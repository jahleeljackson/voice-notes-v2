import XCTest
@testable import VoiceNotes

final class VoiceNotesLogicTests: XCTestCase {
    func testHoldPastHalfSecondFinishes() throws { try VoiceNotesLogicChecks.holdPastHalfSecondFinishes() }
    func testShortHoldDoesNotPaste() throws { try VoiceNotesLogicChecks.shortHoldDoesNotPaste() }
    func testDoubleTapStartsAndStopsHandsFree() throws { try VoiceNotesLogicChecks.doubleTapStartsAndStopsHandsFree() }
    func testSingleTapDoesNotStart() throws { try VoiceNotesLogicChecks.singleTapDoesNotStart() }
    func testExpiredDoubleTapDoesNothing() throws { try VoiceNotesLogicChecks.expiredDoubleTapDoesNothing() }
    func testEscapeWhileIdleDoesNothing() throws { try VoiceNotesLogicChecks.escapeWhileIdleDoesNothing() }
    func testEscapeWhileRecordingCancels() throws { try VoiceNotesLogicChecks.escapeWhileRecordingCancels() }
    func testEscapeWhileProcessingCancels() throws { try VoiceNotesLogicChecks.escapeWhileProcessingCancels() }
    func testDeleteWhileRecordingKeepsTheSession() throws { try VoiceNotesLogicChecks.deleteWhileRecordingKeepsTheSession() }
    func testSeparatePressKeyToggles() throws { try VoiceNotesLogicChecks.separatePressKeyToggles() }
    func testHoldDuringHandsFreeDoesNotStop() throws { try VoiceNotesLogicChecks.holdDuringHandsFreeDoesNotStop() }
    func testLateReleaseStillFinishes() throws { try VoiceNotesLogicChecks.lateReleaseStillFinishes() }
    func testSessionEndReturnsToIdle() throws { try VoiceNotesLogicChecks.sessionEndReturnsToIdle() }
    func testFunctionKeyDownStartsPush() throws { try VoiceNotesLogicChecks.functionKeyDownStartsPush() }
    func testEscapePassesThroughUntilRecording() throws { try VoiceNotesLogicChecks.escapePassesThroughUntilRecording() }
    func testEscapeWhileRecordingIsSwallowed() throws { try VoiceNotesLogicChecks.escapeWhileRecordingIsSwallowed() }
    func testDeleteChordIsSwallowed() throws { try VoiceNotesLogicChecks.deleteChordIsSwallowed() }
    func testUnrelatedKeyIsIgnored() throws { try VoiceNotesLogicChecks.unrelatedKeyIsIgnored() }
    func testPromptRequiresCleanupRules() throws { try VoiceNotesLogicChecks.promptRequiresCleanupRules() }
    func testRequestIncludesMinimalReasoning() throws { try VoiceNotesLogicChecks.requestIncludesMinimalReasoning() }
    func testRetryDropsRejectedReasoningField() throws { try VoiceNotesLogicChecks.retryDropsRejectedReasoningField() }
    func testSanitizeStripsFencesAndQuotes() throws { try VoiceNotesLogicChecks.sanitizeStripsFencesAndQuotes() }
}
