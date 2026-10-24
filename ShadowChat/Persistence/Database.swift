import Foundation
import SQLite3

enum DatabaseError: LocalizedError {
    case open(String)
    case exec(String)

    var errorDescription: String? {
        switch self {
        case .open(let message): return "Could not open the chat database. \(message)"
        case .exec(let message): return message
        }
    }
}

final class Database {
    private var db: OpaquePointer?
    private let lock = NSLock()
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    static func defaultPath() -> String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShadowChat", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("shadowchat.sqlite").path
    }

    init(path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &handle, flags, nil)
        guard rc == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let handle { sqlite3_close(handle) }
            throw DatabaseError.open(message)
        }
        db = handle
        try exec("PRAGMA foreign_keys = ON;")
        try migrate()
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    func ensureLobby() throws -> Room {
        if let existing = try rooms().first(where: { $0.kind == .lobby }) {
            return existing
        }
        let room = Room.lobby()
        try insertRoom(room)
        return room
    }

    func rooms() throws -> [Room] {
        try query("SELECT id, name, kind, project_path, worktree_path, allow_file_changes, roundtable, turn_limit, run_state, created_at FROM rooms ORDER BY created_at ASC") { stmt in
            Room(
                id: columnText(stmt, 0),
                name: columnText(stmt, 1),
                kind: RoomKind(rawValue: columnText(stmt, 2)) ?? .project,
                projectPath: columnOptionalText(stmt, 3),
                worktreePath: columnOptionalText(stmt, 4),
                allowFileChanges: sqlite3_column_int(stmt, 5) != 0,
                roundtable: sqlite3_column_int(stmt, 6) != 0,
                turnLimit: Int(sqlite3_column_int(stmt, 7)),
                runState: RunPhase(rawValue: columnText(stmt, 8)) ?? .stopped,
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 9))
            )
        }
    }

    func insertRoom(_ room: Room) throws {
        try exec(
            """
            INSERT INTO rooms (id, name, kind, project_path, worktree_path, allow_file_changes, roundtable, turn_limit, run_state, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(room.id), .text(room.name), .text(room.kind.rawValue),
                .optional(room.projectPath), .optional(room.worktreePath),
                .int(room.allowFileChanges ? 1 : 0), .int(room.roundtable ? 1 : 0),
                .int(Int32(room.turnLimit)), .text(room.runState.rawValue),
                .double(room.createdAt.timeIntervalSince1970)
            ]
        )
    }

    func saveRoom(_ room: Room) throws {
        try exec(
            """
            UPDATE rooms
            SET name = ?, kind = ?, project_path = ?, worktree_path = ?, allow_file_changes = ?, roundtable = ?, turn_limit = ?, run_state = ?
            WHERE id = ?
            """,
            bindings: [
                .text(room.name), .text(room.kind.rawValue),
                .optional(room.projectPath), .optional(room.worktreePath),
                .int(room.allowFileChanges ? 1 : 0), .int(room.roundtable ? 1 : 0),
                .int(Int32(min(max(room.turnLimit, 1), 12))), .text(room.runState.rawValue),
                .text(room.id)
            ]
        )
    }

    func messages(roomID: String) throws -> [ChatMessage] {
        try query(
            """
            SELECT id, room_id, sender, sender_name, body, rtf, status, created_at
            FROM messages WHERE room_id = ? ORDER BY created_at ASC, rowid ASC
            """,
            bindings: [.text(roomID)]
        ) { stmt in
            ChatMessage(
                id: columnText(stmt, 0),
                roomID: columnText(stmt, 1),
                sender: ParticipantID(rawValue: columnText(stmt, 2)) ?? .me,
                senderName: columnText(stmt, 3),
                body: columnText(stmt, 4),
                rtf: columnBlob(stmt, 5),
                status: MessageStatus(rawValue: columnText(stmt, 6)) ?? .complete,
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7))
            )
        }
    }

    func insertMessage(_ message: ChatMessage) throws {
        let found: [Int] = try query(
            "SELECT 1 FROM rooms WHERE id = ?",
            bindings: [.text(message.roomID)]
        ) { _ in 1 }
        guard found.first == 1 else {
            throw DatabaseError.exec("That room does not exist.")
        }
        try exec(
            """
            INSERT INTO messages (id, room_id, sender, sender_name, body, rtf, status, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(message.id), .text(message.roomID), .text(message.sender.rawValue),
                .text(message.senderName), .text(message.body), .blob(message.rtf),
                .text(message.status.rawValue), .double(message.createdAt.timeIntervalSince1970)
            ]
        )
    }

    func updateMessage(id: String, body: String, status: MessageStatus) throws {
        try exec(
            "UPDATE messages SET body = ?, status = ? WHERE id = ?",
            bindings: [.text(body), .text(status.rawValue), .text(id)]
        )
    }

    func cancelDanglingStreams() throws {
        try exec("UPDATE messages SET status = 'cancelled' WHERE status = 'streaming'")
    }

    func sessionID(roomID: String, participant: ParticipantID) throws -> String? {
        let rows: [String] = try query(
            "SELECT session_id FROM sessions WHERE room_id = ? AND participant = ?",
            bindings: [.text(roomID), .text(participant.rawValue)]
        ) { columnText($0, 0) }
        return rows.first
    }

    func saveSession(roomID: String, participant: ParticipantID, sessionID: String) throws {
        try exec(
            """
            INSERT INTO sessions (room_id, participant, session_id, updated_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(room_id, participant) DO UPDATE SET session_id = excluded.session_id, updated_at = excluded.updated_at
            """,
            bindings: [
                .text(roomID), .text(participant.rawValue), .text(sessionID),
                .double(Date().timeIntervalSince1970)
            ]
        )
    }

    func clearSession(roomID: String, participant: ParticipantID) throws {
        try exec(
            "DELETE FROM sessions WHERE room_id = ? AND participant = ?",
            bindings: [.text(roomID), .text(participant.rawValue)]
        )
    }

    func enabledParticipants() throws -> [ParticipantID: Bool] {
        let rows: [(ParticipantID, Bool)] = try query("SELECT participant, enabled FROM buddies") { stmt in
            let id = ParticipantID(rawValue: columnText(stmt, 0))
            return (id ?? .me, sqlite3_column_int(stmt, 1) != 0)
        }
        var map: [ParticipantID: Bool] = [:]
        for (id, enabled) in rows where id != .me { map[id] = enabled }
        return map
    }

    func setEnabled(_ participant: ParticipantID, enabled: Bool) throws {
        try exec(
            """
            INSERT INTO buddies (participant, enabled) VALUES (?, ?)
            ON CONFLICT(participant) DO UPDATE SET enabled = excluded.enabled
            """,
            bindings: [.text(participant.rawValue), .int(enabled ? 1 : 0)]
        )
    }

    private func migrate() throws {
        try exec(
            """
            CREATE TABLE IF NOT EXISTS rooms (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              kind TEXT NOT NULL,
              project_path TEXT,
              worktree_path TEXT,
              allow_file_changes INTEGER NOT NULL DEFAULT 0,
              roundtable INTEGER NOT NULL DEFAULT 0,
              turn_limit INTEGER NOT NULL DEFAULT 4,
              run_state TEXT NOT NULL DEFAULT 'stopped',
              created_at REAL NOT NULL
            );
            """
        )
        try exec(
            """
            CREATE TABLE IF NOT EXISTS messages (
              id TEXT PRIMARY KEY,
              room_id TEXT NOT NULL,
              sender TEXT NOT NULL,
              sender_name TEXT NOT NULL,
              body TEXT NOT NULL,
              rtf BLOB,
              status TEXT NOT NULL,
              created_at REAL NOT NULL
            );
            """
        )
        try exec(
            """
            CREATE TABLE IF NOT EXISTS sessions (
              room_id TEXT NOT NULL,
              participant TEXT NOT NULL,
              session_id TEXT NOT NULL,
              updated_at REAL NOT NULL,
              PRIMARY KEY (room_id, participant)
            );
            """
        )
        try exec(
            """
            CREATE TABLE IF NOT EXISTS buddies (
              participant TEXT PRIMARY KEY,
              enabled INTEGER NOT NULL
            );
            """
        )
        try exec("CREATE INDEX IF NOT EXISTS messages_room ON messages(room_id, created_at);")
    }

    private enum Binding {
        case text(String)
        case optional(String?)
        case int(Int32)
        case double(Double)
        case blob(Data?)
    }

    private func exec(_ sql: String, bindings: [Binding] = []) throws {
        try withStatement(sql, bindings: bindings) { stmt, db in
            let rc = sqlite3_step(stmt)
            if rc != SQLITE_DONE && rc != SQLITE_ROW {
                throw DatabaseError.exec(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    private func query<T>(_ sql: String, bindings: [Binding] = [], map: (OpaquePointer) -> T) throws -> [T] {
        try withStatement(sql, bindings: bindings) { stmt, db in
            var rows: [T] = []
            while true {
                let rc = sqlite3_step(stmt)
                if rc == SQLITE_ROW {
                    rows.append(map(stmt))
                } else if rc == SQLITE_DONE {
                    break
                } else {
                    throw DatabaseError.exec(String(cString: sqlite3_errmsg(db)))
                }
            }
            return rows
        }
    }

    private func withStatement<T>(_ sql: String, bindings: [Binding], body: (OpaquePointer, OpaquePointer) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { throw DatabaseError.exec("Database is closed.") }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw DatabaseError.exec(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        for (index, binding) in bindings.enumerated() {
            let i = Int32(index + 1)
            switch binding {
            case .text(let value):
                bindText(stmt, i, value)
            case .optional(let value):
                if let value {
                    bindText(stmt, i, value)
                } else {
                    sqlite3_bind_null(stmt, i)
                }
            case .int(let value):
                sqlite3_bind_int(stmt, i, value)
            case .double(let value):
                sqlite3_bind_double(stmt, i, value)
            case .blob(let data):
                if let data {
                    _ = data.withUnsafeBytes { raw in
                        sqlite3_bind_blob(stmt, i, raw.baseAddress, Int32(data.count), transient)
                    }
                } else {
                    sqlite3_bind_null(stmt, i)
                }
            }
        }
        return try body(stmt, db)
    }

    private func bindText(_ stmt: OpaquePointer, _ index: Int32, _ value: String) {
        let data = Data(value.utf8)
        if data.isEmpty {
            sqlite3_bind_text(stmt, index, "", 0, transient)
            return
        }
        data.withUnsafeBytes { raw in
            let pointer = raw.bindMemory(to: CChar.self).baseAddress
            sqlite3_bind_text(stmt, index, pointer, Int32(data.count), transient)
        }
    }

    private func columnText(_ stmt: OpaquePointer, _ index: Int32) -> String {
        guard let bytes = sqlite3_column_text(stmt, index) else { return "" }
        let count = Int(sqlite3_column_bytes(stmt, index))
        guard count > 0 else { return "" }
        let data = Data(bytes: bytes, count: count)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func columnOptionalText(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        if sqlite3_column_type(stmt, index) == SQLITE_NULL { return nil }
        let text = columnText(stmt, index)
        return text.isEmpty ? nil : text
    }

    private func columnBlob(_ stmt: OpaquePointer, _ index: Int32) -> Data? {
        if sqlite3_column_type(stmt, index) == SQLITE_NULL { return nil }
        guard let bytes = sqlite3_column_blob(stmt, index) else { return nil }
        let count = Int(sqlite3_column_bytes(stmt, index))
        return Data(bytes: bytes, count: count)
    }
}
