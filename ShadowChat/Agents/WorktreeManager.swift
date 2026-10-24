import Foundation

enum WorktreeError: LocalizedError {
    case notARepository(String)
    case git(String)

    var errorDescription: String? {
        switch self {
        case .notARepository(let path):
            return "\(path) is not a Git repository, so ShadowChat will not make a worktree."
        case .git(let message):
            return message
        }
    }
}

enum WorktreeManager {
    static func applicationSupport() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShadowChat", isDirectory: true)
    }

    static func worktreeRoot(_ override: URL? = nil) -> URL {
        (override ?? applicationSupport()).appendingPathComponent("worktrees", isDirectory: true)
    }

    static func worktreeURL(roomID: String, root: URL? = nil) -> URL {
        worktreeRoot(root).appendingPathComponent(safeRoomID(roomID), isDirectory: true)
    }

    static func scratchDirectory() -> String {
        let url = applicationSupport().appendingPathComponent("scratch", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path
    }

    static func safeRoomID(_ id: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-")
        let filtered = String(id.unicodeScalars.filter { allowed.contains($0) })
        return filtered.isEmpty ? "room" : filtered
    }

    static func isGitRepo(_ path: String) -> Bool {
        let result = runGit(revParseArguments(path))
        return result.status == 0
    }

    static func revParseArguments(_ path: String) -> [String] {
        ["-C", path, "rev-parse", "--is-inside-work-tree"]
    }

    static func addArguments(repo: String, destination: String) -> [String] {
        ["-C", repo, "worktree", "add", "--detach", destination, "HEAD"]
    }

    static func removeArguments(repo: String, destination: String) -> [String] {
        ["-C", repo, "worktree", "remove", destination]
    }

    static func ensureWorktree(repo: String, roomID: String, root: URL? = nil) throws -> String {
        guard isGitRepo(repo) else { throw WorktreeError.notARepository(repo) }
        let dest = worktreeURL(roomID: roomID, root: root)
        if FileManager.default.fileExists(atPath: dest.path), isGitRepo(dest.path) {
            return dest.path
        }
        try FileManager.default.createDirectory(at: worktreeRoot(root), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        let result = runGit(addArguments(repo: repo, destination: dest.path))
        guard result.status == 0 else {
            let detail = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw WorktreeError.git(detail.isEmpty ? "git worktree add failed." : detail)
        }
        return dest.path
    }

    @discardableResult
    static func runGit(_ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CLIPaths.git)
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
        } catch {
            return (127, error.localizedDescription)
        }
        process.waitUntilExit()
        let stdout = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (process.terminationStatus, stdout + stderr)
    }
}
