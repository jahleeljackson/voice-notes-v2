import Foundation

enum VoiceNotesLogicChecks {
    static func runAll() throws {
        let tests: [(String, () throws -> Void)] = [
            ("holdPastHalfSecondFinishes", holdPastHalfSecondFinishes),
            ("shortHoldDoesNotPaste", shortHoldDoesNotPaste),
            ("doubleTapStartsAndStopsHandsFree", doubleTapStartsAndStopsHandsFree),
            ("singleTapDoesNotStart", singleTapDoesNotStart),
            ("expiredDoubleTapDoesNothing", expiredDoubleTapDoesNothing),
            ("escapeWhileIdleDoesNothing", escapeWhileIdleDoesNothing),
            ("escapeWhileRecordingCancels", escapeWhileRecordingCancels),
            ("escapeWhileProcessingCancels", escapeWhileProcessingCancels),
            ("deleteWhileRecordingKeepsTheSession", deleteWhileRecordingKeepsTheSession),
            ("separatePressKeyToggles", separatePressKeyToggles),
            ("holdDuringHandsFreeDoesNotStop", holdDuringHandsFreeDoesNotStop),
            ("lateReleaseStillFinishes", lateReleaseStillFinishes),
            ("sessionEndReturnsToIdle", sessionEndReturnsToIdle),
            ("functionKeyDownStartsPush", functionKeyDownStartsPush),
            ("escapePassesThroughUntilRecording", escapePassesThroughUntilRecording),
            ("escapeWhileRecordingIsSwallowed", escapeWhileRecordingIsSwallowed),
            ("deleteChordIsSwallowed", deleteChordIsSwallowed),
            ("unrelatedKeyIsIgnored", unrelatedKeyIsIgnored),
            ("promptRequiresCleanupRules", promptRequiresCleanupRules),
            ("requestIncludesMinimalReasoning", requestIncludesMinimalReasoning),
            ("retryDropsRejectedReasoningField", retryDropsRejectedReasoningField),
            ("sanitizeStripsFencesAndQuotes", sanitizeStripsFencesAndQuotes)
        ]
        for (name, test) in tests {
            do {
                try test()
            } catch {
                throw LogicCheckError("\(name): \(error)")
            }
        }
    }

    static func holdPastHalfSecondFinishes() throws {
        let (machine, effects) = try run([
            (.pushDown, 0),
            (.armElapsed, 0.18),
            (.pushUp, 0.80)
        ])
        try expectEqual(effects[0], [.scheduleArm], "down")
        try expectEqual(effects[1], [.startPush], "arm")
        try expectEqual(effects[2], [.finish], "up")
        try expectEqual(machine.phase, .processing, "phase")
    }

    static func shortHoldDoesNotPaste() throws {
        let (machine, effects) = try run([
            (.pushDown, 0),
            (.armElapsed, 0.18),
            (.pushUp, 0.40)
        ])
        try expectEqual(effects[2], [.cancelSession], "cancel")
        try expectEqual(machine.phase, .idle, "phase")
        try expectFalse(effects.joined().contains(.finish), "must not finish")
    }

    static func doubleTapStartsAndStopsHandsFree() throws {
        let (machine, effects) = try run([
            (.pushDown, 0),
            (.pushUp, 0.10),
            (.pushDown, 0.30),
            (.pushUp, 0.38),
            (.pushDown, 1.00),
            (.pushUp, 1.08),
            (.pushDown, 1.25)
        ])
        try expectEqual(effects[0], [.scheduleArm], "first down")
        try expectEqual(effects[1], [.cancelArm, .scheduleTapWindow], "first up")
        try expectEqual(effects[2], [.cancelTapWindow, .startHandsFree], "second down")
        try expectEqual(effects[3], [], "second up")
        try expectEqual(effects[4], [.scheduleArm], "stop down")
        try expectEqual(effects[5], [.cancelArm, .scheduleTapWindow], "stop up")
        try expectEqual(effects[6], [.cancelTapWindow, .finish], "second double tap")
        try expectEqual(machine.phase, .processing, "phase")
    }

    static func singleTapDoesNotStart() throws {
        let (_, effects) = try run([
            (.pushDown, 0),
            (.pushUp, 0.10)
        ])
        try expectFalse(effects.joined().contains(.startPush), "no push start")
        try expectFalse(effects.joined().contains(.startHandsFree), "no hands-free")
        try expectFalse(effects.joined().contains(.finish), "no finish")
    }

