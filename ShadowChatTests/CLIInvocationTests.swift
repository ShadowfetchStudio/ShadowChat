import Security
import XCTest
@testable import ShadowChat

final class CLIInvocationTests: XCTestCase {
    private let prompt = "Say hello in one sentence."
    private let cwd = "/tmp/shadowchat-room"
    private let session = "11111111-1111-1111-1111-111111111111"

    func testClaudeReadOnlyPlanMode() {
        let invocation = CLICommands.claude(prompt: prompt, cwd: cwd, writable: false, sessionID: nil, newSessionID: session)
        XCTAssertEqual(invocation.executable, CLIPaths.resolveClaude())
        XCTAssertEqual(invocation.cwd, cwd)
        XCTAssertEqual(invocation.arguments.first, "-p")
        assertContains(invocation, ["--output-format", "stream-json", "--include-partial-messages", "--verbose"])
        assertContains(invocation, ["--permission-mode", "plan", "--permission-prompts", "none", "--restricted"])
        assertContains(invocation, ["--tools", "Read,Grep,Glob"])
        assertContains(invocation, ["--session-id", session])
        XCTAssertFalse(invocation.arguments.contains("--resume"))
        XCTAssertEqual(invocation.arguments.last, prompt)
        XCTAssertNil(CLICommands.containsBannedFlag(invocation.arguments))
    }

    func testClaudeWriteAndResume() {
        let invocation = CLICommands.claude(prompt: prompt, cwd: cwd, writable: true, sessionID: session, newSessionID: "ignored")
        assertContains(invocation, ["--permission-mode", "acceptEdits"])
        XCTAssertFalse(invocation.arguments.contains("--restricted"))
        XCTAssertFalse(invocation.arguments.contains("plan"))
        assertContains(invocation, ["--resume", session])
        XCTAssertNil(CLICommands.containsBannedFlag(invocation.arguments))
    }

    func testCodexReadOnlyAndWrite() {
        let readOnly = CLICommands.codex(prompt: prompt, cwd: cwd, writable: false, sessionID: nil)
        XCTAssertEqual(readOnly.executable, CLIPaths.resolveCodex())
        assertContains(readOnly, ["--sandbox", "read-only", "-C", cwd, "exec", "--json", "--color", "never", "--skip-git-repo-check"])
        XCTAssertFalse(readOnly.arguments.contains("-a"))
        XCTAssertFalse(readOnly.arguments.contains("danger-full-access"))
        XCTAssertEqual(readOnly.arguments.last, prompt)
        XCTAssertNil(CLICommands.containsBannedFlag(readOnly.arguments))

        let writing = CLICommands.codex(prompt: prompt, cwd: cwd, writable: true, sessionID: nil)
        assertContains(writing, ["--sandbox", "workspace-write"])
        XCTAssertFalse(writing.arguments.contains("-a"))
        XCTAssertFalse(writing.arguments.contains("read-only"))
        XCTAssertFalse(writing.arguments.contains("--skip-git-repo-check"))
        XCTAssertNil(CLICommands.containsBannedFlag(writing.arguments))
    }

    func testCodexResume() {
        let invocation = CLICommands.codex(prompt: prompt, cwd: cwd, writable: false, sessionID: session)
        assertContains(invocation, ["exec", "resume", session, "--json", "--skip-git-repo-check"])
        XCTAssertEqual(invocation.arguments.last, prompt)
        XCTAssertNil(CLICommands.containsBannedFlag(invocation.arguments))
    }

    func testCursorGrokPlanAndWrite() {
        let readOnly = CLICommands.cursorGrok(prompt: prompt, cwd: cwd, writable: false, sessionID: nil, newSessionID: session)
        assertContains(readOnly, ["-p", "--output-format", "stream-json", "--stream-partial-output"])
        assertContains(readOnly, ["--sandbox", "enabled", "--trust", "--model", CLIPaths.cursorGrokModel, "--workspace", cwd])
        assertContains(readOnly, ["--mode", "plan"])
        XCTAssertFalse(readOnly.arguments.contains("--new-session-id"))
        XCTAssertFalse(readOnly.arguments.contains("--yolo"))
        XCTAssertFalse(readOnly.arguments.contains("--force"))
        XCTAssertNil(CLICommands.containsBannedFlag(["--trust"]))
        XCTAssertNil(CLICommands.containsBannedFlag(readOnly.arguments))

        let writing = CLICommands.cursorGrok(prompt: prompt, cwd: cwd, writable: true, sessionID: session, newSessionID: "ignored")
        XCTAssertFalse(writing.arguments.contains("plan"))
        assertContains(writing, ["--sandbox", "enabled", "--resume", session])
        XCTAssertNil(CLICommands.containsBannedFlag(writing.arguments))
    }

