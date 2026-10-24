import Foundation

enum MentionTarget: Equatable {
    case everyone
    case agent(ParticipantID)
}

struct TurnPlan: Equatable {
    var sender: ParticipantID
    var text: String
    var phase: RunPhase
    var roundtable: Bool
    var turnLimit: Int
    var roster: [Buddy]
}

enum TurnPlanner {
    static func plan(_ input: TurnPlan) -> [ParticipantID] {
        guard input.sender == .me else { return [] }
        guard input.phase == .running else { return [] }

        let available = ParticipantID.agentOrder.filter { id in
            guard let buddy = input.roster.first(where: { $0.id == id }) else { return false }
            return buddy.enabled && buddy.online
        }

        let mentions = parseMentions(input.text)
        let selected: [ParticipantID]
        if mentions.containsEveryone {
            selected = available
        } else if !mentions.agents.isEmpty {
            var seen = Set<ParticipantID>()
            selected = mentions.agents.filter { id in
                guard available.contains(id) else { return false }
                return seen.insert(id).inserted
            }
        } else if input.roundtable {
            selected = available
        } else {
            return []
        }

        let cap = min(max(input.turnLimit, 1), 12)
        return Array(selected.prefix(cap))
    }

    /// The latest human message when no agent has completed a reply after it.
    static func unansweredHumanText(in messages: [ChatMessage]) -> String? {
        guard let index = messages.lastIndex(where: { $0.sender == .me && $0.status == .complete }) else {
            return nil
        }
        let later = messages.suffix(from: messages.index(after: index))
        let answered = later.contains { message in
            ParticipantID.agentOrder.contains(message.sender) && message.status == .complete
        }
        return answered ? nil : messages[index].body
    }

    static func parseMentions(_ text: String) -> (containsEveryone: Bool, agents: [ParticipantID]) {
        let pattern = #"@([A-Za-z][A-Za-z0-9_-]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (false, [])
        }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var everyone = false
        var agents: [ParticipantID] = []
        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            if match.range.location > 0 {
                let previous = ns.substring(with: NSRange(location: match.range.location - 1, length: 1))
                if previous.range(of: "[A-Za-z0-9_]", options: .regularExpression) != nil {
                    continue
                }
            }
            let token = ns.substring(with: match.range(at: 1))
            switch target(for: token) {
            case .everyone:
                everyone = true
            case .agent(let id):
                agents.append(id)
            case nil:
                break
            }
        }
        return (everyone, agents)
    }

    static func target(for token: String) -> MentionTarget? {
        switch token.lowercased() {
        case "all", "room":
            return .everyone
        case "claude", "claudecode", "claude-code":
            return .agent(.claudeCode)
        case "codex":
            return .agent(.codex)
        case "grok":
            return .agent(.grok)
        case "cursor", "cursorgrok", "cursor-grok", "antigravity", "cursorantigravity":
            return .agent(.cursorGrok)
        case "me":
            return .agent(.me)
        default:
            return nil
        }
    }
}