    static func expiredDoubleTapDoesNothing() throws {
        let (machine, effects) = try run([
            (.pushDown, 0),
            (.pushUp, 0.10),
            (.tapWindowElapsed, 0.60)
        ])
        try expectFalse(effects.joined().contains(.startHandsFree), "no start")
        try expectEqual(machine.phase, .idle, "phase")
    }

    static func escapeWhileIdleDoesNothing() throws {
        let (machine, effects) = try run([(.cancel, 0)])
        try expectEqual(effects[0], [], "effects")
        try expectEqual(machine.phase, .idle, "phase")
    }

    static func escapeWhileRecordingCancels() throws {
        let (machine, effects) = try run([
            (.pushDown, 0),
            (.armElapsed, 0.18),
            (.cancel, 0.70)
        ])
        try expectTrue(effects[2].contains(.cancelSession), "cancel")
        try expectEqual(machine.phase, .idle, "phase")
    }

    static func escapeWhileProcessingCancels() throws {
        var machine = HotkeyStateMachine()
        _ = machine.handle(.pushDown, at: 0)
        _ = machine.handle(.armElapsed, at: 0.18)
        _ = machine.handle(.pushUp, at: 0.8)
        let effects = machine.handle(.cancel, at: 1.2)
        try expectTrue(effects.contains(.cancelSession), "cancel")
        try expectEqual(machine.phase, .idle, "phase")
    }

    static func deleteWhileRecordingKeepsTheSession() throws {
        let (machine, effects) = try run([
            (.pushDown, 0),
            (.armElapsed, 0.18),
            (.delete, 0.70)
        ])
        try expectEqual(effects[2], [.deleteLast], "delete")
        try expectEqual(machine.phase, .pushRecording, "still recording")
    }

    static func separatePressKeyToggles() throws {
        let (machine, effects) = try run([
            (.pressDown, 0),
            (.pressDown, 1)
        ], pressIsDoubleTap: false)
        try expectEqual(effects[0], [.startHandsFree], "start")
        try expectEqual(effects[1], [.finish], "stop")
        try expectEqual(machine.phase, .processing, "phase")
    }

    static func holdDuringHandsFreeDoesNotStop() throws {
        let (machine, effects) = try run([
            (.pushDown, 0),
            (.pushUp, 0.10),
            (.pushDown, 0.20),
            (.pushUp, 0.28),
            (.pushDown, 2),
            (.armElapsed, 2.2),
            (.pushUp, 3)
        ])
        try expectFalse(effects[4].contains(.finish), "hold down")
        try expectFalse(effects[5].contains(.finish), "arm")
        try expectFalse(effects[6].contains(.finish), "release")
        try expectEqual(machine.phase, .handsFree, "still hands-free")
    }

    static func lateReleaseStillFinishes() throws {
        let (machine, effects) = try run([
            (.pushDown, 0),
            (.pushUp, 0.60)
        ])
        try expectEqual(effects[1], [.cancelArm, .startPush, .finish], "late up")
        try expectEqual(machine.phase, .processing, "phase")
    }

    static func sessionEndReturnsToIdle() throws {
        var machine = HotkeyStateMachine()
        _ = machine.handle(.pushDown, at: 0)
        _ = machine.handle(.armElapsed, at: 0.18)
        _ = machine.handle(.pushUp, at: 0.8)
        machine.noteSessionEnded()
        try expectEqual(machine.phase, .idle, "phase")
    }

    static func functionKeyDownStartsPush() throws {
        var router = HotkeyRouter(shortcuts: .default)
        let down = router.route(PhysicalKeyEvent(
            kind: .flagsChanged, keyCode: 63,
            control: false, option: false, shift: false, command: false,
            function: true, isRepeat: false
        ))
        try expectEqual(down.events, [.pushDown], "down")
        try expectTrue(down.swallow, "swallow down")
        let up = router.route(PhysicalKeyEvent(
            kind: .flagsChanged, keyCode: 63,
            control: false, option: false, shift: false, command: false,
            function: false, isRepeat: false
        ))
        try expectEqual(up.events, [.pushUp], "up")
        try expectTrue(up.swallow, "swallow up")
    }

    static func escapePassesThroughUntilRecording() throws {
        var router = HotkeyRouter(shortcuts: .default)
        router.capturesCancel = false
        let result = router.route(escape())
        try expectEqual(result.events, [.cancel], "event")
        try expectFalse(result.swallow, "do not swallow")
    }

    static func escapeWhileRecordingIsSwallowed() throws {
        var router = HotkeyRouter(shortcuts: .default)
        _ = router.route(PhysicalKeyEvent(
            kind: .flagsChanged, keyCode: 63,
            control: false, option: false, shift: false, command: false,
            function: true, isRepeat: false
        ))
        router.capturesCancel = true
        let result = router.route(escape(function: true))
        try expectEqual(result.events, [.cancel], "cancel only")
        try expectTrue(result.swallow, "swallow")
    }

