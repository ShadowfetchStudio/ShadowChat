import XCTest
@testable import ShadowChat

final class TurnEngineTests: XCTestCase {
    func testPauseHoldsQueueUntilCurrentFinishes() {
        var engine = TurnEngine()
        engine.start()
        engine.enqueue([.claudeCode, .codex, .grok])
        XCTAssertEqual(engine.dequeueIfIdle(), .claudeCode)
        engine.pause()
        XCTAssertNil(engine.dequeueIfIdle())
        XCTAssertEqual(engine.queue, [.codex, .grok])
        engine.finishCurrent()
        XCTAssertNil(engine.dequeueIfIdle())
        engine.start()
        XCTAssertEqual(engine.dequeueIfIdle(), .codex)
    }

    func testEnqueueIgnoredUnlessRunning() {
        var engine = TurnEngine()
        engine.enqueue([.claudeCode])
        XCTAssertTrue(engine.queue.isEmpty)
        engine.start()
        engine.pause()
        engine.enqueue([.codex])
        XCTAssertTrue(engine.queue.isEmpty)
    }

    func testStopDropsQueueAndMarksActiveCancelled() {
        var engine = TurnEngine()
        engine.start()
        engine.enqueue([.claudeCode, .codex])
        _ = engine.dequeueIfIdle()
        engine.stop()
        XCTAssertTrue(engine.queue.isEmpty)
        XCTAssertTrue(engine.cancelCurrent)
        XCTAssertEqual(engine.phase, .stopped)
        XCTAssertEqual(StopPolicy.status(wasKilled: true, exitCode: 15, producedText: true), .cancelled)
        engine.finishCurrent()
        XCTAssertFalse(engine.cancelCurrent)
        XCTAssertNil(engine.dequeueIfIdle())
    }

    func testSecondStartDoesNotQueueASecondRound() {
        var engine = TurnEngine()
        let roster = ParticipantID.agentOrder
        engine.armIfIdle(roster)
        engine.armIfIdle(roster)
        XCTAssertEqual(engine.queue, roster)
        XCTAssertEqual(engine.phase, .running)
        XCTAssertEqual(engine.dequeueIfIdle(), .claudeCode)
        engine.armIfIdle([.grok])
        XCTAssertEqual(engine.queue, [.codex, .grok, .cursorGrok])
        XCTAssertEqual(engine.active, .claudeCode)
    }

    func testStopWithNoActiveDoesNotPretendATurnWasCancelled() {
        var engine = TurnEngine()
        engine.start()
        engine.enqueue([.grok])
        engine.stop()
        XCTAssertTrue(engine.queue.isEmpty)
        XCTAssertFalse(engine.cancelCurrent)
        XCTAssertEqual(StopPolicy.status(wasKilled: false, exitCode: 0, producedText: true), .complete)
    }
}
