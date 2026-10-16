import Foundation
import AppKit
import AVFoundation
import ApplicationServices

enum Permissions {
    static func accessibilityGranted(prompt: Bool = false) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    static func micStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    static func requestMic() async -> Bool {
        switch micStatus() {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { cont in
                AVCaptureDevice.requestAccess(for: .audio) { ok in cont.resume(returning: ok) }
            }
        default: return false
        }
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openMicSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    static func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private static func open(_ s: String) {
        if let url = URL(string: s) { NSWorkspace.shared.open(url) }
    }

    static func micStatusLabel() -> String {
        switch micStatus() {
        case .authorized: return "granted"
        case .denied: return "denied - enable in System Settings"
        case .restricted: return "restricted"
        case .notDetermined: return "not asked yet - first recording will ask"
        @unknown default: return "unknown"
        }
    }
}
