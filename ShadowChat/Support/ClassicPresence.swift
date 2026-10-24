import AppKit
import Foundation

/// Text smileys drawn as yellow faces in the transcript, the way old IM clients did.
/// Only whole tokens are swapped, so `http://`, `a:b`, and code stay untouched.
enum Smileys {
    static let table: [(token: String, face: String)] = [
        ("O:-)", "😇"), (">:o", "😠"), (":'(", "😢"), ("8-)", "😎"),
        (":-)", "🙂"), (":)", "🙂"), (":-(", "🙁"), (":(", "🙁"),
        (";-)", "😉"), (";)", "😉"), (":-D", "😀"), (":D", "😀"),
        (":-P", "😛"), (":P", "😛"), (":p", "😛"), (":-O", "😮"), (":O", "😮"), (":o", "😮"),
        (":-*", "😘"), (":-$", "🤑"), (":-!", "😬"), (":-[", "😳"), (":-\\", "😕"), ("<3", "❤️")
    ]

    static let menuTokens = [":-)", ":-(", ";-)", ":-D", ":-P", ":-O", ":'(", "8-)", ":-*", ">:o", "O:-)", "<3"]

    private static let regex: NSRegularExpression = {
        let alternation = table
            .map(\.token)
            .sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        return try! NSRegularExpression(pattern: "(?<!\\S)(?:\(alternation))(?![^\\s.,!?])")
    }()

    private static let faces: [String: String] = Dictionary(table.map { ($0.token, $0.face) }, uniquingKeysWith: { first, _ in first })

    static func face(for token: String) -> String? { faces[token] }

    static func replacing(_ text: String) -> String {
        let mutable = NSMutableAttributedString(string: text)
        replace(in: mutable)
        return mutable.string
    }

    static func replace(in text: NSMutableAttributedString) {
        let source = text.string as NSString
        let matches = regex.matches(in: text.string, range: NSRange(location: 0, length: source.length))
        for match in matches.reversed() {
            let token = source.substring(with: match.range)
            guard let face = faces[token] else { continue }
            text.replaceCharacters(in: match.range, with: face)
        }
    }
}

/// An away message, with the classic `%n` (your screen name), `%t` (time) and `%d` (date) codes.
struct AwayPreset: Codable, Equatable, Identifiable {
    var label: String
    var message: String

    var id: String { label }

    static let defaults: [AwayPreset] = [
        AwayPreset(label: "Be Right Back", message: "brb! The bots can keep talking without me."),
        AwayPreset(label: "Out to Lunch", message: "Out to lunch since %t. @mention me and I'll catch up."),
        AwayPreset(label: "Heads Down", message: "Heads down coding. Only @%n if it's urgent."),
        AwayPreset(label: "Sleeping", message: "zzz… signed on but asleep. Leave a message!")
    ]

    static func expand(_ message: String, screenName: String, now: Date = Date()) -> String {
        let time = DateFormatter()
        time.dateFormat = "h:mm a"
        let date = DateFormatter()
        date.dateFormat = "M/d/yyyy"
        return message
            .replacingOccurrences(of: "%n", with: screenName)
            .replacingOccurrences(of: "%t", with: time.string(from: now))
            .replacingOccurrences(of: "%d", with: date.string(from: now))
    }
}

/// How a connected bridge program looks in the Buddy List, from how recently it checked in.
enum GuestActivity: Equatable {
    case active
    case idle(minutes: Int)
    case gone

    static let idleAfter: TimeInterval = 5 * 60
    static let goneAfter: TimeInterval = 30 * 60

    static func state(lastSeen: Date, now: Date = Date()) -> GuestActivity {
        let quiet = now.timeIntervalSince(lastSeen)
        if quiet >= goneAfter { return .gone }
        if quiet >= idleAfter { return .idle(minutes: Int(quiet / 60)) }
        return .active
    }

    /// Old-school idle readout: `Idle 7m`, `Idle 1:05`.
    static func label(minutes: Int) -> String {
        minutes >= 60 ? "Idle \(minutes / 60):\(String(format: "%02d", minutes % 60))" : "Idle \(minutes)m"
    }
}

/// A buddy who just signed on (door open) or off (door closed). Shown for a few seconds.
struct BuddyTransition: Equatable {
    enum Kind: Equatable {
        case arrived
        case departed
    }

    var kind: Kind
    var at: Date

    static let visibleFor: TimeInterval = 10

    func isVisible(now: Date = Date()) -> Bool {
        now.timeIntervalSince(at) < Self.visibleFor
    }
}

enum TranscriptStamp {
    /// `(10:42:15 PM)` like the classic timestamp option.
    static func text(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm:ss a"
        return "(\(formatter.string(from: date)))"
    }
}