    func testGrokBodyHasNoSecret() {
        let body = CLICommands.grokBody(prompt: prompt, previousResponseID: "resp_123")
        XCTAssertEqual(body["model"] as? String, "grok-4.7")
        XCTAssertEqual(CLIPaths.defaultGrokModel, "grok-4.7")
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["store"] as? Bool, true)
        XCTAssertEqual(body["input"] as? String, prompt)
        XCTAssertEqual(body["previous_response_id"] as? String, "resp_123")
        XCTAssertNil(body["api_key"])
        XCTAssertNil(body["authorization"])
        let fresh = CLICommands.grokBody(prompt: prompt, previousResponseID: nil)
        XCTAssertNil(fresh["previous_response_id"])
        let hidden = "/Users/me/Library/Application Support/ShadowChat/worktrees/room"
        let readOnlyPrompt = PromptText.make(
            speaker: "Codex",
            roomName: "Lobby",
            history: "Me: hi",
            allowFileChanges: false,
            worktreePath: hidden,
            projectPath: nil
        )
        XCTAssertFalse(readOnlyPrompt.contains(hidden))
        XCTAssertTrue(readOnlyPrompt.contains("Do not impersonate"))
        XCTAssertTrue(readOnlyPrompt.contains("Codex"))
        let writingPrompt = PromptText.make(
            speaker: "ClaudeCode",
            roomName: "Demo",
            history: "Me: edit it",
            allowFileChanges: true,
            worktreePath: hidden,
            projectPath: "/tmp/demo"
        )
        XCTAssertTrue(writingPrompt.contains(hidden))
        XCTAssertFalse(writingPrompt.contains("Bearer"))
        XCTAssertEqual(Redactor.scrub("use Bearer abcdefghijklmnop now"), "use Bearer [redacted] now")
        XCTAssertEqual(Redactor.scrub("hello"), "hello")
        let gate = PermissionGate.directory(
            allowFileChanges: false,
            projectPath: "/tmp/demo",
            worktreePath: hidden,
            worktreeExists: true,
            scratch: "/tmp/scratch"
        )
        XCTAssertFalse(gate.writable)
        XCTAssertEqual(gate.cwd, "/tmp/demo")
        let allowed = PermissionGate.directory(
            allowFileChanges: true,
            projectPath: "/tmp/demo",
            worktreePath: hidden,
            worktreeExists: true,
            scratch: "/tmp/scratch"
        )
        XCTAssertTrue(allowed.writable)
        XCTAssertEqual(allowed.cwd, hidden)
        XCTAssertEqual(KeychainStore.service, "com.shadowfetch.shadowchat")
        XCTAssertEqual(KeychainStore.account, "xai-api-key")
        let query = KeychainStore.loadQuery()
        XCTAssertEqual(query[kSecAttrService as String] as? String, KeychainStore.service)
        XCTAssertEqual(query[kSecAttrAccount as String] as? String, KeychainStore.account)
        XCTAssertNil(query[kSecValueData as String])
        let fake = Data("not-a-real-key".utf8)
        let save = KeychainStore.saveQuery(secret: fake)
        XCTAssertEqual(save[kSecValueData as String] as? Data, fake)
        XCTAssertEqual(save[kSecAttrService as String] as? String, KeychainStore.service)
        XCTAssertEqual(
            WorktreeManager.addArguments(repo: "/tmp/repo", destination: "/tmp/work"),
            ["-C", "/tmp/repo", "worktree", "add", "--detach", "/tmp/work", "HEAD"]
        )
        XCTAssertFalse(WorktreeManager.addArguments(repo: "/tmp/repo", destination: "/tmp/work").contains("--force"))
        XCTAssertEqual(
            WorktreeManager.revParseArguments("/tmp/repo"),
            ["-C", "/tmp/repo", "rev-parse", "--is-inside-work-tree"]
        )
    }

    private func assertContains(_ invocation: CLIInvocation, _ expected: [String], file: StaticString = #filePath, line: UInt = #line) {
        var start = 0
        for token in expected {
            guard let found = invocation.arguments[start...].firstIndex(of: token) else {
                XCTFail("Missing \(token) in \(invocation.arguments)", file: file, line: line)
                return
            }
            start = found + 1
        }
    }
}
