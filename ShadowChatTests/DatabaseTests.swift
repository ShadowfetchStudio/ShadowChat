import XCTest
@testable import ShadowChat

final class DatabaseTests: XCTestCase {
    private var database: Database!
    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        database = try Database(path: directory.appendingPathComponent("test.sqlite").path)
    }

    override func tearDownWithError() throws {
        database = nil
        try? FileManager.default.removeItem(at: directory)
    }

    func testLobbyDefaultsAndMessages() throws {
        let lobby = try database.ensureLobby()
        XCTAssertEqual(lobby.name, "Lobby")
        XCTAssertEqual(lobby.kind, .lobby)
        XCTAssertFalse(lobby.allowFileChanges)
        XCTAssertFalse(lobby.roundtable)
        XCTAssertEqual(lobby.turnLimit, 4)
        XCTAssertEqual(lobby.runState, .stopped)
        let again = try database.ensureLobby()
        XCTAssertEqual(again.id, lobby.id)

        var message = ChatMessage(
            id: UUID().uuidString,
            roomID: lobby.id,
            sender: .me,
            senderName: "Me",
            body: "hello",
            rtf: nil,
            status: .streaming,
            createdAt: Date()
        )
        try database.insertMessage(message)
        try database.cancelDanglingStreams()
        let loaded = try database.messages(roomID: lobby.id)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].status, .cancelled)
        XCTAssertEqual(loaded[0].body, "hello")

        message.status = .complete
        message.body = "hello there"
        try database.updateMessage(id: message.id, body: message.body, status: .complete)
        XCTAssertEqual(try database.messages(roomID: lobby.id)[0].body, "hello there")
    }

    func testSessionsAndBuddyEnabled() throws {
        let lobby = try database.ensureLobby()
        XCTAssertNil(try database.sessionID(roomID: lobby.id, participant: .claudeCode))
        try database.saveSession(roomID: lobby.id, participant: .claudeCode, sessionID: "sess")
        XCTAssertEqual(try database.sessionID(roomID: lobby.id, participant: .claudeCode), "sess")
        try database.saveSession(roomID: lobby.id, participant: .claudeCode, sessionID: "sess-2")
        XCTAssertEqual(try database.sessionID(roomID: lobby.id, participant: .claudeCode), "sess-2")
        try database.clearSession(roomID: lobby.id, participant: .claudeCode)
        XCTAssertNil(try database.sessionID(roomID: lobby.id, participant: .claudeCode))

        try database.setEnabled(.codex, enabled: false)
        XCTAssertEqual(try database.enabledParticipants()[.codex], false)
        try database.setEnabled(.codex, enabled: true)
        XCTAssertEqual(try database.enabledParticipants()[.codex], true)
    }

    func testProjectRoomFileChangesStayOffUntilSaved() throws {
        var room = Room(
            id: UUID().uuidString,
            name: "Demo",
            kind: .project,
            projectPath: "/tmp/demo",
            worktreePath: nil,
            allowFileChanges: false,
            roundtable: true,
            turnLimit: 4,
            runState: .paused,
            createdAt: Date()
        )
        try database.insertRoom(room)
        var loaded = try database.rooms().first { $0.id == room.id }
        XCTAssertEqual(loaded?.allowFileChanges, false)
        room.allowFileChanges = true
        room.worktreePath = "/tmp/worktree"
        try database.saveRoom(room)
        loaded = try database.rooms().first { $0.id == room.id }
        XCTAssertEqual(loaded?.allowFileChanges, true)
        XCTAssertEqual(loaded?.worktreePath, "/tmp/worktree")
        XCTAssertEqual(loaded?.runState, .paused)
    }
}
