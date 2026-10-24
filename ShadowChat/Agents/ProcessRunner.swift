import Darwin
import Foundation

struct CommandResult: Equatable {
    var exitCode: Int32
    var stderr: String
    var cancelled: Bool
}

final class TurnHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var killImpl: () -> Void = {}
    private var killed = false

    var wasKilled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return killed
    }

    func setKill(_ body: @escaping () -> Void) {
        lock.lock()
        killImpl = body
        let already = killed
        lock.unlock()
        if already { body() }
    }

    func terminate() {
        lock.lock()
        killed = true
        let body = killImpl
        lock.unlock()
        body()
    }
}

struct UTF8LineBuffer {
    private var pending = Data()

    mutating func append(_ chunk: Data) -> [String] {
        guard !chunk.isEmpty else { return [] }
        pending.append(chunk)
        var lines: [String] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            var line = Data(pending.prefix(upTo: newline))
            pending.removeSubrange(..<pending.index(after: newline))
            if line.last == 0x0D { line.removeLast() }
            lines.append(String(decoding: line, as: UTF8.self))
        }
        return lines
    }

    mutating func finish() -> String? {
        guard !pending.isEmpty else { return nil }
        let text = String(decoding: pending, as: UTF8.self)
        pending.removeAll()
        return text
    }
}

enum ProcessTree {
    static func children(of pid: pid_t) -> [pid_t] {
        guard pid > 1 else { return [] }
        let needed = proc_listchildpids(pid, nil, 0)
        let slots = max(8, needed > 0 ? Int(needed) / MemoryLayout<pid_t>.size + 4 : 32)
        var buffer = [pid_t](repeating: 0, count: slots)
        let used = buffer.withUnsafeMutableBytes { raw in
            proc_listchildpids(pid, raw.baseAddress, Int32(raw.count))
        }
        guard used > 0 else { return [] }
        let count = min(buffer.count, Int(used) / MemoryLayout<pid_t>.size)
        return Array(buffer.prefix(count)).filter { $0 > 1 && $0 != pid }
    }
}

@_silgen_name("proc_listchildpids")
private func proc_listchildpids(_ ppid: Int32, _ buffer: UnsafeMutableRawPointer?, _ buffersize: Int32) -> Int32

final class LiveProcess: @unchecked Sendable {
    private let process = Process()
    private let outPipe = Pipe()
    private let errPipe = Pipe()
    private let lock = NSLock()
    private var lines = UTF8LineBuffer()
    private var stderrData = Data()
    private var killed = false
    private var processGroup: pid_t = 0

    func terminate() {
        lock.lock()
        killed = true
        let running = process.isRunning
        let pid = process.processIdentifier
        let group = processGroup
        lock.unlock()
        guard running, pid > 1 else { return }
        killNow(pid: pid, group: group)
        process.terminate()
    }

    private func killNow(pid: pid_t, group: pid_t, depth: Int = 0) {
        guard depth < 6, pid > 1, pid != getpid() else { return }
        if group > 1 {
            kill(-group, SIGTERM)
        }
        kill(pid, SIGTERM)
        for child in ProcessTree.children(of: pid) {
            killNow(pid: child, group: 0, depth: depth + 1)
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.6) {
            if group > 1 { kill(-group, SIGKILL) }
            if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
            for child in ProcessTree.children(of: pid) where child > 1 {
                kill(child, SIGKILL)
            }
        }
    }

    func run(_ invocation: CLIInvocation, onLine: @escaping @Sendable (String) -> Void) async -> CommandResult {
        let executable = URL(fileURLWithPath: invocation.executable)
        guard FileManager.default.isExecutableFile(atPath: invocation.executable) else {
            return CommandResult(exitCode: 127, stderr: "Executable is missing: \(invocation.executable)", cancelled: false)
        }
        process.executableURL = executable
        process.arguments = invocation.arguments
        process.currentDirectoryURL = URL(fileURLWithPath: invocation.cwd, isDirectory: true)
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        let outHandle = outPipe.fileHandleForReading
        let errHandle = errPipe.fileHandleForReading
        outHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else { return }
            self.lock.lock()
            let parsed = self.lines.append(data)
            self.lock.unlock()
            for line in parsed where !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onLine(line)
            }
        }
        errHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else { return }
            self.lock.lock()
            self.stderrData.append(data)
            if self.stderrData.count > 16_000 {
                self.stderrData.removeFirst(self.stderrData.count - 8_000)
            }
            self.lock.unlock()
        }

        return await withCheckedContinuation { continuation in
            process.terminationHandler = { [weak self] proc in
                outHandle.readabilityHandler = nil
                errHandle.readabilityHandler = nil
                let rest = outHandle.readDataToEndOfFile()
                let errRest = errHandle.readDataToEndOfFile()
                var extra: [String] = []
                var stderr = ""
                var killed = false
                if let self {
                    self.lock.lock()
                    if !rest.isEmpty {
                        extra.append(contentsOf: self.lines.append(rest))
                    }
                    if let tail = self.lines.finish() {
                        extra.append(tail)
                    }
                    self.stderrData.append(errRest)
                    stderr = String(decoding: self.stderrData, as: UTF8.self)
                    killed = self.killed
                    self.lock.unlock()
                }
                for line in extra where !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    onLine(line)
                }
                let clipped = stderr.count > 2_000 ? String(stderr.suffix(2_000)) : stderr
                continuation.resume(returning: CommandResult(exitCode: proc.terminationStatus, stderr: clipped, cancelled: killed))
            }
            do {
                try process.run()
                let pid = process.processIdentifier
                if setpgid(pid, pid) == 0 {
                    lock.lock()
                    processGroup = pid
                    lock.unlock()
                }
                lock.lock()
                let shouldKill = killed
                let group = processGroup
                lock.unlock()
                if shouldKill {
                    killNow(pid: pid, group: group)
                    process.terminate()
                }
            } catch {
                outHandle.readabilityHandler = nil
                errHandle.readabilityHandler = nil
                continuation.resume(returning: CommandResult(exitCode: 127, stderr: error.localizedDescription, cancelled: false))
            }
        }
    }
}
