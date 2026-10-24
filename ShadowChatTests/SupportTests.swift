import AppKit
import XCTest
@testable import ShadowChat

final class SupportTests: XCTestCase {
    func testPresenceReasons() {
        let missingClaude = PresenceProbe.claude(installed: false, statusText: "")
        XCTAssertFalse(missingClaude.online)
        XCTAssertTrue(missingClaude.reason.contains("~/.local/bin/claude"))
        XCTAssertFalse(missingClaude.reason.contains("/Users/"))

        let signedOut = PresenceProbe.claude(installed: true, statusText: #"{"loggedIn": false}"#)
        XCTAssertFalse(signedOut.online)
        XCTAssertTrue(signedOut.reason.contains("not signed in"))

        let signedIn = PresenceProbe.claude(installed: true, statusText: #"{"loggedIn": true}"#)
        XCTAssertTrue(signedIn.online)

        let codexOut = PresenceProbe.codex(installed: true, statusText: "Not logged in")
        XCTAssertFalse(codexOut.online)
        let codexIn = PresenceProbe.codex(installed: true, statusText: "Logged in using ChatGPT")
        XCTAssertTrue(codexIn.online)

        let grokOut = PresenceProbe.grok(hasKey: false)
        XCTAssertFalse(grokOut.online)
        XCTAssertTrue(grokOut.reason.contains("Keychain"))
        XCTAssertTrue(PresenceProbe.grok(hasKey: true).online)

        let cursorOut = PresenceProbe.cursorGrok(installed: true, statusText: "Not logged in")
        XCTAssertFalse(cursorOut.online)
        XCTAssertTrue(cursorOut.reason.contains("cursor-agent status"))
        XCTAssertTrue(cursorOut.reason.contains("Antigravity"))
        let cursorMissing = PresenceProbe.cursorGrok(installed: false, statusText: "")
        XCTAssertFalse(cursorMissing.online)
        XCTAssertTrue(cursorMissing.reason.contains("Grok Bot"))
        XCTAssertTrue(PresenceProbe.cursorGrok(installed: true, statusText: "Logged in as studio").online)
    }

    func testTranscriptUsesScreenNameNotBubbles() {
        let messages = [
            ChatMessage(id: "1", roomID: "r", sender: .me, senderName: "Me", body: "hi", rtf: nil, status: .complete, createdAt: Date()),
            ChatMessage(id: "2", roomID: "r", sender: .claudeCode, senderName: "Claude", body: "hello", rtf: nil, status: .streaming, createdAt: Date()),
            ChatMessage(id: "3", roomID: "r", sender: .codex, senderName: "Codex", body: "partial", rtf: nil, status: .cancelled, createdAt: Date())
        ]
        let rendered = TranscriptRenderer.render(messages)
        XCTAssertEqual(rendered.string, "Me: hi\nClaude: hello\nCodex: partial (cancelled)\n")
        let claude = (rendered.string as NSString).range(of: "Claude")
        var found: NSColor?
        rendered.enumerateAttribute(.foregroundColor, in: claude) { value, _, _ in
            found = value as? NSColor
        }
        XCTAssertEqual(found, ParticipantID.claudeCode.nsColor)
        XCTAssertFalse(rendered.string.contains("bubble"))
    }

    func testWorktreePathAndGitRepo() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("shadowchat-wt-\(UUID().uuidString)", isDirectory: true)
        let repo = root.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        XCTAssertNotEqual(WorktreeManager.runGit(["init", repo.path]).status, 127)
        XCTAssertEqual(WorktreeManager.runGit(["-C", repo.path, "-c", "user.email=shadowchat@example.com", "-c", "user.name=ShadowChat Tests", "commit", "--allow-empty", "-m", "init"]).status, 0)
        XCTAssertTrue(WorktreeManager.isGitRepo(repo.path))
        let created = try WorktreeManager.ensureWorktree(repo: repo.path, roomID: "Room 1", root: root)
        XCTAssertTrue(created.contains("worktrees/Room1"))
        XCTAssertTrue(WorktreeManager.isGitRepo(created))
        let again = try WorktreeManager.ensureWorktree(repo: repo.path, roomID: "Room 1", root: root)
        XCTAssertEqual(again, created)
        XCTAssertFalse(WorktreeManager.isGitRepo(root.path))
        try? FileManager.default.removeItem(at: root)
    }
}
