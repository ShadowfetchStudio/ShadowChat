import AppKit
import Foundation

enum ParticipantID: String, Codable, CaseIterable, Identifiable, Equatable {
    case me
    case claudeCode
    case codex
    case grok
    case cursorGrok

    var id: String { rawValue }

    /// Turn order for @all, @room, and roundtable. Me is never in this list.
    static let agentOrder: [ParticipantID] = [.claudeCode, .codex, .grok, .cursorGrok]

    var screenName: String {
        switch self {
        case .me: return "Me"
        case .claudeCode: return "ClaudeCode"
        case .codex: return "Codex"
        case .grok: return "Grok"
        case .cursorGrok: return "CursorGrok"
        }
    }

    var nsColor: NSColor {
        switch self {
        case .me:
            return NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.80, alpha: 1)
        case .claudeCode:
            return NSColor(calibratedRed: 0.50, green: 0.04, blue: 0.16, alpha: 1)
        case .codex:
            return NSColor(calibratedRed: 0.0, green: 0.42, blue: 0.13, alpha: 1)
        case .grok:
            return NSColor(calibratedRed: 0.90, green: 0.40, blue: 0.0, alpha: 1)
        case .cursorGrok:
            return NSColor(calibratedRed: 0.0, green: 0.45, blue: 0.48, alpha: 1)
        }
    }
}

enum RunPhase: String, Codable, Equatable {
    case stopped
    case running
    case paused

    var label: String {
        switch self {
        case .stopped: return "Stopped"
        case .running: return "Running"
        case .paused: return "Paused"
        }
    }
}

enum MessageStatus: String, Codable, Equatable {
    case streaming
    case complete
    case cancelled
    case error
}

enum RoomKind: String, Codable, Equatable {
    case lobby
    case project
}

struct Room: Identifiable, Equatable {
    var id: String
    var name: String
    var kind: RoomKind
    var projectPath: String?
    var worktreePath: String?
    var allowFileChanges: Bool
    var roundtable: Bool
    var turnLimit: Int
    var runState: RunPhase
    var createdAt: Date

    static func lobby(id: String = UUID().uuidString, now: Date = Date()) -> Room {
        Room(
            id: id,
            name: "Lobby",
            kind: .lobby,
            projectPath: nil,
            worktreePath: nil,
            allowFileChanges: false,
            roundtable: false,
            turnLimit: 4,
            runState: .stopped,
            createdAt: now
        )
    }
}

struct ChatMessage: Identifiable, Equatable {
    var id: String
    var roomID: String
    var sender: ParticipantID
    var senderName: String
    var body: String
    var rtf: Data?
    var status: MessageStatus
    var createdAt: Date
}

struct Buddy: Identifiable, Equatable {
    var id: ParticipantID
    var enabled: Bool
    var online: Bool
    var reason: String
}

struct Presence: Equatable {
    var online: Bool
    var reason: String
}

struct ConnectedGuest: Identifiable, Equatable {
    var screenName: String
    var program: String
    var roomName: String
    var lastSeenAt: Date
    var isListening: Bool

    var id: String { screenName }
}

enum Selection: Hashable {
    case buddy(ParticipantID)
    case guest(String)
    case room(String)
}
