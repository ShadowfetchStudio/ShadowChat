import XCTest
@testable import ShadowChat

final class SlashCommandTests: XCTestCase {
    func testParsesKnownCommandsAndAliases() {
        XCTAssertEqual(SlashCommand.parse("/help"), .help)
        XCTAssertEqual(SlashCommand.parse("  /HELP  "), .help)
        XCTAssertEqual(SlashCommand.parse("/?"), .help)
        XCTAssertEqual(SlashCommand.parse("/who"), .who)
        XCTAssertEqual(SlashCommand.parse("/apps"), .apps)
        XCTAssertEqual(SlashCommand.parse("/programs"), .apps)
        XCTAssertEqual(SlashCommand.parse("/go"), .start)
        XCTAssertEqual(SlashCommand.parse("/stop now"), .stop)
        XCTAssertEqual(SlashCommand.parse("/round"), .roundtable)
        XCTAssertEqual(SlashCommand.parse("/save"), .export)
        XCTAssertEqual(SlashCommand.parse("/compare SQLite vs CoreData"), .compare("SQLite vs CoreData"))
        XCTAssertEqual(SlashCommand.parse("/review concurrency safety"), .review("concurrency safety"))
        XCTAssertEqual(SlashCommand.parse("/handoff Antigravity finish parser"), .handoff("Antigravity finish parser"))
    }

    func testPathsAndOrdinaryTextAreNotCommands() {
        XCTAssertNil(SlashCommand.parse("hello"))
        XCTAssertNil(SlashCommand.parse("/"))
        XCTAssertNil(SlashCommand.parse("/usr/bin/env"))
        XCTAssertNil(SlashCommand.parse("/usr is a folder"))
        XCTAssertNil(SlashCommand.parse("see /help"))
    }

    func testUnknownSingleWordIsFlagged() {
        XCTAssertEqual(SlashCommand.parse("/frobnicate"), .unknown("frobnicate"))
    }

    func testTranscriptExportMarkdown() {
        let messages = [
            ChatMessage(id: "1", roomID: "r", sender: .me, senderName: "Me", body: "hi", rtf: nil, status: .complete, createdAt: Date()),
            ChatMessage(id: "2", roomID: "r", sender: .codex, senderName: "Codex", body: "part", rtf: nil, status: .cancelled, createdAt: Date()),
            ChatMessage(id: "3", roomID: "r", sender: .grok, senderName: "Grok", body: "typing", rtf: nil, status: .streaming, createdAt: Date())
        ]
        let text = TranscriptExport.markdown(roomName: "Lobby", messages: messages, exportedAt: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(text.hasPrefix("# Lobby — ShadowChat transcript"))
        XCTAssertTrue(text.contains("**Me:** hi"))
        XCTAssertTrue(text.contains("**Codex:** part _(cancelled)_"))
        XCTAssertFalse(text.contains("typing"))
        XCTAssertEqual(TranscriptExport.suggestedFileName(roomName: "My Project/x"), "My-Project-x-transcript.md")
    }
}
