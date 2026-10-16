import Foundation
import AppKit
import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var settings: Settings
    weak var controller: DictationController?

    @State private var apiKeyInput = ""
    @State private var keyStatus = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginStatus = ""
    @State private var engineStatus = ""
    @State private var axGranted = Permissions.accessibilityGranted()
    @State private var micLabel = Permissions.micStatusLabel()

    var body: some View {
        Form {
            Section("Hotkey") {
                Picker("Key", selection: $settings.hotkey) {
                    ForEach(HotkeyChoice.allCases) { Text($0.label).tag($0) }
                }
                Picker("Mode", selection: $settings.mode) {
                    ForEach(ActivationMode.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Play start / stop sounds", isOn: $settings.playSounds)
                Text("Fn needs System Settings > Keyboard > \"Press 🌐 key to\" set to \"Do Nothing\", and no other tool may be using Fn at the same time.")
                    .font(.caption).foregroundColor(.secondary)
            }

            Section("Formatting (cleanup pass)") {
                Toggle("Clean up transcript with Claude", isOn: $settings.formattingEnabled)
                TextField("Model", text: $settings.formatterModel)
                HStack {
                    Text("Timeout (s)")
                    Slider(value: $settings.formatterTimeout, in: 1...6, step: 0.5)
                    Text(String(format: "%.1f", settings.formatterTimeout)).frame(width: 30)
                }
                Text("Off = the raw transcript is inserted. On a timeout or API error the raw transcript is inserted too. Only text is sent, never audio.")
                    .font(.caption).foregroundColor(.secondary)
            }

            Section("Anthropic API key (stored in macOS Keychain)") {
                SecureField("Paste a key to replace the stored one", text: $apiKeyInput)
                HStack {
                    Button("Save to Keychain") {
                        if Keychain.writeAPIKey(apiKeyInput) {
                            keyStatus = "Saved. Key length \(Keychain.keyLength())."
                            apiKeyInput = ""
                        } else {
                            keyStatus = "Save failed."
                        }
                    }.disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    Text(keyStatus.isEmpty
                         ? (Keychain.hasAPIKey() ? "Key present (length \(Keychain.keyLength()))." : "No key stored.")
                         : keyStatus)
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            Section("Speech engine (local whisper.cpp)") {
                TextField("whisper-server", text: $settings.whisperServerPath)
                TextField("Model file", text: $settings.whisperModelPath)
                TextField("Port", value: $settings.whisperPort, format: .number)
                HStack {
                    Button("Restart engine") {
                        engineStatus = "Restarting…"
                        Task {
                            let ok = await controller?.stt.restart() ?? false
                            await MainActor.run {
                                engineStatus = ok ? "Engine ready." : "Engine failed: \(controller?.stt.lastError ?? "unknown")"
                            }
                        }
                    }
                    Text(engineStatus).font(.caption).foregroundColor(.secondary)
                }
            }

            Section("Permissions") {
                HStack {
                    Text("Microphone: \(micLabel)")
                    Spacer()
                    Button("Open Settings") { Permissions.openMicSettings() }
                }
                HStack {
                    Text("Accessibility: \(axGranted ? "granted" : "NOT granted - hotkey and paste will not work")")
                    Spacer()
                    Button("Open Settings") { Permissions.openAccessibilitySettings() }
                }
                Button("Re-check") {
                    axGranted = Permissions.accessibilityGranted()
                    micLabel = Permissions.micStatusLabel()
                }
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginStatus = on ? "Registered." : "Removed."
                        } catch {
                            loginStatus = "Failed: \(error.localizedDescription)"
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Text(loginStatus).font(.caption).foregroundColor(.secondary)
            }

            Section {
                HStack {
                    Text("Dictate \(appVersion) - log: \(Log.path)").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button("Open log") { NSWorkspace.shared.open(URL(fileURLWithPath: Log.path)) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .padding(.bottom, 8)
    }
}

final class SettingsWindowController {
    private var window: NSWindow?

    func show(controller: DictationController) {
        if window == nil {
            let view = SettingsView(controller: controller).environmentObject(Settings.shared)
            let hosting = NSHostingController(rootView: view)
            let w = NSWindow(contentViewController: hosting)
            w.title = "Dictate Settings"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
