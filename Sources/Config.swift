import Foundation
import CoreGraphics
import Combine

let appVersion = "0.1.0"
// The bundle id is set by scripts/build.sh (DICTATE_BUNDLE_ID). It also names
// the Keychain item and the UserDefaults domain.
let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.parkeraiteam.dictate"

enum HotkeyChoice: String, CaseIterable, Identifiable {
    case rightOption, leftOption, rightCommand, rightControl, fn

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rightOption: return "Right Option (⌥)"
        case .leftOption: return "Left Option (⌥)"
        case .rightCommand: return "Right Command (⌘)"
        case .rightControl: return "Right Control (⌃)"
        case .fn: return "Fn / Globe (🌐) - experimental"
        }
    }

    // Virtual key codes from Carbon HIToolbox Events.h
    var keyCode: Int64 {
        switch self {
        case .rightOption: return 61   // kVK_RightOption
        case .leftOption: return 58    // kVK_Option
        case .rightCommand: return 54  // kVK_RightCommand
        case .rightControl: return 62  // kVK_RightControl
        case .fn: return 63            // kVK_Function
        }
    }

    var flag: CGEventFlags {
        switch self {
        case .rightOption, .leftOption: return .maskAlternate
        case .rightCommand: return .maskCommand
        case .rightControl: return .maskControl
        case .fn: return .maskSecondaryFn
        }
    }

    // Fn is swallowed so the system "press Globe to ..." action does not fire as well.
    var swallowEvent: Bool { self == .fn }
}

enum ActivationMode: String, CaseIterable, Identifiable {
    case hold, toggle
    var id: String { rawValue }
    var label: String {
        switch self {
        case .hold: return "Hold to talk"
        case .toggle: return "Tap to start, tap to stop"
        }
    }
}

final class Settings: ObservableObject {
    static let shared = Settings()

    private let d = UserDefaults.standard

    @Published var hotkey: HotkeyChoice { didSet { d.set(hotkey.rawValue, forKey: "hotkey") } }
    @Published var mode: ActivationMode { didSet { d.set(mode.rawValue, forKey: "mode") } }
    @Published var formattingEnabled: Bool { didSet { d.set(formattingEnabled, forKey: "formattingEnabled") } }
    @Published var formatterModel: String { didSet { d.set(formatterModel, forKey: "formatterModel") } }
    @Published var formatterTimeout: Double { didSet { d.set(formatterTimeout, forKey: "formatterTimeout") } }
    @Published var whisperServerPath: String { didSet { d.set(whisperServerPath, forKey: "whisperServerPath") } }
    @Published var whisperModelPath: String { didSet { d.set(whisperModelPath, forKey: "whisperModelPath") } }
    @Published var whisperPort: Int { didSet { d.set(whisperPort, forKey: "whisperPort") } }
    @Published var playSounds: Bool { didSet { d.set(playSounds, forKey: "playSounds") } }

    private init() {
        hotkey = HotkeyChoice(rawValue: d.string(forKey: "hotkey") ?? "") ?? .rightOption
        mode = ActivationMode(rawValue: d.string(forKey: "mode") ?? "") ?? .hold
        formattingEnabled = d.object(forKey: "formattingEnabled") as? Bool ?? true
        formatterModel = d.string(forKey: "formatterModel") ?? "claude-haiku-5-5"
        formatterTimeout = d.object(forKey: "formatterTimeout") as? Double ?? 2.0
        whisperServerPath = d.string(forKey: "whisperServerPath") ?? "/opt/homebrew/bin/whisper-server"
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        whisperModelPath = d.string(forKey: "whisperModelPath") ?? "\(home)/.cache/whisper/ggml-large-v3-turbo.bin"
        whisperPort = d.object(forKey: "whisperPort") as? Int ?? 8178
        playSounds = d.object(forKey: "playSounds") as? Bool ?? true
    }
}

enum DictateError: Error, LocalizedError {
    case noInputDevice
    case micDenied
    case engineNotReady(String)
    case sttFailed(String)
    case formatterFailed(String)
    case noAPIKey

    var errorDescription: String? {
        switch self {
        case .noInputDevice: return "No microphone input device found"
        case .micDenied: return "Microphone access denied"
        case .engineNotReady(let s): return "Speech engine not ready: \(s)"
        case .sttFailed(let s): return "Transcription failed: \(s)"
        case .formatterFailed(let s): return "Formatting failed: \(s)"
        case .noAPIKey: return "No Anthropic API key in Keychain"
        }
    }
}
