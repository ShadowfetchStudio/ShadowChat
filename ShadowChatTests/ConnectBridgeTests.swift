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

    func testPathLikeRoomNamesAreRejected() throws {
        let lobby = try database.ensureLobby()
        for name in ["..", "../Lobby", "Lobby/secret", "room\\x"] {
            var evil = Room.lobby(id: UUID().uuidString)
            evil.name = name
            try database.insertRoom(evil)
            XCTAssertThrowsError(
                try BridgeInbox.insert(database: database, rooms: [lobby, evil], screenName: "Codex", text: "hi", roomName: name)
            )
        }
        let stored = try database.messages(roomID: lobby.id)
        XCTAssertTrue(stored.isEmpty)
    }

    func testGuestMentionsWaitUntilTheRoomIsStarted() {
        let roster = ParticipantID.agentOrder.map { Buddy(id: $0, enabled: true, online: true, reason: "") }
        XCTAssertEqual(BridgeTurnPolicy.plan(text: "@Codex hello", phase: .stopped, turnLimit: 4, roster: roster), [])
        XCTAssertEqual(BridgeTurnPolicy.plan(text: "hello from Codex", phase: .running, turnLimit: 4, roster: roster), [])
        XCTAssertEqual(BridgeTurnPolicy.plan(text: "@Codex hello", phase: .running, turnLimit: 4, roster: roster), [.codex])
    }

    func testOversizedBodyIsNotParsed() {
        let header = Data("POST /message HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 40000\r\n\r\n".utf8)
        XCTAssertNil(BridgeHTTPParser.parse(header + Data(repeating: 0x61, count: 64)))
    }

    func testConcurrentPostsOnLoopback() async throws {
        let lobby = try database.ensureLobby()
        let token = "stress-token"
        let server = LocalBridgeServer { request in
            BridgeRouter.handle(request: request, expectedToken: token) { action in
                switch action {
                case .post(let screenName, let text, let room):
                    do {
                        _ = try BridgeInbox.insert(database: self.database, rooms: [lobby], screenName: screenName, text: text, roomName: room)
                        return BridgeHTTPResponse(status: 200, contentType: "application/json; charset=utf-8", body: "{\"ok\":true}")
                    } catch {
                        return BridgeHTTPResponse(status: 400, contentType: "application/json; charset=utf-8", body: "{\"ok\":false}")
                    }
                case .join:
                    return BridgeHTTPResponse(status: 200, contentType: "application/json; charset=utf-8", body: "{\"ok\":true}")
                default:
                    return BridgeHTTPResponse(status: 404, contentType: "text/plain; charset=utf-8", body: "no")
                }
            }
        }
        try server.start()
        defer { server.stop() }
        let port = server.port
        XCTAssertGreaterThan(port, 0)
        let session = URLSession(configuration: .ephemeral)
        let codes: [Int] = try await withThrowingTaskGroup(of: Int.self) { group in
            for index in 0..<40 {
                group.addTask {
                    var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/message")!)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 8
                    let body = index == 0
                        ? "{\"token\":\"nope\",\"screenName\":\"Codex\",\"text\":\"x\",\"room\":\"Lobby\"}"
                        : "{\"token\":\"\(token)\",\"screenName\":\"Muse\",\"text\":\"hi \(index)\",\"room\":\"Lobby\"}"
                    request.httpBody = Data(body.utf8)
                    let (_, response) = try await session.data(for: request)
                    return (response as? HTTPURLResponse)?.statusCode ?? 0
                }
            }
            var collected: [Int] = []
            for try await code in group { collected.append(code) }
            return collected
        }
        XCTAssertEqual(codes.filter { $0 == 401 }.count, 1)
        XCTAssertEqual(codes.filter { $0 == 200 }.count, 39)
        var big = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/message")!)
        big.httpMethod = "POST"
        big.httpBody = Data(repeating: 0x61, count: 40_000)
        big.timeoutInterval = 8
        let (_, bigResponse) = try await session.data(for: big)
        XCTAssertEqual((bigResponse as? HTTPURLResponse)?.statusCode, 400)
        let stored = try database.messages(roomID: lobby.id)
        XCTAssertEqual(stored.count, 39)
        XCTAssertTrue(stored.allSatisfy { $0.senderName == "Muse" })
    }
}
