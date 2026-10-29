import AppKit
import SwiftUI

struct SettingsView: View {
    @State private var apiKey = ""
    @State private var keyMessage = ""
    private var model = AppModel.shared
    private var settings: AppSettings { model.settings }

    var body: some View {
        Form {
            Section("Permissions") {
                permissionRow("Microphone", granted: model.microphoneGranted) {
                    model.requestPermissions()
                    Permissions.open("Microphone")
                }
                permissionRow("Speech Recognition", granted: model.speechGranted) {
                    model.requestPermissions()
                    Permissions.open("SpeechRecognition")
                }
                permissionRow("Accessibility", granted: model.accessibilityGranted) {
                    _ = Permissions.promptAccessibility()
                    Permissions.open("Accessibility")
                    model.refreshPermissions()
                }
                permissionRow("Hotkeys", granted: model.hotkeysActive) {
                    _ = Permissions.promptInputMonitoring()
                    Permissions.open("ListenEvent")
                    model.refreshPermissions()
                }
                Text("Global keys need Accessibility and Input Monitoring. Paste needs Accessibility.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Transcription") {
                Picker("Mode", selection: Binding(
                    get: { settings.mode },
                    set: { settings.mode = $0 }
                )) {
                    Text("Cleaned").tag(TranscriptionMode.cleaned)
                    Text("Raw").tag(TranscriptionMode.raw)
                }
                TextField("OpenAI model", text: Binding(
                    get: { settings.model },
                    set: { settings.model = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                LabeledContent("API key") {
                    SecureField(settings.hasAPIKey ? "Saved — enter a new key to replace it" : "sk-…", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Button("Save Key") { saveKey() }
                    Button("Remove Key") {
                        settings.clearAPIKey()
                        apiKey = ""
                        keyMessage = "Removed."
                    }
                    if settings.hasAPIKey {
                        Text("A key is saved")
                            .foregroundStyle(.secondary)
                    }
                }
                if !keyMessage.isEmpty {
                    Text(keyMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Cleaned mode sends only the transcript text to OpenAI. Audio stays on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Output") {
                Toggle("Paste into the focused app", isOn: Binding(
                    get: { settings.autoPaste },
                    set: { settings.autoPaste = $0 }
                ))
                Toggle("Play start and stop sounds", isOn: Binding(
                    get: { settings.soundsEnabled },
                    set: { settings.soundsEnabled = $0 }
                ))
            }

            Section("Shortcuts") {
                shortcutRow("Push to talk", value: "Hold \(settings.shortcuts.push.display)", action: .push)
                shortcutRow(
                    "Press to record",
                    value: settings.shortcuts.press?.display ?? "Double-tap \(settings.shortcuts.push.display)",
                    action: .press
                )
                if settings.shortcuts.press != nil {
                    Button("Use double-tap of the push key") {
                        model.useDoubleTapPress()
                    }
                }
                shortcutRow("Cancel", value: settings.shortcuts.cancel.display, action: .cancel)
                shortcutRow("Delete last note", value: settings.shortcuts.delete.display, action: .delete)
                if let rebind = model.rebind {
                    HStack {
                        Text("Press a key for \(rebind.label)… Esc backs out.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel") { model.cancelRebind() }
                    }
                }
            }

        }
        .formStyle(.grouped)
        .padding(12)
        .frame(minWidth: 440, minHeight: 560)
    }

    private func shortcutRow(_ title: String, value: String, action: ShortcutAction) -> some View {
        LabeledContent(title) {
            HStack {
                Text(value)
                    .foregroundStyle(.secondary)
                Button("Change") { model.beginRebind(action) }
            }
        }
    }

    private func permissionRow(_ title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        LabeledContent(title) {
            HStack {
                Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(granted ? .green : .orange)
                if !granted {
                    Button("Open", action: action)
                }
            }
        }
    }

    private func saveKey() {
        do {
            try settings.saveAPIKey(apiKey)
            apiKey = ""
            keyMessage = settings.hasAPIKey ? "Saved." : "Removed."
        } catch {
            keyMessage = error.localizedDescription
        }
    }
}

extension ShortcutAction {
    var label: String {
        switch self {
        case .push: return "push to talk"
        case .press: return "press to record"
        case .cancel: return "cancel"
        case .delete: return "delete last note"
        }
    }
}