    static func deleteChordIsSwallowed() throws {
        var router = HotkeyRouter(shortcuts: .default)
        let result = router.route(PhysicalKeyEvent(
            kind: .keyDown, keyCode: 51,
            control: true, option: true, shift: false, command: false,
            function: false, isRepeat: false
        ))
        try expectEqual(result.events, [.delete], "delete")
        try expectTrue(result.swallow, "swallow")
    }

    static func unrelatedKeyIsIgnored() throws {
        var router = HotkeyRouter(shortcuts: .default)
        let result = router.route(PhysicalKeyEvent(
            kind: .keyDown, keyCode: 0,
            control: false, option: false, shift: false, command: false,
            function: false, isRepeat: false
        ))
        try expectEqual(result.events, [], "events")
        try expectFalse(result.swallow, "swallow")
    }

    static func promptRequiresCleanupRules() throws {
        let prompt = CleanupPrompt.system
        try expectTrue(prompt.contains("filler"), "filler")
        try expectTrue(prompt.contains("self-correction"), "self-correction")
        try expectTrue(prompt.contains("bullet"), "bullet")
        try expectTrue(prompt.contains("Do not add"), "do not add")
        try expectEqual(CleanupPrompt.defaultModel, "gpt-5-mini", "model")
    }

    static func requestIncludesMinimalReasoning() throws {
        let json = try jsonBody(includeReasoning: true)
        try expectEqual(json["model"] as? String, "gpt-5-mini", "model")
        try expectEqual(json["reasoning_effort"] as? String, "minimal", "effort")
        let messages = json["messages"] as? [[String: String]] ?? []
        try expectEqual(messages.first?["role"], "system", "role")
        try expectTrue(messages.first?["content"]?.contains("Do not add") == true, "system")
        try expectTrue(messages.last?["content"]?.contains("um hello") == true, "transcript")
    }

    static func retryDropsRejectedReasoningField() throws {
        try expectTrue(
            CleanupPrompt.shouldRetryWithoutReasoning(
                status: 400,
                body: "{\"error\":{\"message\":\"Unrecognized request argument: reasoning_effort\"}}"
            ),
            "retry"
        )
        try expectFalse(
            CleanupPrompt.shouldRetryWithoutReasoning(status: 401, body: "reasoning_effort"),
            "not a 400"
        )
        let json = try jsonBody(includeReasoning: false)
        try expectTrue(json["reasoning_effort"] == nil, "field omitted")
    }

    static func sanitizeStripsFencesAndQuotes() throws {
        try expectEqual(CleanupPrompt.sanitize("```\nHello\n```"), "Hello", "fence")
        try expectEqual(CleanupPrompt.sanitize("\"Hello\""), "Hello", "quotes")
        try expectEqual(CleanupPrompt.sanitize("  Buy milk.  "), "Buy milk.", "trim")
    }

    private static func run(
        _ events: [(HotkeyStateMachine.Event, TimeInterval)],
        pressIsDoubleTap: Bool = true
    ) throws -> (HotkeyStateMachine, [[HotkeyStateMachine.Effect]]) {
        var machine = HotkeyStateMachine()
        machine.pressIsDoubleTapOfPushKey = pressIsDoubleTap
        var all: [[HotkeyStateMachine.Effect]] = []
        for (event, time) in events {
            all.append(machine.handle(event, at: time))
        }
        return (machine, all)
    }

    private static func escape(function: Bool = false) -> PhysicalKeyEvent {
        PhysicalKeyEvent(
            kind: .keyDown, keyCode: 53,
            control: false, option: false, shift: false, command: false,
            function: function, isRepeat: false
        )
    }

    private static func jsonBody(includeReasoning: Bool) throws -> [String: Any] {
        let data = try CleanupPrompt.requestBody(
            model: "gpt-5-mini",
            transcript: "um hello",
            includeReasoningEffort: includeReasoning
        )
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    private static func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ name: String) throws {
        if actual != expected {
            throw LogicCheckError("\(name). expected \(String(describing: expected)), got \(String(describing: actual))")
        }
    }

    private static func expectTrue(_ condition: Bool, _ name: String) throws {
        if !condition { throw LogicCheckError(name) }
    }

    private static func expectFalse(_ condition: Bool, _ name: String) throws {
        if condition { throw LogicCheckError(name) }
    }
}
