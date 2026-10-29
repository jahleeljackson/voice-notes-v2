import Foundation

struct HotkeyRouter {
    struct RouteResult: Equatable {
        var events: [HotkeyStateMachine.Event]
        var swallow: Bool
    }

    var shortcuts: ShortcutMap
    var capturesCancel = false
    private var functionIsDown = false

    init(shortcuts: ShortcutMap, capturesCancel: Bool = false) {
        self.shortcuts = shortcuts
        self.capturesCancel = capturesCancel
    }

    /// Only the Fn key (key code 63) records. Arrow keys and other keys often
    /// carry the Fn flag on macOS, so the flag alone must not start listening.
    /// Esc is the only other key the app handles.
    mutating func route(_ event: PhysicalKeyEvent) -> RouteResult {
        if event.isRepeat {
            return RouteResult(events: [], swallow: event.keyCode == KeyCombo.fn.keyCode)
        }

        var events: [HotkeyStateMachine.Event] = []
        var swallow = false

        if event.keyCode == KeyCombo.fn.keyCode {
            if event.function && !functionIsDown {
                events.append(.pushDown)
            } else if !event.function && functionIsDown {
                events.append(.pushUp)
            }
            functionIsDown = event.function
            swallow = true
        }

        if event.kind == .keyDown && event.keyCode == KeyCombo.escape.keyCode {
            events.append(.cancel)
            if capturesCancel {
                swallow = true
            }
        }

        return RouteResult(events: events, swallow: swallow)
    }
}
