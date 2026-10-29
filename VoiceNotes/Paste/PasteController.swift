import AppKit
import Foundation

struct ClipboardSnapshot {
    struct Item {
        var payloads: [NSPasteboard.PasteboardType: Data]
    }

    var items: [Item]

    static func capture() -> ClipboardSnapshot {
        let pasteboard = NSPasteboard.general
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            var payloads: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    payloads[type] = data
                }
            }
            return Item(payloads: payloads)
        }
        return ClipboardSnapshot(items: items)
    }

    func restore() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let restored = items.compactMap { item -> NSPasteboardItem? in
            guard !item.payloads.isEmpty else { return nil }
            let pasteboardItem = NSPasteboardItem()
            for (type, data) in item.payloads {
                pasteboardItem.setData(data, forType: type)
            }
            return pasteboardItem
        }
        if !restored.isEmpty {
            pasteboard.writeObjects(restored)
        }
    }
}

@MainActor
final class PasteController {
    func paste(_ text: String, to app: NSRunningApplication?) async {
        let snapshot = ClipboardSnapshot.capture()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let target = app?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : app
        if let target {
            _ = target.activate(from: .current, options: [])
            try? await Task.sleep(for: .milliseconds(140))
        }
        postCommandV(pid: target?.processIdentifier)
        try? await Task.sleep(for: .milliseconds(450))
        if pasteboard.string(forType: .string) == text {
            snapshot.restore()
        }
    }

    private func postCommandV(pid: pid_t?) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        if let pid {
            down.postToPid(pid)
            up.postToPid(pid)
        } else {
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }
}
