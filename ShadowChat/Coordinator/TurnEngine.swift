import Foundation

/// Sequential turn queue. Pause lets the current CLI finish and holds the rest.
/// Stop drops everyone still waiting and marks the active turn for cancellation.
struct TurnEngine: Equatable {
    var phase: RunPhase = .stopped
    var queue: [ParticipantID] = []
    var active: ParticipantID?
    var cancelCurrent = false

    mutating func start() {
        phase = .running
        cancelCurrent = false
    }

    mutating func pause() {
        guard phase == .running else { return }
        phase = .paused
    }

    mutating func stop() {
        phase = .stopped
        queue.removeAll()
        if active != nil {
            cancelCurrent = true
        }
    }

    mutating func enqueue(_ plan: [ParticipantID]) {
        guard phase == .running else { return }
        queue.append(contentsOf: plan)
    }

    mutating func dequeueIfIdle() -> ParticipantID? {
        guard phase == .running, active == nil, !queue.isEmpty else { return nil }
        let next = queue.removeFirst()
        active = next
        cancelCurrent = false
        return next
    }

    mutating func finishCurrent() {
        active = nil
        cancelCurrent = false
    }
}

enum StopPolicy {
    /// Partial text already stored on the message stays. Stop only changes status.
    static func status(wasKilled: Bool, exitCode: Int32, producedText: Bool) -> MessageStatus {
        if wasKilled { return .cancelled }
        if exitCode == 0 { return .complete }
        if producedText { return .error }
        return .error
    }
}
