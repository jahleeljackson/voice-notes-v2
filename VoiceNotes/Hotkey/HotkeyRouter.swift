import Foundation

struct HotkeyRouter {
    struct RouteResult: Equatable {
        var events: [HotkeyStateMachine.Event]
        var swallow: Bool
    }

    var shortcuts: ShortcutMap
    var capturesCancel = false
    private var functionIsDown = false
    private var pushIsDown = false

    init(shortcuts: ShortcutMap, capturesCancel: Bool = false) {
        self.shortcuts = shortcuts
        self.capturesCancel = capturesCancel
    }

    mutating func route(_ event: PhysicalKeyEvent) -> RouteResult {
        if event.isRepeat {
            let swallow = shortcuts.push.isFunctionAlone
                ? event.keyCode == 63
                : event.keyCode == shortcuts.push.keyCode && pushIsDown
            return RouteResult(events: [], swallow: swallow)
        }

        var events: [HotkeyStateMachine.Event] = []
        var swallow = false

        if shortcuts.push.isFunctionAlone {
            if event.function && !functionIsDown {
                events.append(.pushDown)
                swallow = true
            } else if !event.function && functionIsDown {
                events.append(.pushUp)
                swallow = true
            }
            functionIsDown = event.function
            if event.keyCode == 63 {
                swallow = true
            }
        } else if event.kind == .keyDown && shortcuts.push.matches(event) {
            events.append(.pushDown)
            pushIsDown = true
            swallow = true
        } else if event.kind == .keyUp && event.keyCode == shortcuts.push.keyCode && pushIsDown {
            events.append(.pushUp)
            pushIsDown = false
            swallow = true
        }

        if event.kind == .keyDown, let press = shortcuts.press, press.matches(event) {
            events.append(.pressDown)
            swallow = true
        }

        if event.kind == .keyDown && shortcuts.delete.matches(event) {
            events.append(.delete)
            swallow = true
        }

        if event.kind == .keyDown && shortcuts.cancel.matches(event) {
            events.append(.cancel)
            if capturesCancel {
                swallow = true
            }
        }

        return RouteResult(events: events, swallow: swallow)
    }
}
