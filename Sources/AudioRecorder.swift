import Foundation
import AVFoundation

// Captures the default input device and resamples to 16 kHz mono Float32,
// which is what whisper.cpp expects. A fresh AVAudioEngine per recording
// keeps device changes (headset in/out) from wedging a long-lived engine.
final class AudioRecorder {
    static let sampleRate: Double = 16_000

    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var samples: [Float] = []
    private let lock = NSLock()
    private(set) var isRecording = false

    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!

    func start() throws {
        lock.lock(); samples.removeAll(keepingCapacity: true); lock.unlock()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else {
            throw DictateError.noInputDevice
        }
        guard let conv = AVAudioConverter(from: inFormat, to: targetFormat) else {
            throw DictateError.noInputDevice
        }
        converter = conv
        input.installTap(onBus: 0, bufferSize: 2048, format: inFormat) { [weak self] buffer, _ in
            self?.append(buffer)
        }
        engine.prepare()
        try engine.start()
        self.engine = engine
        isRecording = true
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, let ch = out.floatChannelData else { return }
        let n = Int(out.frameLength)
        guard n > 0 else { return }
        lock.lock()
        samples.append(contentsOf: UnsafeBufferPointer(start: ch[0], count: n))
        lock.unlock()
    }

    // Returns 16 kHz mono samples.
    func stop() -> [Float] {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        converter = nil
        isRecording = false
        lock.lock(); defer { lock.unlock() }
        let s = samples
        samples = []
        return s
    }

    static func duration(of samples: [Float]) -> Double {
        Double(samples.count) / sampleRate
    }

    // 16-bit PCM WAV, 16 kHz mono. whisper.cpp rejects clips under 1 s, so
    // short clips are padded with silence to 1.2 s.
    static func wavData(from input: [Float]) -> Data {
        var samples = input
        let minSamples = Int(sampleRate * 1.2)
        if samples.count < minSamples {
            samples.append(contentsOf: [Float](repeating: 0, count: minSamples - samples.count))
        }
        let dataSize = samples.count * 2
        var d = Data(capacity: 44 + dataSize)
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append("RIFF".data(using: .ascii)!)
        u32(UInt32(36 + dataSize))
        d.append("WAVE".data(using: .ascii)!)
        d.append("fmt ".data(using: .ascii)!)
        u32(16)
        u16(1)                       // PCM
        u16(1)                       // mono
        u32(UInt32(sampleRate))
        u32(UInt32(sampleRate) * 2)  // byte rate
        u16(2)                       // block align
        u16(16)                      // bits per sample
        d.append("data".data(using: .ascii)!)
        u32(UInt32(dataSize))
        var pcm = [Int16](repeating: 0, count: samples.count)
        for i in 0..<samples.count {
            let v = max(-1.0, min(1.0, samples[i]))
            pcm[i] = Int16(v * 32767.0)
        }
        pcm.withUnsafeBufferPointer { d.append(Data(buffer: $0)) }
        return d
    }
}
