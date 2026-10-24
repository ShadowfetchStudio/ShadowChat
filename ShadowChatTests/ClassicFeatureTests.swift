import AppKit
import XCTest
@testable import ShadowChat

final class ClassicFeatureTests: XCTestCase {
    func testSmileysSwapWholeTokensOnly() {
        XCTAssertEqual(Smileys.replacing("hi :)"), "hi 🙂")
        XCTAssertEqual(Smileys.replacing(":D great;) ok"), "😀 great;) ok")
        XCTAssertEqual(Smileys.replacing("wow :-P."), "wow 😛.")
        XCTAssertEqual(Smileys.replacing("O:-) <3 8-)"), "😇 ❤️ 😎")
        XCTAssertEqual(Smileys.replacing("see http://example.com"), "see http://example.com")
        XCTAssertEqual(Smileys.replacing("a:b :options C:D"), "a:b :options C:D")
        XCTAssertEqual(Smileys.replacing("let x = f(:)"), "let x = f(:)")
    }

    func testSmileyMenuTokensAllRender() {
        for token in Smileys.menuTokens {
            XCTAssertNotNil(Smileys.face(for: token), token)
            XCTAssertNotEqual(Smileys.replacing(token), token, token)
        }
    }

    func testAwayMessageCodesExpand() {
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 10
        parts.day = 24
        parts.hour = 13
        parts.minute = 5
        let date = Calendar.current.date(from: parts)!
        let text = AwayPreset.expand("%n left at %t on %d", screenName: "Shadow", now: date)
        XCTAssertEqual(text, "Shadow left at 1:05 PM on 10/24/2026")
        XCTAssertEqual(AwayPreset.defaults.count, 4)
    }

    func testGuestActivityThresholds() {
        let now = Date()
        XCTAssertEqual(GuestActivity.state(lastSeen: now.addingTimeInterval(-30), now: now), .active)
        XCTAssertEqual(GuestActivity.state(lastSeen: now.addingTimeInterval(-7 * 60), now: now), .idle(minutes: 7))
        XCTAssertEqual(GuestActivity.state(lastSeen: now.addingTimeInterval(-31 * 60), now: now), .gone)
        XCTAssertEqual(GuestActivity.label(minutes: 7), "Idle 7m")
        XCTAssertEqual(GuestActivity.label(minutes: 65), "Idle 1:05")
    }

    func testBuddyTransitionFades() {
        let start = Date()
        let transition = BuddyTransition(kind: .arrived, at: start)
        XCTAssertTrue(transition.isVisible(now: start.addingTimeInterval(3)))
        XCTAssertFalse(transition.isVisible(now: start.addingTimeInterval(BuddyTransition.visibleFor + 1)))
    }

    func testSynthesizedSoundsAreValidWAV() {
        for sound in ClassicSound.allCases {
            let data = ClassicSoundSynth.wav(for: sound)
            XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "RIFF", sound.rawValue)
            XCTAssertEqual(String(data: data.subdata(in: 8..<12), encoding: .ascii), "WAVE", sound.rawValue)
            XCTAssertGreaterThan(data.count, 44 + 1_000, sound.rawValue)
            XCTAssertLessThan(data.count, 44 + ClassicSoundSynth.sampleRate * 2, "cues stay under a second")
            XCTAssertNotNil(NSSound(data: data), sound.rawValue)
        }
    }

    func testTranscriptTimestampsAndSmileys() {
        let message = ChatMessage(
            id: "1",
            roomID: "r",
            sender: .claudeCode,
            senderName: "ClaudeCode",
            body: "done :)",
            rtf: nil,
            status: .complete,
            createdAt: Date()
        )
        let plain = TranscriptRenderer.render([message]).string
        XCTAssertEqual(plain, "ClaudeCode: done :)\n")
        let classic = TranscriptRenderer.render([message], timestamps: true, smileys: true).string
        XCTAssertTrue(classic.hasPrefix("ClaudeCode ("))
        XCTAssertTrue(classic.hasSuffix("): done 🙂\n"))
    }

    func testEmptyStreamingReplyIsHiddenUntilItStarts() {
        let typing = ChatMessage(
            id: "2",
            roomID: "r",
            sender: .codex,
            senderName: "Codex",
            body: "",
            rtf: nil,
            status: .streaming,
            createdAt: Date()
        )
        XCTAssertEqual(TranscriptRenderer.render([typing]).string, "")
    }
}
