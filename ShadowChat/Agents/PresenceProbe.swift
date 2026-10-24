import Foundation

enum PresenceProbe {
    static func probe() -> [ParticipantID: Presence] {
        let claudePath = CLIPaths.resolveClaude()
        let claudeInstalled = FileManager.default.isExecutableFile(atPath: claudePath)
        let claudeText = claudeInstalled ? capture(claudePath, ["auth", "status"]).text : ""
        let codexPath = CLIPaths.resolveCodex()
        let codexInstalled = FileManager.default.isExecutableFile(atPath: codexPath)
        let codexText = codexInstalled ? capture(codexPath, ["login", "status"]).text : ""
        let cursor = CLIPaths.resolveCursor()
        let cursorInstalled = FileManager.default.isExecutableFile(atPath: cursor.path)
        let cursorArgs = cursor.prefix + ["status"]
        let cursorText = cursorInstalled ? capture(cursor.path, cursorArgs).text : ""
        return [
            .claudeCode: claude(installed: claudeInstalled, statusText: claudeText),
            .codex: codex(installed: codexInstalled, statusText: codexText),
            .grok: grok(hasKey: KeychainStore.hasKey),
            .cursorGrok: cursorGrok(installed: cursorInstalled, statusText: cursorText)
        ]
    }

    static func claude(installed: Bool, statusText: String) -> Presence {
        guard installed else {
            return Presence(online: false, reason: "Claude Code CLI is not installed. Look for the claude executable on PATH or at ~/.local/bin/claude.")
        }
        if loggedIn(statusText) {
            return Presence(online: true, reason: "Online")
        }
        return Presence(online: false, reason: "Claude Code is not signed in (claude auth status).")
    }

    static func codex(installed: Bool, statusText: String) -> Presence {
        guard installed else {
            return Presence(online: false, reason: "Codex CLI is not installed at \(CLIPaths.codex).")
        }
        let lowered = statusText.lowercased()
        if lowered.contains("logged in"), !lowered.contains("not logged in") {
            return Presence(online: true, reason: "Online")
        }
        return Presence(online: false, reason: "Codex CLI is not signed in (codex login status).")
    }

    static func grok(hasKey: Bool) -> Presence {
        if hasKey {
            return Presence(online: true, reason: "Online")
        }
        return Presence(online: false, reason: "No xAI API key in Keychain. Use Setup to save one.")
    }

    static func cursorGrok(installed: Bool, statusText: String) -> Presence {
        guard installed else {
            return Presence(
                online: false,
                reason: "Cursor Agent CLI is not installed. Antigravity.app and Grok Bot.app are GUI apps and have no chat CLI."
            )
        }
        if statusText.localizedCaseInsensitiveContains("Not logged in") || statusText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Presence(
                online: false,
                reason: "Cursor Agent is not signed in (cursor-agent status). Antigravity.app and Grok Bot.app have no non-interactive chat CLI."
            )
        }
        return Presence(online: true, reason: "Online via cursor-agent")
    }

    static func loggedIn(_ statusText: String) -> Bool {
        guard let data = statusText.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = obj["loggedIn"] as? Bool else {
            return statusText.contains("\"loggedIn\": true") || statusText.contains("\"loggedIn\":true")
        }
        return value
    }

    static func capture(_ path: String, _ arguments: [String]) -> (code: Int32, text: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
        } catch {
            return (127, "")
        }
        let deadline = Date().addingTimeInterval(8)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            return (124, "")
        }
        let stdout = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (process.terminationStatus, stdout + stderr)
    }
}
