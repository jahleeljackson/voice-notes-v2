import AppKit
import SwiftUI

@main
struct VoiceNotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
        } label: {
            MenuBarIcon()
        }
        .menuBarExtraStyle(.menu)

        Window("Notes", id: "notes") {
            HistoryView()
        }
        .defaultSize(width: 860, height: 560)

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }
        NSApp.setActivationPolicy(.accessory)
        AppModel.shared.start()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppModel.shared.noteBecameActive()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.shutdown()
    }
}
