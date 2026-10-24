import Foundation

/// Local chat commands typed into the compose box, for example `/help`.
/// Commands never reach an agent and are never executed as shell.
enum SlashCommand: Equatable {
    case help, who, clear, start, pause, stop, roundtable, connect, export
    case unknown(String)

    /// Returns nil for normal chat. A leading slash only counts as a command when the
    /// whole message is a single alphabetic word (or a known command followed by text),
    /// so file paths such as `/usr/bin` still send as ordinary messages.
    static func parse(_ text: String) -> SlashCommand? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/"), trimmed.count > 1 else { return nil }
        let parts = trimmed.dropFirst().split(whereSeparator: { $0.isWhitespace })
        guard let first = parts.first else { return nil }
        let word = String(first).lowercased()
        guard word.allSatisfy({ $0.isLetter }) else { return nil }
        switch word {
        case "help", "?", "commands": return .help
        case "who", "people", "online": return .who
        case "clear", "cls": return .clear
        case "start", "go": return .start
        case "pause": return .pause
        case "stop": return .stop
        case "roundtable", "round": return .roundtable
        case "connect", "join": return .connect
        case "export", "save": return .export
        default:
            return parts.count == 1 ? .unknown(word) : nil
        }
    }

    static let helpText = """
    ShadowChat quick help
    • Type a message and press Return to send. Shift-Return adds a new line.
    • @name talks to one helper (for example @Claude or @Codex). @all talks to everyone.
    • Green dots in the buddy list mean a helper is ready. Double-click one to chat privately.
    • Commands: /who  /start  /pause  /stop  /roundtable  /clear  /connect  /export  /help
    """
}

enum TranscriptExport {
    static func markdown(roomName: String, messages: [ChatMessage], exportedAt: Date = Date()) -> String {
        let stamp = ISO8601DateFormatter().string(from: exportedAt)
        var lines = ["# \(roomName) — ShadowChat transcript", "", "Exported \(stamp)", ""]
        for message in messages where message.status != .streaming {
            let suffix: String
            switch message.status {
            case .cancelled: suffix = " _(cancelled)_"
            case .error: suffix = " _(error)_"
            default: suffix = ""
            }
            lines.append("**\(message.senderName):** \(message.body)\(suffix)")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    static func suggestedFileName(roomName: String) -> String {
        let safe = roomName.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
        let base = String(safe).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return (base.isEmpty ? "room" : base) + "-transcript.md"
    }
}
