import AVFoundation
import CoreGraphics
import Foundation

final class HotkeyMonitor {
    var onEffects: (([HotkeyStateMachine.Effect]) -> Void)?
    var onRebind: ((ShortcutAction, KeyCombo) -> Void)?
    var onRebindCancelled: (() -> Void)?

    private var machine = HotkeyStateMachine()
    private var router = HotkeyRouter(shortcuts: .default)
    private let lock = NSLock()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var armToken = 0
    private var tapToken = 0
    private(set) var isInstalled = false

    func start() {
        guard tap == nil else { return }
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: hotkeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            isInstalled = false
            return
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isInstalled = true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        isInstalled = false
    }

    func noteSessionEnded() {
        lock.lock()
        machine.noteSessionEnded()
        lock.unlock()
    }

    func forceIdle() {
        lock.lock()
        machine.forceIdle()
        armToken += 1
        tapToken += 1
        lock.unlock()
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        let physical = physicalEvent(type: type, event: event)
        if let rebound = capturedRebind(physical) {
            switch rebound {
            case .assigned(let action, let combo):
                DispatchQueue.main.async { [weak self] in
                    self?.onRebind?(action, combo)
                }
            case .cancelled:
                DispatchQueue.main.async { [weak self] in
                    self?.onRebindCancelled?()
                }
            case .ignore:
                break
            }
            return nil
        }

        let swallow = ingest(physical)
        return swallow ? nil : Unmanaged.passUnretained(event)
    }

    private func physicalEvent(type: CGEventType, event: CGEvent) -> PhysicalKeyEvent {
        let flags = event.flags
        let kind: PhysicalKeyEvent.Kind
        switch type {
        case .keyDown: kind = .keyDown
        case .keyUp: kind = .keyUp
        default: kind = .flagsChanged
        }
        return PhysicalKeyEvent(
            kind: kind,
            keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
            control: flags.contains(.maskControl),
            option: flags.contains(.maskAlternate),
            shift: flags.contains(.maskShift),
            command: flags.contains(.maskCommand),
            function: flags.contains(.maskSecondaryFn),
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) == 1
        )
    }

    private func ingest(_ physical: PhysicalKeyEvent) -> Bool {
        lock.lock()
        let (shortcuts, _) = ShortcutSync.box.snapshot()
        router.shortcuts = shortcuts
        router.capturesCancel = machine.capturesCancel
        machine.pressIsDoubleTapOfPushKey = true
        let routed = router.route(physical)
        var effects: [HotkeyStateMachine.Effect] = []
        let now = ProcessInfo.processInfo.systemUptime
        for event in routed.events {
            effects.append(contentsOf: machine.handle(event, at: now))
        }
        let timers = takeTimers(from: effects)
        lock.unlock()
        schedule(timers)
        deliver(effects.filter { !$0.isTimer })
        return routed.swallow
    }

    private func feed(_ event: HotkeyStateMachine.Event) {
        lock.lock()
        machine.pressIsDoubleTapOfPushKey = true
        let effects = machine.handle(event, at: ProcessInfo.processInfo.systemUptime)
        let timers = takeTimers(from: effects)
        lock.unlock()
        schedule(timers)
        deliver(effects.filter { !$0.isTimer })
    }

    private func takeTimers(from effects: [HotkeyStateMachine.Effect]) -> [(String, Int, TimeInterval)] {
        var scheduled: [(String, Int, TimeInterval)] = []
        for effect in effects {
            switch effect {
            case .scheduleArm:
                armToken += 1
                scheduled.append(("arm", armToken, HotkeyStateMachine.armDelay))
            case .cancelArm:
                armToken += 1
            case .scheduleTapWindow:
                tapToken += 1
                scheduled.append(("tap", tapToken, HotkeyStateMachine.doubleTapWindow))
            case .cancelTapWindow:
                tapToken += 1
            default:
                break
            }
        }
        return scheduled
    }

    private func schedule(_ timers: [(String, Int, TimeInterval)]) {
        for timer in timers {
            DispatchQueue.main.asyncAfter(deadline: .now() + timer.2) { [weak self] in
                self?.fire(kind: timer.0, token: timer.1)
            }
        }
    }

    private func fire(kind: String, token: Int) {
        lock.lock()
        let current = kind == "arm" ? armToken : tapToken
        lock.unlock()
        guard current == token else { return }
        feed(kind == "arm" ? .armElapsed : .tapWindowElapsed)
    }

    private func deliver(_ effects: [HotkeyStateMachine.Effect]) {
        guard !effects.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onEffects?(effects)
        }
    }

    private enum RebindResult {
        case assigned(ShortcutAction, KeyCombo)
        case cancelled
        case ignore
    }

    private func capturedRebind(_ event: PhysicalKeyEvent) -> RebindResult? {
        let (_, action) = ShortcutSync.box.snapshot()
        guard let action else { return nil }
        if event.isRepeat { return .ignore }
        let plainEscape = event.kind == .keyDown
            && event.keyCode == 53
            && !event.control && !event.option && !event.shift && !event.command
        if plainEscape && action != .cancel {
            return .cancelled
        }
        if event.kind == .flagsChanged && event.keyCode == 63 && event.function {
            return .assigned(action, .fn)
        }
        let modifiers: Set<UInt16> = [54, 55, 56, 58, 59, 60, 61, 62]
        if event.kind == .keyDown && !modifiers.contains(event.keyCode) {
            var combo = event.combo
            if combo.keyCode == 63 && !combo.control && !combo.option && !combo.shift && !combo.command {
                combo = .fn
            }
            if action == .push {
                combo.function = combo.keyCode == 63
            }
            return .assigned(action, combo)
        }
        return .ignore
    }
}

private func hotkeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    return monitor.handle(type: type, event: event)
}
