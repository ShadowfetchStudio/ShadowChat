import Foundation

struct AgentTurnContext {
    var prompt: String
    var cwd: String
    var writable: Bool
    var sessionID: String?
    var grokModel: String
}

struct AgentTurnOutcome {
    var text: String
    var sessionID: String?
}

enum AgentFailure: Error {
    case cancelled(String)
    case failed(String)
}

final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func with<R>(_ body: (inout T) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}

enum AgentService {
    static func run(
        participant: ParticipantID,
        context: AgentTurnContext,
        handle: TurnHandle,
        onText: @escaping @Sendable (String) -> Void
    ) async throws -> AgentTurnOutcome {
        switch participant {
        case .grok:
            return try await runGrok(context: context, handle: handle, onText: onText)
        case .claudeCode, .codex, .cursorGrok:
            return try await runCLI(participant: participant, context: context, handle: handle, onText: onText)
        case .me:
            throw AgentFailure.failed("Me does not have an agent adapter.")
        }
    }

    private static func runCLI(
        participant: ParticipantID,
        context: AgentTurnContext,
        handle: TurnHandle,
        onText: @escaping @Sendable (String) -> Void
    ) async throws -> AgentTurnOutcome {
        let freshID = UUID().uuidString
        let invocation: CLIInvocation
        switch participant {
        case .claudeCode:
            invocation = CLICommands.claude(
                prompt: context.prompt,
                cwd: context.cwd,
                writable: context.writable,
                sessionID: context.sessionID,
                newSessionID: freshID
            )
        case .codex:
            invocation = CLICommands.codex(
                prompt: context.prompt,
                cwd: context.cwd,
                writable: context.writable,
                sessionID: context.sessionID
            )
        case .cursorGrok:
            invocation = CLICommands.cursorGrok(
                prompt: context.prompt,
                cwd: context.cwd,
                writable: context.writable,
                sessionID: context.sessionID,
                newSessionID: freshID
            )
        default:
            throw AgentFailure.failed("No CLI for \(participant.screenName).")
        }
        if let banned = CLICommands.containsBannedFlag(invocation.arguments) {
            throw AgentFailure.failed("Refusing to launch \(participant.screenName) with \(banned).")
        }

        let process = LiveProcess()
        handle.setKill { process.terminate() }
        let parser = LockedBox(LineParser(participant: participant))

        let result = await process.run(invocation) { line in
            let update = parser.with { $0.consume(line) }
            if let update {
                onText(update)
            }
        }
        let text = parser.with { $0.text }
        let parsedSession = parser.with { $0.sessionID }
        if result.cancelled || handle.wasKilled {
            throw AgentFailure.cancelled(text)
        }
        if result.exitCode != 0 && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = detail.isEmpty ? "\(participant.screenName) exited \(result.exitCode)." : detail
            throw AgentFailure.failed(Redactor.scrub(message))
        }
        let session = parsedSession ?? ((context.sessionID?.isEmpty == false) ? context.sessionID : freshID)
        let kept = participant == .codex ? (parsedSession ?? context.sessionID) : session
        if result.exitCode != 0 {
            let note = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let combined = note.isEmpty ? text : text + "\n" + note
            return AgentTurnOutcome(text: combined, sessionID: kept)
        }
        return AgentTurnOutcome(text: text, sessionID: kept)
    }

    private static func runGrok(
        context: AgentTurnContext,
        handle: TurnHandle,
        onText: @escaping @Sendable (String) -> Void
    ) async throws -> AgentTurnOutcome {
        guard let key = KeychainStore.load()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw AgentFailure.failed("Grok is offline because no xAI API key is saved in the Keychain.")
        }
        let session = URLSession(configuration: .ephemeral)
        handle.setKill { session.invalidateAndCancel() }
        do {
            let outcome = try await postGrok(
                prompt: context.prompt,
                previous: context.sessionID,
                model: context.grokModel,
                key: key,
                session: session,
                onText: onText
            )
            if handle.wasKilled {
                throw AgentFailure.cancelled(outcome.text)
            }
            return outcome
        } catch let failure as AgentFailure {
            if case .failed(let message) = failure,
               let previous = context.sessionID, !previous.isEmpty,
               message.localizedCaseInsensitiveContains("previous_response") {
                let outcome = try await postGrok(
                    prompt: context.prompt,
                    previous: nil,
                    model: context.grokModel,
                    key: key,
                    session: session,
                    onText: onText
                )
                if handle.wasKilled {
                    throw AgentFailure.cancelled(outcome.text)
                }
                return outcome
            }
            throw failure
        } catch {
            if handle.wasKilled {
                throw AgentFailure.cancelled("")
            }
            let message = (error as? URLError)?.localizedDescription ?? error.localizedDescription
            throw AgentFailure.failed(Redactor.scrub(message))
        }
    }

    private static func postGrok(
        prompt: String,
        previous: String?,
        model: String,
        key: String,
        session: URLSession,
        onText: @escaping @Sendable (String) -> Void
    ) async throws -> AgentTurnOutcome {
        var request = URLRequest(url: URL(string: "https://api.x.ai/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: CLICommands.grokBody(prompt: prompt, previousResponseID: previous, model: model))
        let (bytes, response) = try await session.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 {
            throw AgentFailure.failed("xAI rejected the API key (HTTP \(status)).")
        }
        var state = GrokParseState()
        if status >= 400 {
            var collected = ""
            for try await line in bytes.lines {
                collected += line
                if collected.count > 2_000 { break }
            }
            _ = GrokSSE.consume(collected, state: &state)
            throw AgentFailure.failed(Redactor.scrub(state.error ?? "xAI request failed (HTTP \(status))."))
        }
        for try await line in bytes.lines {
            if let text = GrokSSE.consume(line, state: &state) {
                onText(text)
            }
            if let error = state.error {
                throw AgentFailure.failed(Redactor.scrub(error))
            }
        }
        return AgentTurnOutcome(text: state.text, sessionID: state.responseID ?? previous)
    }
}

final class LineParser {
    private var claude = ClaudeStreamParser()
    private var codex = CodexStreamParser()
    private var cursor = CursorStreamParser()
    private let participant: ParticipantID

    init(participant: ParticipantID) {
        self.participant = participant
    }

    var text: String {
        switch participant {
        case .claudeCode: return claude.text
        case .codex: return codex.text
        default: return cursor.text
        }
    }

    var sessionID: String? {
        switch participant {
        case .claudeCode: return claude.sessionID
        case .codex: return codex.threadID
        default: return cursor.sessionID
        }
    }

    func consume(_ line: String) -> String? {
        switch participant {
        case .claudeCode: return claude.consume(line)
        case .codex: return codex.consume(line)
        default: return cursor.consume(line)
        }
    }
}
