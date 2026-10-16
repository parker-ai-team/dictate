import Foundation
import AppKit
import SwiftUI

// Orchestrates one dictation: hotkey -> mic -> whisper -> formatter -> paste.
final class DictationController {
    enum State { case idle, recording, processing }

    private(set) var state: State = .idle
    let recorder = AudioRecorder()
    let stt = WhisperServerSTT()
    let indicator = Indicator()
    var onStateChange: ((State) -> Void)?

    private let minimumDuration = 0.35

    var formatter: TextFormatter {
        let s = Settings.shared
        guard s.formattingEnabled else { return PassthroughFormatter() }
        return ClaudeFormatter(model: s.formatterModel, timeout: s.formatterTimeout)
    }

    // Hotkey went down.
    func hotkeyPressed() {
        switch Settings.shared.mode {
        case .hold:
            if state == .idle { startRecording() }
        case .toggle:
            if state == .idle { startRecording() } else if state == .recording { stopAndProcess() }
        }
    }

    // Hotkey came up.
    func hotkeyReleased() {
        if Settings.shared.mode == .hold, state == .recording { stopAndProcess() }
    }

    // Menu "Start / stop dictation" entry, works in both modes.
    func toggleFromMenu() {
        if state == .idle { startRecording() } else if state == .recording { stopAndProcess() }
    }

    private func setState(_ s: State) {
        state = s
        onStateChange?(s)
    }

    func startRecording() {
        guard state == .idle else { return }
        Task { @MainActor in
            let ok = await Permissions.requestMic()
            guard ok else {
                Log.info("mic: permission \(Permissions.micStatusLabel())")
                indicator.show("Microphone access needed", color: .orange, autoHide: 3)
                Permissions.openMicSettings()
                return
            }
            do {
                try recorder.start()
            } catch {
                Log.info("mic: start failed: \(error.localizedDescription)")
                indicator.show("Mic error: \(error.localizedDescription)", color: .orange, autoHide: 3)
                return
            }
            setState(.recording)
            indicator.show("Listening - \(Settings.shared.mode == .hold ? "release to finish" : "tap again to finish")")
            if Settings.shared.playSounds { NSSound(named: "Tink")?.play() }
            Log.info("rec: started")
            // Warm the engine in parallel with the user speaking.
            Task { await stt.ensureRunning() }
        }
    }

    func stopAndProcess() {
        guard state == .recording else { return }
        let samples = recorder.stop()
        let audioEnd = Date()
        setState(.processing)
        if Settings.shared.playSounds { NSSound(named: "Pop")?.play() }
        let duration = AudioRecorder.duration(of: samples)
        Log.info(String(format: "rec: stopped, %.2fs of audio", duration))
        guard duration >= minimumDuration else {
            indicator.hide()
            setState(.idle)
            return
        }
        indicator.show("Transcribing…", color: .yellow)
        let formatter = self.formatter
        Task {
            do {
                let wav = AudioRecorder.wavData(from: samples)
                let raw = try await stt.transcribe(wav: wav)
                let sttDone = Date()
                let sttMs = Int(sttDone.timeIntervalSince(audioEnd) * 1000)
                guard !raw.isEmpty else {
                    Log.info("stt: no speech detected (\(sttMs) ms)")
                    await MainActor.run {
                        indicator.show("No speech detected", color: .gray, autoHide: 1.5)
                        setState(.idle)
                    }
                    return
                }
                let (final, fmtMs, fmtNote) = await Self.runFormatter(formatter, raw: raw) {
                    await MainActor.run { self.indicator.show("Formatting…", color: .blue) }
                }
                await MainActor.run {
                    TextInserter.insert(TextInserter.finalize(final))
                    let totalMs = Int(Date().timeIntervalSince(audioEnd) * 1000)
                    Log.info("done: audio \(String(format: "%.1f", duration))s | stt \(sttMs) ms, \(raw.count) chars | format \(fmtMs) ms (\(fmtNote)), \(final.count) chars | total \(totalMs) ms")
                    indicator.show("Inserted (\(String(format: "%.1f", Double(totalMs) / 1000))s)", color: .green, autoHide: 1.2)
                    setState(.idle)
                }
            } catch {
                Log.info("pipeline error: \(error.localizedDescription)")
                await MainActor.run {
                    indicator.show("Error: \(error.localizedDescription)", color: .orange, autoHide: 4)
                    setState(.idle)
                }
            }
        }
    }

    // Runs the cleanup pass; any failure returns the raw transcript.
    static func runFormatter(_ formatter: TextFormatter, raw: String, onStart: () async -> Void) async -> (String, Int, String) {
        if formatter is PassthroughFormatter { return (raw, 0, "off") }
        await onStart()
        let t = Date()
        do {
            let text = try await formatter.format(raw)
            return (text, Int(Date().timeIntervalSince(t) * 1000), "ok")
        } catch {
            return (raw, Int(Date().timeIntervalSince(t) * 1000), "fallback to raw: \(error.localizedDescription)")
        }
    }

    // Headless self-test used by the build verification: same STT + formatter
    // path as a real dictation, fed from a WAV file instead of the mic.
    func selfTest(wavPath: String, formatting: Bool) async -> Int32 {
        guard let wav = FileManager.default.contents(atPath: wavPath) else {
            print("[selftest] cannot read \(wavPath)")
            return 2
        }
        let fmt: TextFormatter = formatting
            ? ClaudeFormatter(model: Settings.shared.formatterModel, timeout: Settings.shared.formatterTimeout)
            : PassthroughFormatter()
        print("[selftest] file=\(wavPath) bytes=\(wav.count) formatter=\(fmt.name)")
        let warm = Date()
        let ready = await stt.ensureRunning()
        print(String(format: "[selftest] engine ready=%@ after %.2fs", ready ? "yes" : "no", Date().timeIntervalSince(warm)))
        guard ready else { return 3 }
        let t0 = Date()
        do {
            let raw = try await stt.transcribe(wav: wav)
            let t1 = Date()
            print("[selftest] stt \(String(format: "%.2f", t1.timeIntervalSince(t0)))s raw=\"\(raw)\"")
            var final = raw
            if formatting {
                do {
                    final = try await fmt.format(raw)
                    print("[selftest] format \(String(format: "%.2f", Date().timeIntervalSince(t1)))s text=\"\(final)\"")
                } catch {
                    print("[selftest] format FAILED after \(String(format: "%.2f", Date().timeIntervalSince(t1)))s -> raw used: \(error.localizedDescription)")
                }
            }
            let inserted = TextInserter.finalize(final)
            print("[selftest] inserted=\"\(inserted)\" (ends with: \(inserted.suffix(2).map { $0 == " " ? "<space>" : String($0) }.joined()))")
            print(String(format: "[selftest] total audio-end -> text: %.2fs (%d chars)", Date().timeIntervalSince(t0), inserted.count))
            return 0
        } catch {
            print("[selftest] FAILED: \(error.localizedDescription)")
            return 4
        }
    }
}
