import Foundation

/// Hold the push key to record. A quick double tap starts hands-free.
/// One more tap stops hands-free. Releasing before `shortHold` does not paste.
struct HotkeyStateMachine {
    enum Phase: Equatable {
        case idle
        case arming
        case pushRecording
        case awaitingSecondTap(Purpose)
        case handsFree
        case handsFreeKeyDown
        case handsFreeHolding
        case processing
    }

    enum Purpose: Equatable {
        case startHandsFree
        case stopHandsFree
    }

    enum Event: Equatable {
        case pushDown
        case pushUp
        case pressDown
        case cancel
        case delete
        case armElapsed
        case tapWindowElapsed
    }

    enum Effect: Equatable {
        case scheduleArm
        case cancelArm
        case scheduleTapWindow
        case cancelTapWindow
        case startPush
        case startHandsFree
        case finish
        case cancelSession
        case deleteLast

        var isTimer: Bool {
            switch self {
            case .scheduleArm, .cancelArm, .scheduleTapWindow, .cancelTapWindow:
                return true
            default:
                return false
            }
        }
    }

    static let armDelay: TimeInterval = 0.18
    static let shortHold: TimeInterval = 0.50
    static let doubleTapWindow: TimeInterval = 0.45

    private(set) var phase: Phase = .idle
    var pressIsDoubleTapOfPushKey = true
    private var downAt: TimeInterval?
    private var lastUpAt: TimeInterval?

    var capturesCancel: Bool {
        switch phase {
        case .pushRecording, .handsFree, .handsFreeKeyDown, .handsFreeHolding, .processing:
            return true
        case .awaitingSecondTap(.stopHandsFree):
            return true
        default:
            return false
        }
    }

    mutating func noteSessionEnded() {
        guard phase == .processing else { return }
        phase = .idle
        downAt = nil
        lastUpAt = nil
    }

    mutating func forceIdle() {
        phase = .idle
        downAt = nil
        lastUpAt = nil
    }

    mutating func handle(_ event: Event, at time: TimeInterval) -> [Effect] {
        switch event {
        case .delete:
            return [.deleteLast]
        case .cancel:
            guard phase != .idle else { return [] }
            return clearToIdle() + [.cancelSession]
        default:
            break
        }

        switch phase {
        case .idle:
            return handleIdle(event, at: time)
        case .arming:
            return handleArming(event, at: time)
        case .pushRecording:
            return handlePushRecording(event, at: time)
        case .awaitingSecondTap(let purpose):
            return handleAwaiting(purpose, event, at: time)
        case .handsFree:
            return handleHandsFree(event, at: time)
        case .handsFreeKeyDown:
            return handleHandsFreeKeyDown(event, at: time)
        case .handsFreeHolding:
            return handleHandsFreeHolding(event)
        case .processing:
            return []
        }
    }

    private mutating func handleIdle(_ event: Event, at time: TimeInterval) -> [Effect] {
        switch event {
        case .pushDown:
            phase = .arming
            downAt = time
            return [.scheduleArm]
        case .pressDown where !pressIsDoubleTapOfPushKey:
            phase = .handsFree
            return [.startHandsFree]
        default:
            return []
        }
    }

    private mutating func handleArming(_ event: Event, at time: TimeInterval) -> [Effect] {
        switch event {
        case .armElapsed:
            phase = .pushRecording
            return [.startPush]
        case .pushUp:
            let held = time - (downAt ?? time)
            if held < Self.shortHold {
                var effects: [Effect] = [.cancelArm]
                if pressIsDoubleTapOfPushKey {
                    phase = .awaitingSecondTap(.startHandsFree)
                    lastUpAt = time
                    effects.append(.scheduleTapWindow)
                } else {
                    phase = .idle
                    downAt = nil
                }
                return effects
            }
            phase = .processing
            downAt = nil
            return [.cancelArm, .startPush, .finish]
        default:
            return []
        }
    }

    private mutating func handlePushRecording(_ event: Event, at time: TimeInterval) -> [Effect] {
        switch event {
        case .pushUp:
            let held = time - (downAt ?? time)
            downAt = nil
            if held < Self.shortHold {
                phase = .idle
                return [.cancelSession]
            }
            phase = .processing
            return [.finish]
        default:
            return []
        }
    }

    private mutating func handleAwaiting(
        _ purpose: Purpose,
        _ event: Event,
        at time: TimeInterval
    ) -> [Effect] {
        switch event {
        case .pushDown:
            guard pressIsDoubleTapOfPushKey else { return [] }
            if let lastUpAt, time - lastUpAt <= Self.doubleTapWindow {
                switch purpose {
                case .startHandsFree:
                    phase = .handsFree
                    return [.cancelTapWindow, .startHandsFree]
                case .stopHandsFree:
                    phase = .processing
                    return [.cancelTapWindow, .finish]
                }
            }
            phase = .arming
            downAt = time
            return [.cancelTapWindow, .scheduleArm]
        case .tapWindowElapsed:
            switch purpose {
            case .startHandsFree:
                phase = .idle
                lastUpAt = nil
            case .stopHandsFree:
                phase = .handsFree
            }
            return []
        default:
            return []
        }
    }

    private mutating func handleHandsFree(_ event: Event, at time: TimeInterval) -> [Effect] {
        switch event {
        case .pushDown where pressIsDoubleTapOfPushKey:
            phase = .handsFreeKeyDown
            downAt = time
            return [.scheduleArm]
        case .pressDown where !pressIsDoubleTapOfPushKey:
            phase = .processing
            return [.finish]
        default:
            return []
        }
    }

    private mutating func handleHandsFreeKeyDown(_ event: Event, at time: TimeInterval) -> [Effect] {
        switch event {
        case .pushUp:
            let held = time - (downAt ?? time)
            downAt = nil
            if held < Self.shortHold {
                phase = .processing
                return [.cancelArm, .finish]
            }
            phase = .handsFree
            return [.cancelArm]
        case .armElapsed:
            return []
        default:
            return []
        }
    }

    private mutating func handleHandsFreeHolding(_ event: Event) -> [Effect] {
        switch event {
        case .pushUp:
            phase = .handsFree
            downAt = nil
            return []
        default:
            return []
        }
    }

    private mutating func clearToIdle() -> [Effect] {
        phase = .idle
        downAt = nil
        lastUpAt = nil
        return [.cancelArm, .cancelTapWindow]
    }
}
