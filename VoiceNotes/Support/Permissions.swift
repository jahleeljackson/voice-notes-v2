import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum Permissions {
    static var accessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static var inputMonitoringTrusted: Bool {
        CGPreflightListenEventAccess()
    }

    @discardableResult
    static func promptAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    static func promptInputMonitoring() -> Bool {
        CGRequestListenEventAccess()
    }

    @discardableResult
    static func open(_ pane: String) -> String {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_\(pane)",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_\(pane)"
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return candidate
            }
        }
        return "failed"
    }
}
