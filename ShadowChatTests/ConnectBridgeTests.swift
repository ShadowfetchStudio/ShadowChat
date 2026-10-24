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
        XCTAssertTrue(text.contains("/wait"))
        XCTAssertTrue(text.contains("/say"))
        for name in ["Codex", "Claude", "Antigravity", "Cursor", "Grok", "Grok Bot", "Muse", "Gemini", "ChatGPT", "Windsurf", "Aider", "Goose", "Cline", "OpenCode"] {
            XCTAssertTrue(text.contains(name), name)
        }
        XCTAssertTrue(text.contains("Do not run unrestricted shell"))
        XCTAssertTrue(text.contains("pressed Start"))
        try BridgeFiles.write(endpoint: endpoint, prompt: text, directory: directory)
        let disk = try String(contentsOf: directory.appendingPathComponent("connect-prompt.txt"), encoding: .utf8)
        XCTAssertEqual(disk, text)
        let decoded = try JSONDecoder().decode(BridgeEndpoint.self, from: Data(contentsOf: directory.appendingPathComponent("bridge.json")))
        XCTAssertEqual(decoded, endpoint)
        let cliURL = directory.appendingPathComponent("shadowchat-cli")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: cliURL.path))
    }

    func testProgramSpecificPresetsAndModes() {
        let endpoint = BridgeEndpoint(host: "127.0.0.1", port: 51234, token: "tok-preset")
        let occupants = ["Me", "ClaudeCode", "Codex", "Grok", "CursorGrok"]

        for preset in [ConnectPreset.grokBot, .muse, .claude, .codex, .antigravity, .cursor, .gemini, .chatGPT] {
            let full = ConnectPrompt.render(endpoint: endpoint, occupantNames: occupants, preset: preset, roomName: "Lobby", mode: .full)
            XCTAssertTrue(full.contains("\"screenName\":\"\(preset.screenName)\""), preset.displayName)
            XCTAssertTrue(full.contains("screenName=\(preset.screenName)"), preset.displayName)
            XCTAssertTrue(full.contains("hello from \(preset.screenName)"), preset.displayName)

            let oneLine = ConnectPrompt.render(endpoint: endpoint, occupantNames: occupants, preset: preset, roomName: "Lobby", mode: .oneLiner)
            XCTAssertTrue(oneLine.contains("\"screenName\":\"\(preset.screenName)\""), preset.displayName)
            XCTAssertTrue(oneLine.contains("/wait?token=tok-preset"), preset.displayName)

            let web = ConnectPrompt.render(endpoint: endpoint, occupantNames: occupants, preset: preset, roomName: "Lobby", mode: .webFetch)
            XCTAssertTrue(web.contains("/join?token=tok-preset&screenName=\(preset.screenName)"), preset.displayName)
            XCTAssertTrue(web.contains("/say?token=tok-preset&screenName=\(preset.screenName)"), preset.displayName)
        }
    }

    func testCanonicalNamesForAllSupportedPrograms() {
        let pairs: [(String, String)] = [
            ("Grok Bot", "GrokBot"),
            ("grok-bot", "GrokBot"),
            ("grok_bot", "GrokBot"),
            ("Muse", "Muse"),
            ("Meta Muse", "Muse"),
            ("Claude", "Claude"),
            ("Claude Code", "Claude"),
            ("Codex", "Codex"),
            ("Antigravity", "Antigravity"),
            ("agy", "Antigravity"),
            ("Cursor", "Cursor"),
            ("CursorGrok", "Cursor"),
            ("Gemini", "Gemini"),
            ("ChatGPT", "ChatGPT"),
            ("Windsurf", "Windsurf"),
            ("Aider", "Aider"),
            ("Goose", "Goose"),
            ("Cline", "Cline"),
            ("OpenCode", "OpenCode"),
            ("Warp", "Warp"),
            ("Zed", "Zed"),
            ("Copilot", "Copilot"),
            ("DeepSeek", "DeepSeek"),
            ("Perplexity", "Perplexity")
        ]
        for (input, expected) in pairs {
            XCTAssertEqual(BridgeNames.canonical(screenName: input, program: ""), expected, input)
        }
    }

    func testPlainBodyAndGetSayAndHeaderAuth() throws {
        let lobby = try database.ensureLobby()
        let token = "tok-plain-123"

        // 1. Plain-text body with apostrophes and quotes via POST /message?token=...&screenName=GrokBot&room=Lobby
        let rawQuoteText = "It's Grok Bot & Muse saying \"hello\"!"
        let plainReq = BridgeHTTPRequest(
            method: "POST",
            path: "/message",
            query: ["token": token, "screenName": "Grok Bot", "room": "Lobby"],
            body: Data(rawQuoteText.utf8)
        )
        let plainResp = BridgeRouter.handle(request: plainReq, expectedToken: token) { action in
            guard case .post(let screenName, let text, let room) = action else {
                return BridgeHTTPResponse(status: 500, contentType: "text/plain; charset=utf-8", body: "wrong action")
            }
            let msg = try! BridgeInbox.insert(database: self.database, rooms: [lobby], screenName: screenName, text: text, roomName: room)
            return BridgeHTTPResponse(status: 200, contentType: "application/json; charset=utf-8", body: "{\"ok\":true,\"screenName\":\"\(msg.senderName)\"}")
        }
        XCTAssertEqual(plainResp.status, 200)

        // 2. URL-only GET /say for tools without POST/shell
        let getSayReq = BridgeHTTPRequest(
            method: "GET",
            path: "/say",
            query: ["token": token, "screenName": "Muse", "room": "Lobby", "text": "hello via GET"],
            body: Data()
        )
        let getSayResp = BridgeRouter.handle(request: getSayReq, expectedToken: token) { action in
            guard case .post(let screenName, let text, let room) = action else {
                return BridgeHTTPResponse(status: 500, contentType: "text/plain; charset=utf-8", body: "wrong action")
            }
            _ = try! BridgeInbox.insert(database: self.database, rooms: [lobby], screenName: screenName, text: text, roomName: room)
            return BridgeHTTPResponse(status: 200, contentType: "application/json; charset=utf-8", body: "{\"ok\":true}")
        }
        XCTAssertEqual(getSayResp.status, 200)

        // 3. OPTIONS CORS preflight
        let optionsReq = BridgeHTTPRequest(method: "OPTIONS", path: "/message", query: [:], body: Data())
        let optionsResp = BridgeRouter.handle(request: optionsReq, expectedToken: token) { _ in
            BridgeHTTPResponse(status: 500, contentType: "text/plain; charset=utf-8", body: "unused")
        }
        XCTAssertEqual(optionsResp.status, 200)
        let wire = String(decoding: optionsResp.serialized, as: UTF8.self)
        XCTAssertTrue(wire.contains("Access-Control-Allow-Origin: *"))

        let stored = try database.messages(roomID: lobby.id)
        XCTAssertEqual(stored.count, 2)
        XCTAssertEqual(stored[0].senderName, "GrokBot")
        XCTAssertEqual(stored[0].body, rawQuoteText)
        XCTAssertEqual(stored[1].senderName, "Muse")
        XCTAssertEqual(stored[1].body, "hello via GET")
    }

    func testShouldReplyPolicyPreventsAgentLoopsAndHonorsMentions() {
        let now = Date()
        let joined = ["GrokBot", "Muse", "Antigravity"]

        // 1. GrokBot joins and says hello -> shouldReply for GrokBot is false, and for Muse is false (since GrokBot didn't mention Muse)
        let m1 = ChatMessage(id: "1", roomID: "r", sender: .me, senderName: "GrokBot", body: "hello from GrokBot", rtf: nil, status: .complete, createdAt: now)
        XCTAssertFalse(BridgeTurnPolicy.shouldReply(screenName: "GrokBot", messages: [m1], after: nil, humanScreenName: "Me", joinedGuests: joined, turnLimit: 4))
        XCTAssertFalse(BridgeTurnPolicy.shouldReply(screenName: "Muse", messages: [m1], after: nil, humanScreenName: "Me", joinedGuests: joined, turnLimit: 4))

        // 2. Human speaks to the room without restricting mentions -> all connected guests should reply
        let m2 = ChatMessage(id: "2", roomID: "r", sender: .me, senderName: "Me", body: "What do you all think?", rtf: nil, status: .complete, createdAt: now)
        XCTAssertTrue(BridgeTurnPolicy.shouldReply(screenName: "GrokBot", messages: [m1, m2], after: nil, humanScreenName: "Me", joinedGuests: joined, turnLimit: 4))
        XCTAssertTrue(BridgeTurnPolicy.shouldReply(screenName: "Muse", messages: [m1, m2], after: nil, humanScreenName: "Me", joinedGuests: joined, turnLimit: 4))
        XCTAssertTrue(BridgeTurnPolicy.shouldReply(screenName: "Antigravity", messages: [m1, m2], after: nil, humanScreenName: "Me", joinedGuests: joined, turnLimit: 4))

        // 3. Muse replies first -> GrokBot still hasn't replied to Me's message, so GrokBot is still true, while Muse is now false!
        let m3 = ChatMessage(id: "3", roomID: "r", sender: .me, senderName: "Muse", body: "I like the classic AIM design.", rtf: nil, status: .complete, createdAt: now)
        XCTAssertFalse(BridgeTurnPolicy.shouldReply(screenName: "Muse", messages: [m1, m2, m3], after: nil, humanScreenName: "Me", joinedGuests: joined, turnLimit: 4))
        XCTAssertTrue(BridgeTurnPolicy.shouldReply(screenName: "GrokBot", messages: [m1, m2, m3], after: nil, humanScreenName: "Me", joinedGuests: joined, turnLimit: 4))

        // 4. Human specifically mentions @Muse -> only Muse should reply, GrokBot and Antigravity stay quiet
        let m4 = ChatMessage(id: "4", roomID: "r", sender: .me, senderName: "GrokBot", body: "Agreed!", rtf: nil, status: .complete, createdAt: now)
        let m5 = ChatMessage(id: "5", roomID: "r", sender: .me, senderName: "Me", body: "@Muse tell me more", rtf: nil, status: .complete, createdAt: now)
        XCTAssertTrue(BridgeTurnPolicy.shouldReply(screenName: "Muse", messages: [m1, m2, m3, m4, m5], after: nil, humanScreenName: "Me", joinedGuests: joined, turnLimit: 4))
        XCTAssertFalse(BridgeTurnPolicy.shouldReply(screenName: "GrokBot", messages: [m1, m2, m3, m4, m5], after: nil, humanScreenName: "Me", joinedGuests: joined, turnLimit: 4))
        XCTAssertFalse(BridgeTurnPolicy.shouldReply(screenName: "Antigravity", messages: [m1, m2, m3, m4, m5], after: nil, humanScreenName: "Me", joinedGuests: joined, turnLimit: 4))

        // 5. Muse replies and explicitly mentions @Antigravity -> Antigravity wakes up!
        let m6 = ChatMessage(id: "6", roomID: "r", sender: .me, senderName: "Muse", body: "Sure! @Antigravity what do you think?", rtf: nil, status: .complete, createdAt: now)
        XCTAssertTrue(BridgeTurnPolicy.shouldReply(screenName: "Antigravity", messages: [m1, m2, m3, m4, m5, m6], after: nil, humanScreenName: "Me", joinedGuests: joined, turnLimit: 4))
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

    @MainActor
    func testLiveAppModelBridgeWaitWakeupStatusAndPrompt() async throws {
        let model = AppModel(database: database)
        defer { model.stopAll() }
        let port = model.bridgePort
        XCTAssertGreaterThan(port, 0)
        let token = model.currentEndpoint().token
        let session = URLSession(configuration: .ephemeral)

        // 1. Join via GET /join as GrokBot
        let joinURL = URL(string: "http://127.0.0.1:\(port)/join?token=\(token)&screenName=GrokBot&program=Grok%20Bot")!
        let (joinData, joinResp) = try await session.data(from: joinURL)
        XCTAssertEqual((joinResp as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(String(decoding: joinData, as: UTF8.self).contains("\"GrokBot\""))
        XCTAssertTrue(model.isGuestConnected("GrokBot"))

        // 2. GrokBot says hello so its lastOwnIndex is at the tail of Lobby
        let helloURL = URL(string: "http://127.0.0.1:\(port)/say?token=\(token)&screenName=GrokBot&room=Lobby&text=hello")!
        let (_, helloResp) = try await session.data(from: helloURL)
        XCTAssertEqual((helloResp as? HTTPURLResponse)?.statusCode, 200)

        // 3. Start a long-poll /wait task for GrokBot (timeout=5s), then send a human message 120ms later
        let started = Date()
        let waitURL = URL(string: "http://127.0.0.1:\(port)/wait?token=\(token)&room=Lobby&screenName=GrokBot&timeout=5")!
        async let waitPair = session.data(from: waitURL)

        try await Task.sleep(nanoseconds: 120_000_000)
        let lobbyID = try XCTUnwrap(model.rooms.first(where: { $0.kind == .lobby })?.id)
        model.sendHuman(roomID: lobbyID, plain: "@GrokBot what is the status?", rtf: nil)

        let (waitData, waitResp) = try await waitPair
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertEqual((waitResp as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertLessThan(elapsed, 2.0)
        let waitText = String(decoding: waitData, as: UTF8.self)
        XCTAssertTrue(waitText.contains("should_reply: yes"), waitText)
        XCTAssertTrue(waitText.contains("@GrokBot what is the status?"), waitText)

        // 4. Verify /status and /prompt?program=Muse
        let statusURL = URL(string: "http://127.0.0.1:\(port)/status?token=\(token)")!
        let (statusData, statusResp) = try await session.data(from: statusURL)
        XCTAssertEqual((statusResp as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(String(decoding: statusData, as: UTF8.self).contains("GrokBot"))

        let promptURL = URL(string: "http://127.0.0.1:\(port)/prompt?token=\(token)&program=Muse&room=Lobby")!
        let (promptData, promptResp) = try await session.data(from: promptURL)
        XCTAssertEqual((promptResp as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(String(decoding: promptData, as: UTF8.self).contains("\"screenName\":\"Muse\""))

        // 5. Verify /handoff?program=Antigravity and /transcript?format=json
        let handoffURL = URL(string: "http://127.0.0.1:\(port)/handoff?token=\(token)&program=Antigravity&room=Lobby&note=check%20status")!
        let (handoffData, handoffResp) = try await session.data(from: handoffURL)
        XCTAssertEqual((handoffResp as? HTTPURLResponse)?.statusCode, 200)
        let handoffText = String(decoding: handoffData, as: UTF8.self)
        XCTAssertTrue(handoffText.contains("SHADOWCHAT MULTI-PROGRAM CONTEXT HANDOFF"), handoffText)
        XCTAssertTrue(handoffText.contains("Antigravity"), handoffText)
        XCTAssertTrue(handoffText.contains("@GrokBot what is the status?"), handoffText)

        let jsonTranscriptURL = URL(string: "http://127.0.0.1:\(port)/transcript?token=\(token)&room=Lobby&format=json")!
        let (jsonData, jsonResp) = try await session.data(from: jsonTranscriptURL)
        XCTAssertEqual((jsonResp as? HTTPURLResponse)?.statusCode, 200)
        let jsonText = String(decoding: jsonData, as: UTF8.self)
        XCTAssertTrue(jsonText.contains("\"room\":\"Lobby\""), jsonText)
        XCTAssertTrue(jsonText.contains("GrokBot"), jsonText)
    }

    func testCliLoopModeAndRoleGroupMentionsOnBridge() {
        let endpoint = BridgeEndpoint(host: "127.0.0.1", port: 54321, token: "tok-cli")
        let cliText = ConnectPrompt.render(endpoint: endpoint, occupantNames: ["Me"], preset: .antigravity, roomName: "Lobby", mode: .cliLoop)
        XCTAssertTrue(cliText.contains("shadowchat-cli\" connect \"Antigravity\""))
        XCTAssertTrue(cliText.contains("shadowchat-cli\" listen \"Antigravity\" \"Lobby\" 300"))

        let now = Date()
        let joined = ["GrokBot", "Muse", "Antigravity", "Cursor"]
        let codersMsg = ChatMessage(id: "c1", roomID: "r", sender: .me, senderName: "Me", body: "@coders inspect this", rtf: nil, status: .complete, createdAt: now)
        XCTAssertTrue(BridgeTurnPolicy.shouldReply(screenName: "Antigravity", messages: [codersMsg], after: nil, humanScreenName: "Me", joinedGuests: joined, turnLimit: 4))
        XCTAssertTrue(BridgeTurnPolicy.shouldReply(screenName: "Cursor", messages: [codersMsg], after: nil, humanScreenName: "Me", joinedGuests: joined, turnLimit: 4))
        XCTAssertFalse(BridgeTurnPolicy.shouldReply(screenName: "Muse", messages: [codersMsg], after: nil, humanScreenName: "Me", joinedGuests: joined, turnLimit: 4))
        XCTAssertFalse(BridgeTurnPolicy.shouldReply(screenName: "GrokBot", messages: [codersMsg], after: nil, humanScreenName: "Me", joinedGuests: joined, turnLimit: 4))

        let thinkersMsg = ChatMessage(id: "t1", roomID: "r", sender: .me, senderName: "Me", body: "@thinkers brainstorm ideas", rtf: nil, status: .complete, createdAt: now)
        XCTAssertTrue(BridgeTurnPolicy.shouldReply(screenName: "Muse", messages: [thinkersMsg], after: nil, humanScreenName: "Me", joinedGuests: joined, turnLimit: 4))
        XCTAssertTrue(BridgeTurnPolicy.shouldReply(screenName: "GrokBot", messages: [thinkersMsg], after: nil, humanScreenName: "Me", joinedGuests: joined, turnLimit: 4))
        XCTAssertFalse(BridgeTurnPolicy.shouldReply(screenName: "Antigravity", messages: [thinkersMsg], after: nil, humanScreenName: "Me", joinedGuests: joined, turnLimit: 4))

        let localOnlyMsg = ChatMessage(id: "l1", roomID: "r", sender: .me, senderName: "Me", body: "@local run local clis only", rtf: nil, status: .complete, createdAt: now)
        XCTAssertFalse(BridgeTurnPolicy.shouldReply(screenName: "Muse", messages: [localOnlyMsg], after: nil, humanScreenName: "Me", joinedGuests: joined, turnLimit: 4))
        XCTAssertFalse(BridgeTurnPolicy.shouldReply(screenName: "Antigravity", messages: [localOnlyMsg], after: nil, humanScreenName: "Me", joinedGuests: joined, turnLimit: 4))

        let bridgeOnlyMsg = ChatMessage(id: "b1", roomID: "r", sender: .me, senderName: "Me", body: "@bridge everyone on the bridge answer", rtf: nil, status: .complete, createdAt: now)
        XCTAssertTrue(BridgeTurnPolicy.shouldReply(screenName: "Muse", messages: [bridgeOnlyMsg], after: nil, humanScreenName: "Me", joinedGuests: joined, turnLimit: 4))
        XCTAssertTrue(BridgeTurnPolicy.shouldReply(screenName: "Antigravity", messages: [bridgeOnlyMsg], after: nil, humanScreenName: "Me", joinedGuests: joined, turnLimit: 4))
    }
}
