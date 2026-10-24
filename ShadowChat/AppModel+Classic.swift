import AppKit
import Foundation

enum Prefs {
    static let sounds = "ShadowChat.soundsOn"
    static let timestamps = "ShadowChat.showTimestamps"
    static let smileys = "ShadowChat.smileyGraphics"
    static let autoSignOn = "ShadowChat.autoSignOn"
    static let connectAtLaunch = "ShadowChat.showConnectAtLaunch"
    static let openOnIncoming = "ShadowChat.openOnIncoming"
    static let awayPresets = "ShadowChat.awayPresets"
}

/// The classic-messenger layer: sounds, unread counts, typing, sign-on doors, and away messages.
extension AppModel {
    // MARK: - Sounds

    func playSound(_ sound: ClassicSound) {
        guard soundsOn else { return }
        ClassicSoundPlayer.shared.play(sound)
    }

    // MARK: - Windows, unread, and incoming messages

    func roomWindowAppeared(_ roomID: String) {
        openRoomWindows.insert(roomID)
    }

    func roomWindowDisappeared(_ roomID: String) {
        openRoomWindows.remove(roomID)
        focusedRooms.remove(roomID)
    }

    func setRoomFocused(_ roomID: String, focused: Bool) {
        if focused {
            focusedRooms.insert(roomID)
            markRead(roomID)
        } else {
            focusedRooms.remove(roomID)
        }
    }

    func markRead(_ roomID: String) {
        guard unread[roomID] != nil else { return }
        unread[roomID] = nil
        updateDockBadge()
    }

    var totalUnread: Int { unread.values.reduce(0, +) }

    /// Called once per finished message from anyone other than you.
    func noteIncoming(_ message: ChatMessage) {
        guard message.status == .complete else { return }
        if message.senderName == "ShadowChat" { return }
        if BridgeTurnPolicy.isHuman(message, humanScreenName: screenName, joinedGuests: joinedGuests) { return }
        let watching = focusedRooms.contains(message.roomID) && NSApp.isActive
        if !watching {
            unread[message.roomID, default: 0] += 1
            updateDockBadge()
            if !NSApp.isActive {
                NSApp.requestUserAttention(.informationalRequest)
            }
        }
        playSound(.imReceive)
        if openOnIncoming, signedOn, !openRoomWindows.contains(message.roomID) {
            // Like an old IM client, a new message pops its window open.
            openRequest = OpenRequest(id: message.roomID, ticket: UUID())
        }
    }

    func updateDockBadge() {
        let total = totalUnread
        NSApp.dockTile.badgeLabel = total > 0 ? "\(total)" : nil
    }

    /// Names currently streaming a reply in a room, for the "is typing…" line.
    func typingNames(roomID: String) -> [String] {
        (messages[roomID] ?? []).filter { $0.status == .streaming }.map(\.senderName)
    }

    func lastReceived(roomID: String) -> Date? {
        (messages[roomID] ?? []).last { message in
            message.status == .complete
                && message.senderName != "ShadowChat"
                && !BridgeTurnPolicy.isHuman(message, humanScreenName: screenName, joinedGuests: joinedGuests)
        }?.createdAt
    }

    // MARK: - Sign-on doors and idle buddies

    func noteTransition(_ name: String, kind: BuddyTransition.Kind) {
        transitions[name.lowercased()] = BuddyTransition(kind: kind, at: Date())
        let time = DateFormatter()
        time.dateFormat = "h:mm a"
        ticker = "\(name) signed \(kind == .arrived ? "on" : "off") at \(time.string(from: Date()))."
        if signedOn {
            playSound(kind == .arrived ? .doorOpen : .doorClose)
        }
    }

    func transition(for name: String, now: Date = Date()) -> BuddyTransition? {
        guard let value = transitions[name.lowercased()], value.isVisible(now: now) else { return nil }
        return value
    }

    func guestActivity(_ name: String, now: Date = Date()) -> GuestActivity? {
        guard let guest = connectedGuests.first(where: { $0.screenName.caseInsensitiveCompare(name) == .orderedSame }) else {
            return nil
        }
        return GuestActivity.state(lastSeen: guest.lastSeenAt, now: now)
    }

    // MARK: - Away messages

    var isAway: Bool { awayMessage != nil }

    var expandedAwayMessage: String? {
        awayMessage.map { AwayPreset.expand($0, screenName: screenName.isEmpty ? "Me" : screenName) }
    }

    func goAway(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        awayMessage = trimmed.isEmpty ? AwayPreset.defaults[0].message : trimmed
        ticker = "You are away: \(expandedAwayMessage ?? "")"
    }

    func comeBack() {
        guard awayMessage != nil else { return }
        awayMessage = nil
        ticker = "Welcome back, \(screenName.isEmpty ? "Me" : screenName)!"
    }

    func saveAwayPreset(label: String, message: String) {
        let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanLabel.isEmpty, !cleanMessage.isEmpty else { return }
        var next = awayPresets
        if let index = next.firstIndex(where: { $0.label.caseInsensitiveCompare(cleanLabel) == .orderedSame }) {
            next[index].message = cleanMessage
        } else {
            next.append(AwayPreset(label: cleanLabel, message: cleanMessage))
        }
        awayPresets = next
    }

    func deleteAwayPreset(label: String) {
        awayPresets.removeAll { $0.label == label }
    }

    func persistAwayPresets() {
        if let data = try? JSONEncoder().encode(awayPresets) {
            UserDefaults.standard.set(data, forKey: Prefs.awayPresets)
        }
    }

    static func loadAwayPresets() -> [AwayPreset] {
        guard let data = UserDefaults.standard.data(forKey: Prefs.awayPresets),
              let list = try? JSONDecoder().decode([AwayPreset].self, from: data),
              !list.isEmpty else {
            return AwayPreset.defaults
        }
        return list
    }
}
