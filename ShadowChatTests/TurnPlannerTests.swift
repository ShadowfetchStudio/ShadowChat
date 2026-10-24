import XCTest
@testable import ShadowChat

final class TurnPlannerTests: XCTestCase {
    private func roster(
        offline: Set<ParticipantID> = [],
        disabled: Set<ParticipantID> = []
    ) -> [Buddy] {
        ParticipantID.agentOrder.map { id in
            Buddy(id: id, enabled: !disabled.contains(id), online: !offline.contains(id), reason: "")
        }
    }

    private func plan(
        sender: ParticipantID = .me,
        text: String,
        phase: RunPhase = .running,
        roundtable: Bool = false,
        turnLimit: Int = 4,
        offline: Set<ParticipantID> = [],
        disabled: Set<ParticipantID> = []
    ) -> [ParticipantID] {
        TurnPlanner.plan(
            TurnPlan(
                sender: sender,
                text: text,
                phase: phase,
                roundtable: roundtable,
                turnLimit: turnLimit,
                roster: roster(offline: offline, disabled: disabled)
            )
        )
    }

    func testRosterOrderIsClaudeCodexGrokCursorGrok() {
        XCTAssertEqual(ParticipantID.agentOrder, [.claudeCode, .codex, .grok, .cursorGrok])
    }

    func testPlanOnlyOnHumanMessagesWhileRunning() {
        XCTAssertEqual(plan(text: "@all", phase: .stopped), [])
        XCTAssertEqual(plan(text: "@all", phase: .paused), [])
        XCTAssertEqual(plan(text: "hello", phase: .stopped, roundtable: true), [])
        XCTAssertEqual(
            plan(text: "@all", phase: .running),
            [.claudeCode, .codex, .grok, .cursorGrok]
        )
    }

    func testAgentMessagesNeverReplan() {
        for sender in ParticipantID.agentOrder {
            XCTAssertEqual(
                plan(sender: sender, text: "@all @Codex", phase: .running, roundtable: true),
                [],
                sender.rawValue
            )
        }
    }

    func testMentionsKeepOrderDedupeAndCap() {
        XCTAssertEqual(
            plan(text: "@Grok @Claude @Codex", turnLimit: 4),
            [.grok, .claudeCode, .codex]
        )
        XCTAssertEqual(
            plan(text: "@Claude @Grok @Claude @Codex", turnLimit: 2),
            [.claudeCode, .grok]
        )
        XCTAssertEqual(plan(text: "@CODEX @cursor", turnLimit: 4), [.codex, .cursorGrok])
    }

    func testAllAndRoomUseFullRosterCapped() {
        XCTAssertEqual(plan(text: "hey @all", turnLimit: 4), ParticipantID.agentOrder)
        XCTAssertEqual(plan(text: "@room please", turnLimit: 4), ParticipantID.agentOrder)
        XCTAssertEqual(plan(text: "@all", turnLimit: 2), [.claudeCode, .codex])
        XCTAssertEqual(plan(text: "@Grok @all", turnLimit: 3), [.claudeCode, .codex, .grok])
        XCTAssertEqual(plan(text: "@room", turnLimit: 99), ParticipantID.agentOrder)
    }

    func testNoMentionsFollowRoundtable() {
        XCTAssertEqual(plan(text: "hello room", roundtable: false), [])
        XCTAssertEqual(plan(text: "hello room", roundtable: true, turnLimit: 4), ParticipantID.agentOrder)
        XCTAssertEqual(plan(text: "hello room", roundtable: true, turnLimit: 1), [.claudeCode])
    }

    func testOfflineAndDisabledAreSkipped() {
        XCTAssertEqual(
            plan(text: "@all", offline: [.claudeCode]),
            [.codex, .grok, .cursorGrok]
        )
        XCTAssertEqual(
            plan(text: "@Claude @Codex", disabled: [.claudeCode]),
            [.codex]
        )
        XCTAssertEqual(
            plan(text: "hi", roundtable: true, turnLimit: 4, offline: [.codex, .grok]),
            [.claudeCode, .cursorGrok]
        )
        XCTAssertEqual(plan(text: "@nobody @Codex"), [.codex])
        XCTAssertEqual(plan(text: "@Me @Claude"), [.claudeCode])
    }

    func testPunctuationDoesNotStickToScreenNames() {
        XCTAssertEqual(plan(text: "hey @ClaudeCode, and (@Grok)!"), [.claudeCode, .grok])
        XCTAssertEqual(plan(text: "mail a@Codex.com stays put"), [])
        XCTAssertEqual(plan(text: "@CursorGrok please"), [.cursorGrok])
        XCTAssertEqual(plan(text: "café@Codex stays put"), [])
        XCTAssertEqual(plan(text: "名字@all stays put"), [])
        XCTAssertEqual(plan(text: "@all", turnLimit: 1), [.claudeCode])
        XCTAssertEqual(plan(text: "@room", turnLimit: 12), ParticipantID.agentOrder)
    }

    func testStartReplaysOnlyAnUnansweredHumanMessage() {
        let human = ChatMessage(id: "h", roomID: "r", sender: .me, senderName: "Me", body: "@Codex hi", rtf: nil, status: .complete, createdAt: Date())
        let cancelled = ChatMessage(id: "c", roomID: "r", sender: .codex, senderName: "Codex", body: "partial", rtf: nil, status: .cancelled, createdAt: Date())
        XCTAssertEqual(TurnPlanner.unansweredHumanText(in: [human, cancelled]), "@Codex hi")
        let done = ChatMessage(id: "d", roomID: "r", sender: .codex, senderName: "Codex", body: "ok", rtf: nil, status: .complete, createdAt: Date())
        XCTAssertNil(TurnPlanner.unansweredHumanText(in: [human, done]))
    }

    func testTurnLimitClamps() {
        XCTAssertEqual(plan(text: "@all", turnLimit: 0).count, 1)
        XCTAssertEqual(plan(text: "@all", turnLimit: 1), [.claudeCode])
        XCTAssertEqual(plan(text: "@all", turnLimit: 12), ParticipantID.agentOrder)
        XCTAssertEqual(plan(text: ""), [])
        let huge = String(repeating: "hello @Codex ", count: 200) + "@all"
        XCTAssertEqual(plan(text: huge, turnLimit: 12), ParticipantID.agentOrder)
    }

    func testMultiProgramRoleMentions() {
        XCTAssertEqual(plan(text: "@coders review this", turnLimit: 4), [.claudeCode, .codex, .cursorGrok])
        XCTAssertEqual(plan(text: "@thinkers brainstorm", turnLimit: 4), [.grok])
        XCTAssertEqual(plan(text: "@local check status", turnLimit: 4), ParticipantID.agentOrder)
        XCTAssertEqual(plan(text: "@bridge only outside apps", roundtable: true, turnLimit: 4), [])
        XCTAssertEqual(plan(text: "@bridge @Codex", roundtable: false, turnLimit: 4), [.codex])
    }
}
