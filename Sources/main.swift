import Foundation
import AppKit

// Headless modes:
//   Dictate --selftest <wav> [--no-format]   run STT (+ formatter) on a file, print timings
//   Dictate --version
// Debug-only (compiled in by `scripts/build.sh --debug`, never in a normal build,
// because they let any local process drive our Accessibility grant):
//   Dictate --insert "<text>"                 paste text into the frontmost app
//   Dictate --hotkey-test [seconds]           print hotkey press/release events
let args = CommandLine.arguments
if args.count >= 3, args[1] == "--selftest" {
    let formatting = !args.contains("--no-format")
    let controller = DictationController()
    let sem = DispatchSemaphore(value: 0)
    var code: Int32 = 0
    Task {
        code = await controller.selfTest(wavPath: args[2], formatting: formatting)
        if args.contains("--stop-engine") { controller.stt.stop() }
        sem.signal()
    }
    sem.wait()
    exit(code)
}
#if DICTATE_DEBUG
if args.count >= 3, args[1] == "--insert" {
    let text = args[2]
    let delay = Double(args.count >= 4 ? args[3] : "0.5") ?? 0.5
    Thread.sleep(forTimeInterval: delay)
    let finalized = TextInserter.finalize(text)
    TextInserter.insert(finalized)
    RunLoop.main.run(until: Date().addingTimeInterval(TextInserter.restoreDelay + 0.3))
    print("[insert] posted Cmd+V with \(finalized.count) chars (finalized), pasteboard restored")
    exit(0)
}
if args.count >= 2, args[1] == "--hotkey-test" {
    // Prints press/release for the configured hotkey for N seconds (default 10).
    let seconds = Double(args.count >= 3 ? args[2] : "10") ?? 10
    let monitor = HotkeyMonitor()
    monitor.onPress = { print("[hotkey] press  \(Date())"); fflush(stdout) }
    monitor.onRelease = { print("[hotkey] release \(Date())"); fflush(stdout) }
    let ok = monitor.start()
    print("[hotkey] tap started=\(ok) key=\(Settings.shared.hotkey.rawValue) accessibility=\(Permissions.accessibilityGranted())")
    fflush(stdout)
    if ok { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
    monitor.stop()
    exit(ok ? 0 : 1)
}
#else
if args.count >= 2, args[1] == "--insert" || args[1] == "--hotkey-test" {
    print("\(args[1]) is only available in a debug build (scripts/build.sh --debug)")
    exit(2)
}
#endif
if args.contains("--version") {
    print("Dictate \(appVersion)")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
