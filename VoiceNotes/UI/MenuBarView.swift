import AppKit
import SwiftUI

struct MenuBarIcon: View {
    private var model = AppModel.shared

    var body: some View {
        Image(systemName: model.statusSymbol)
            .accessibilityLabel("Voice Notes")
    }
}

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    private var model = AppModel.shared

    var body: some View {
        Text(model.settings.shortcuts.pushLegend)
        Text(model.settings.shortcuts.pressLegend)
        Text(model.settings.shortcuts.cancelLegend)
        Text(model.settings.shortcuts.deleteLegend)
        Divider()
        Button("Transcription: \(model.settings.mode.title)") {
            model.toggleMode()
        }
        Button("Paste Last Note") {
            model.pasteLastNote()
        }
        Button("Notes") {
            NSApp.activate()
            openWindow(id: "notes")
        }
        SettingsLink {
            Text("Settings…")
        }
        Divider()
        Text(permissionSummary)
        Button("Refresh Permissions") {
            model.refreshPermissions()
        }
        Divider()
        Button("Quit Voice Notes") {
            NSApp.terminate(nil)
        }
    }

    private var permissionSummary: String {
        if model.hotkeysActive && model.microphoneGranted && model.speechGranted {
            return "Microphone, speech, and hotkeys are ready"
        }
        var missing: [String] = []
        if !model.microphoneGranted { missing.append("microphone") }
        if !model.speechGranted { missing.append("speech") }
        if !model.hotkeysActive { missing.append("hotkeys") }
        return "Needs " + missing.joined(separator: ", ")
    }
}
