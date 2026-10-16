import Foundation
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let controller = DictationController()
    private let hotkey = HotkeyMonitor()
    private let settingsWindow = SettingsWindowController()
    private var statusMenuItem: NSMenuItem!
    private var toggleMenuItem: NSMenuItem!
    private var accessibilityTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.info("app: Dictate \(appVersion) launched, bundle \(Bundle.main.bundleIdentifier ?? "none")")
        setupStatusItem()
        controller.onStateChange = { [weak self] s in self?.refreshStatus(s) }
        hotkey.onPress = { [weak self] in self?.controller.hotkeyPressed() }
        hotkey.onRelease = { [weak self] in self?.controller.hotkeyReleased() }

        // Warm the speech engine right away so the first dictation is fast.
        Task { await controller.stt.ensureRunning() }

        if Permissions.accessibilityGranted(prompt: true) {
            startHotkey()
        } else {
            Log.info("app: Accessibility not granted, polling until it is")
            setStatusText("Dictate - needs Accessibility permission")
            accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                guard let self, Permissions.accessibilityGranted() else { return }
                self.accessibilityTimer?.invalidate()
                self.accessibilityTimer = nil
                self.startHotkey()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkey.stop()
        controller.stt.stop()
        Log.info("app: quit")
    }

    private func startHotkey() {
        if hotkey.start() {
            refreshStatus(.idle)
        } else {
            setStatusText("Dictate - hotkey tap failed (grant Accessibility, then relaunch)")
        }
    }

    // Custom template icon from Resources (waveform + cursor); falls back to the
    // SF Symbol if the bundle lacks it (e.g. a build without make-icon.sh).
    private lazy var menuIcon: NSImage = {
        if let img = Bundle.main.image(forResource: "MenuBarTemplate") {
            img.isTemplate = true
            img.size = NSSize(width: 18, height: 18)
            Log.info("icon: custom menu-bar template loaded")
            return img
        }
        Log.info("icon: MenuBarTemplate.png missing, using SF Symbol")
        return NSImage(systemSymbolName: "mic", accessibilityDescription: "Dictate")!
    }()

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = menuIcon
        let menu = NSMenu()
        statusMenuItem = NSMenuItem(title: "Dictate - starting", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        toggleMenuItem = NSMenuItem(title: "Start dictation", action: #selector(toggleDictation), keyEquivalent: "")
        toggleMenuItem.target = self
        menu.addItem(toggleMenuItem)
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let restart = NSMenuItem(title: "Restart speech engine", action: #selector(restartEngine), keyEquivalent: "")
        restart.target = self
        menu.addItem(restart)
        let log = NSMenuItem(title: "Open log", action: #selector(openLog), keyEquivalent: "")
        log.target = self
        menu.addItem(log)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Dictate", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func setStatusText(_ s: String) {
        statusMenuItem.title = s
    }

    private func refreshStatus(_ state: DictationController.State) {
        let s = Settings.shared
        let keyLabel = s.hotkey.label
        switch state {
        case .idle:
            statusItem.button?.image = menuIcon
            statusItem.button?.contentTintColor = nil
            setStatusText("Dictate - ready (\(keyLabel), \(s.mode == .hold ? "hold" : "toggle"))")
            toggleMenuItem.title = "Start dictation"
        case .recording:
            statusItem.button?.image = menuIcon
            statusItem.button?.contentTintColor = .systemRed
            setStatusText("Dictate - listening")
            toggleMenuItem.title = "Stop dictation"
        case .processing:
            statusItem.button?.image = menuIcon
            statusItem.button?.contentTintColor = .systemOrange
            setStatusText("Dictate - processing")
            toggleMenuItem.title = "Processing…"
        }
    }

    @objc private func toggleDictation() { controller.toggleFromMenu() }

    @objc private func openSettings() { settingsWindow.show(controller: controller) }

    @objc private func restartEngine() {
        Task { _ = await controller.stt.restart() }
    }

    @objc private func openLog() { NSWorkspace.shared.open(URL(fileURLWithPath: Log.path)) }

    @objc private func quit() { NSApp.terminate(nil) }
}
