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
                LabeledContent("Push to talk") {
                    Text("Hold Fn")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Press to record") {
                    Text("Double-tap Fn")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Cancel") {
                    Text("Esc")
                        .foregroundStyle(.secondary)
                }
            }

        }
        .formStyle(.grouped)
        .padding(12)
        .frame(minWidth: 440, minHeight: 560)
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
