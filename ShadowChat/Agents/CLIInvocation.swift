import Foundation

struct CLIInvocation: Equatable {
    var executable: String
    var arguments: [String]
    var cwd: String
}

enum CLIPaths {
    static let codex = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"
    static let cursorApp = "/Applications/Cursor.app/Contents/Resources/app/bin/cursor"
    static let git = "/usr/bin/git"
    static let cursorGrokModel = "cursor-grok-4.5-high"
    static let defaultGrokModel = "grok-4.7"

    static func resolveClaude() -> String {
        firstExecutable(
            [homeBinary("claude"), "/usr/local/bin/claude", "/opt/homebrew/bin/claude"]
            + pathExecutables("claude")
        ) ?? homeBinary("claude")
    }

    static func resolveCodex() -> String {
        firstExecutable(
            [
                codex,
                homePath(".codex/plugins/.plugin-appserver/codex-cli/bin/codex"),
                "/opt/homebrew/bin/codex",
                "/usr/local/bin/codex"
            ] + pathExecutables("codex")
        ) ?? codex
    }

    static func resolveCursor() -> (path: String, prefix: [String]) {
        let candidates = [homeBinary("cursor-agent"), homeBinary("agent")] + pathExecutables("cursor-agent")
        if let agent = firstExecutable(candidates) {
            return (agent, [])
        }
        if FileManager.default.isExecutableFile(atPath: cursorApp) {
            return (cursorApp, ["agent"])
        }
        return (homeBinary("cursor-agent"), [])
    }

    private static func homeBinary(_ name: String) -> String {
        homePath(".local/bin/\(name)")
    }

    private static func homePath(_ relative: String) -> String {
        relative.split(separator: "/").reduce(FileManager.default.homeDirectoryForCurrentUser) { url, part in
            url.appendingPathComponent(String(part))
        }.path
    }

    private static func pathExecutables(_ name: String) -> [String] {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        return path.split(separator: ":").filter { !$0.isEmpty }.map { "\($0)/\(name)" }
    }

    private static func firstExecutable(_ paths: [String]) -> String? {
        var seen = Set<String>()
        for path in paths where seen.insert(path).inserted {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }
}

enum CLICommands {
    static let rolePrompt = "You are one participant in ShadowChat, a group instant message. The other participants speak on their own turns. Speak only as yourself. Do not impersonate anyone else. Do not start a new round of turns. Be concise and conversational."

    static let bannedArguments: [String] = [
        "--dangerously-skip-permissions",
        "--allow-dangerously-skip-permissions",
        "--yolo",
        "--force",
        "--dangerously-bypass-approvals-and-sandbox",
        "--dangerously-bypass-hook-trust",
        "danger-full-access",
        "bypassPermissions"
    ]

    static func claude(prompt: String, cwd: String, writable: Bool, sessionID: String?, newSessionID: String) -> CLIInvocation {
        var args = [
            "-p",
            "--output-format", "stream-json",
            "--include-partial-messages",
            "--verbose",
            "--permission-mode", writable ? "acceptEdits" : "plan",
            "--permission-prompts", "none",
            "--append-system-prompt", rolePrompt
        ]
        if !writable {
            args.append("--restricted")
            args.append("--tools")
            args.append("Read,Grep,Glob")
        } else if !cwd.isEmpty {
            args.append("--add-dir")
            args.append(cwd)
        }
        if let sessionID, !sessionID.isEmpty {
            args.append("--resume")
            args.append(sessionID)
        } else {
            args.append("--session-id")
            args.append(newSessionID)
        }
        args.append(prompt)
        return CLIInvocation(executable: CLIPaths.resolveClaude(), arguments: args, cwd: cwd)
    }

    static func codex(prompt: String, cwd: String, writable: Bool, sessionID: String?) -> CLIInvocation {
        let sandbox = writable ? "workspace-write" : "read-only"
        var args = ["--sandbox", sandbox, "-C", cwd]
        if let sessionID, !sessionID.isEmpty {
            args.append(contentsOf: ["exec", "resume", sessionID, "--json", "--skip-git-repo-check", prompt])
        } else {
            args.append(contentsOf: ["exec", "--json", "--color", "never"])
            if !writable {
                args.append("--skip-git-repo-check")
            }
            args.append(prompt)
        }
        return CLIInvocation(executable: CLIPaths.resolveCodex(), arguments: args, cwd: cwd)
    }

