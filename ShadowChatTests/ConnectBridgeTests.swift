import XCTest
@testable import ShadowChat

final class ConnectBridgeTests: XCTestCase {
    private var database: Database!
    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("shadowchat-bridge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        database = try Database(path: directory.appendingPathComponent("test.sqlite").path)
    }

    override func tearDownWithError() throws {
        database = nil
        try? FileManager.default.removeItem(at: directory)
    }

    func testPromptContainsLiveBridgeAndPrograms() throws {
        let endpoint = BridgeEndpoint(host: "127.0.0.1", port: 59731, token: "bridge-token-9f3a")
        let text = ConnectPrompt.render(endpoint: endpoint, occupantNames: ["Me", "ClaudeCode", "Codex", "Grok", "CursorGrok"])
        XCTAssertTrue(text.contains("59731"))
        XCTAssertTrue(text.contains("bridge-token-9f3a"))
        XCTAssertTrue(text.contains("127.0.0.1"))
        XCTAssertTrue(text.contains("curl"))
        XCTAssertTrue(text.contains("/join"))
        XCTAssertTrue(text.contains("/transcript"))
        XCTAssertTrue(text.contains("/message"))
        for name in ["Codex", "Claude", "Antigravity", "Cursor", "Grok", "Grok Bot", "Muse"] {
            XCTAssertTrue(text.contains(name), name)
        }
        XCTAssertTrue(text.contains("Do not run unrestricted shell"))
        XCTAssertTrue(text.contains("pressed Start"))
        try BridgeFiles.write(endpoint: endpoint, prompt: text, directory: directory)
        let disk = try String(contentsOf: directory.appendingPathComponent("connect-prompt.txt"), encoding: .utf8)
        XCTAssertEqual(disk, text)
        let decoded = try JSONDecoder().decode(BridgeEndpoint.self, from: Data(contentsOf: directory.appendingPathComponent("bridge.json")))
        XCTAssertEqual(decoded, endpoint)
    }

    func testWrongTokenIsRejectedAndValidPostIsStored() throws {
        let lobby = try database.ensureLobby()
        let token = "good-token"
        let deniedBody = Data("{\"token\":\"wrong-token\",\"screenName\":\"Codex\",\"text\":\"nope\",\"room\":\"Lobby\"}".utf8)
        var calls = 0
        let denied = BridgeRouter.handle(
            request: BridgeHTTPRequest(method: "POST", path: "/message", query: [:], body: deniedBody),
            expectedToken: token
        ) { _ in
            calls += 1
            return BridgeHTTPResponse(status: 200, contentType: "text/plain; charset=utf-8", body: "should not run")
        }
        XCTAssertEqual(denied.status, 401)
        XCTAssertTrue(denied.body.contains("token refused"))
        XCTAssertEqual(calls, 0)
        XCTAssertFalse(BridgeInbox.authorize("wrong-token", expected: token))
        XCTAssertTrue(try database.messages(roomID: lobby.id).isEmpty)

        let allowedBody = Data("{\"token\":\"good-token\",\"screenName\":\"Codex\",\"text\":\"hello from Codex\",\"room\":\"Lobby\"}".utf8)
        let allowed = BridgeRouter.handle(
            request: BridgeHTTPRequest(method: "POST", path: "/message", query: [:], body: allowedBody),
            expectedToken: token
        ) { action in
            guard case .post(let screenName, let text, let room) = action else {
                return BridgeHTTPResponse(status: 500, contentType: "text/plain; charset=utf-8", body: "wrong action")
            }
            do {
                _ = try BridgeInbox.insert(database: self.database, rooms: [lobby], screenName: screenName, text: text, roomName: room)
                return BridgeHTTPResponse(status: 200, contentType: "application/json; charset=utf-8", body: "{\"ok\":true}")
            } catch {
                return BridgeHTTPResponse(status: 400, contentType: "text/plain; charset=utf-8", body: "rejected")
            }
        }
        XCTAssertEqual(allowed.status, 200)
        let stored = try database.messages(roomID: lobby.id)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored[0].senderName, "Codex")
        XCTAssertEqual(stored[0].body, "hello from Codex")
        XCTAssertEqual(stored[0].roomID, lobby.id)
    }

    func testGuestMentionsWaitUntilTheRoomIsStarted() {
        let roster = ParticipantID.agentOrder.map { Buddy(id: $0, enabled: true, online: true, reason: "") }
        XCTAssertEqual(BridgeTurnPolicy.plan(text: "@Codex hello", phase: .stopped, turnLimit: 4, roster: roster), [])
        XCTAssertEqual(BridgeTurnPolicy.plan(text: "hello from Codex", phase: .running, turnLimit: 4, roster: roster), [])
        XCTAssertEqual(BridgeTurnPolicy.plan(text: "@Codex hello", phase: .running, turnLimit: 4, roster: roster), [.codex])
    }
}
