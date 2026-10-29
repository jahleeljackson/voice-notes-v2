import Foundation

struct HotkeyRouter {
    struct RouteResult: Equatable {
        var events: [HotkeyStateMachine.Event]
        var swallow: Bool
    }

    var shortcuts: ShortcutMap
    var capturesCancel = false
    private var pushIsDown = false
    private var swallowCancelRelease = false

    init(shortcuts: ShortcutMap, capturesCancel: Bool = false) {
        self.shortcuts = shortcuts
        self.capturesCancel = capturesCancel
    }

    /// Right Option records. Esc cancels an active session.
    /// Every other key, including Left Option and Fn, is passed through so typing keeps working.
    mutating func route(_ event: PhysicalKeyEvent) -> RouteResult {
        if event.keyCode == shortcuts.cancel.keyCode {
            return routeCancel(event)
        }
        guard event.keyCode == shortcuts.push.keyCode, event.kind == .flagsChanged else {
            return RouteResult(events: [], swallow: false)
        }

        let down = rightOptionIsDown(event)
        var events: [HotkeyStateMachine.Event] = []
        if down && !pushIsDown {
            events.append(.pushDown)
        } else if !down && pushIsDown {
            events.append(.pushUp)
        }
        pushIsDown = down
        return RouteResult(events: events, swallow: true)
    }

    /// Prefer the Right Option device flag. If the tap omitted it, a flags-changed
    /// event for this key still means the key itself changed.
    private func rightOptionIsDown(_ event: PhysicalKeyEvent) -> Bool {
        if event.rightOption { return true }
        if !event.option { return false }
        return !pushIsDown
    }

    private mutating func routeCancel(_ event: PhysicalKeyEvent) -> RouteResult {
        let plain = !event.control && !event.shift && !event.command
        if event.kind == .keyDown && plain && !event.isRepeat {
            var swallow = false
            if capturesCancel {
                swallow = true
                swallowCancelRelease = true
            }
            return RouteResult(events: [.cancel], swallow: swallow)
        }
        if swallowCancelRelease && (event.kind == .keyDown || event.kind == .keyUp) {
            if event.kind == .keyUp {
                swallowCancelRelease = false
            }
            return RouteResult(events: [], swallow: true)
        }
        return RouteResult(events: [], swallow: false)
    }
}