    static func cursorGrok(prompt: String, cwd: String, writable: Bool, sessionID: String?, newSessionID: String) -> CLIInvocation {
        let resolved = CLIPaths.resolveCursor()
        var args = resolved.prefix
        _ = newSessionID
        args.append(contentsOf: [
            "-p",
            "--output-format", "stream-json",
            "--stream-partial-output",
            "--sandbox", "enabled",
            "--trust",
            "--model", CLIPaths.cursorGrokModel,
            "--workspace", cwd
        ])
        if !writable {
            args.append(contentsOf: ["--mode", "plan"])
        }
        if let sessionID, !sessionID.isEmpty {
            args.append("--resume")
            args.append(sessionID)
        }
        args.append(prompt)
        return CLIInvocation(executable: resolved.path, arguments: args, cwd: cwd)
    }

    static func grokBody(prompt: String, previousResponseID: String?, model: String = CLIPaths.defaultGrokModel) -> [String: Any] {
        var body: [String: Any] = [
            "model": model.isEmpty ? CLIPaths.defaultGrokModel : model,
            "stream": true,
            "store": true,
            "input": prompt
        ]
        if let previousResponseID, !previousResponseID.isEmpty {
            body["previous_response_id"] = previousResponseID
        }
        return body
    }

    static func containsBannedFlag(_ arguments: [String]) -> String? {
        for (index, argument) in arguments.enumerated() {
            if bannedArguments.contains(argument) { return argument }
            let lowered = argument.lowercased()
            if lowered.contains("dangerously-skip-permissions") { return argument }
            if lowered.contains("dangerously-bypass") { return argument }
            if lowered.contains("bypasspermissions") { return argument }
            if argument.contains("danger-full-access") { return argument }
            if argument == "-a" || argument == "--ask-for-approval" {
                let next = index + 1 < arguments.count ? arguments[index + 1] : ""
                if next == "never" { return "\(argument) never" }
            }
        }
        return nil
    }
}

enum PromptText {
    static func make(
        speaker: String,
        roomName: String,
        history: String,
        allowFileChanges: Bool,
        worktreePath: String?,
        projectPath: String?
    ) -> String {
        let access: String
        if allowFileChanges, let worktreePath, !worktreePath.isEmpty {
            access = "File edits are allowed only inside this git worktree: \(worktreePath). Do not change files outside it."
        } else if let projectPath, !projectPath.isEmpty {
            access = "File edits are not allowed. You may read \(projectPath) but you must not modify files."
        } else {
            access = "File edits are not allowed. Do not create, modify, or delete files."
        }
        let apiNote = speaker == ParticipantID.grok.screenName
            ? " You are reached through the xAI API and have no local filesystem. Do not claim that you edited files."
            : ""
        return """
        \(CLICommands.rolePrompt)
        You are \(speaker) in the ShadowChat room "\(roomName)".\(apiNote)
        \(access)

        \(history)
        """
    }
}

enum PermissionGate {
    static func directory(
        allowFileChanges: Bool,
        projectPath: String?,
        worktreePath: String?,
        worktreeExists: Bool,
        scratch: String
    ) -> (cwd: String, writable: Bool) {
        if allowFileChanges, let worktreePath, worktreeExists {
            return (worktreePath, true)
        }
        if let projectPath, !projectPath.isEmpty {
            return (projectPath, false)
        }
        return (scratch, false)
    }
}

enum Redactor {
    static func scrub(_ text: String) -> String {
        var output = ""
        var index = text.startIndex
        let markers = ["Bearer ", "sk-", "xai-"]
        while index < text.endIndex {
            let marker = markers.first { text[index...].hasPrefix($0) }
            if let marker {
                output += marker
                index = text.index(index, offsetBy: marker.count)
                var token = ""
                while index < text.endIndex, isToken(text[index]) {
                    token.append(text[index])
                    index = text.index(after: index)
                }
                output += token.count >= 8 ? "[redacted]" : token
            } else {
                output.append(text[index])
                index = text.index(after: index)
            }
        }
        return output
    }

    private static func isToken(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "-" || character == "_"
    }
}
