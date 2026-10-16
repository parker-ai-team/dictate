import Foundation
import CoreGraphics
import AppKit

// A session-level CGEvent tap on flagsChanged. Modifier keys (Option, Command,
// Control, Fn) never arrive as keyDown/keyUp, only as flagsChanged, so this is
// the one place to catch them. An active tap needs the Accessibility
// permission; without it tapCreate returns nil and start() reports false.
final class HotkeyMonitor {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var pressed = false
    private(set) var isRunning = false

    @discardableResult
    func start() -> Bool {
        if isRunning { return true }
        let mask: CGEventMask = 1 << CGEventType.flagsChanged.rawValue
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            return monitor.handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.info("hotkey: event tap could not be created (Accessibility not granted?)")
            return false
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
        Log.info("hotkey: event tap active, key = \(Settings.shared.hotkey.rawValue)")
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        isRunning = false
        pressed = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // macOS disables a tap whose callback was slow; re-enable and move on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            Log.info("hotkey: tap was disabled by the system, re-enabled")
            return Unmanaged.passUnretained(event)
        }
        guard type == .flagsChanged else { return Unmanaged.passUnretained(event) }
        let hotkey = Settings.shared.hotkey
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == hotkey.keyCode else { return Unmanaged.passUnretained(event) }
        let isDown = event.flags.contains(hotkey.flag)
        if isDown && !pressed {
            pressed = true
            DispatchQueue.main.async { [weak self] in self?.onPress?() }
        } else if !isDown && pressed {
            pressed = false
            DispatchQueue.main.async { [weak self] in self?.onRelease?() }
        }
        return hotkey.swallowEvent ? nil : Unmanaged.passUnretained(event)
    }
}
