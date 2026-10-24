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

final class LiveProcess: @unchecked Sendable {
    private let process = Process()
    private let outPipe = Pipe()
    private let errPipe = Pipe()
    private let lock = NSLock()
    private var buffer = ""
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
        guard running, pid > 0 else { return }
        if group > 0 {
            kill(-group, SIGTERM)
        }
        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.6) {
            if group > 0 {
                kill(-group, SIGKILL)
            }
            if self.process.isRunning {
                kill(pid, SIGKILL)
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
            self.buffer.append(String(decoding: data, as: UTF8.self))
            var lines: [String] = []
            while let range = self.buffer.range(of: "\n") {
                let line = String(self.buffer[..<range.lowerBound])
                self.buffer.removeSubrange(..<range.upperBound)
                lines.append(line)
            }
            self.lock.unlock()
            for line in lines {
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
                var leftover = ""
                var stderr = ""
                var killed = false
                if let self {
                    self.lock.lock()
                    if !rest.isEmpty {
                        self.buffer.append(String(decoding: rest, as: UTF8.self))
                    }
                    self.stderrData.append(errRest)
                    leftover = self.buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.buffer = ""
                    stderr = String(decoding: self.stderrData, as: UTF8.self)
                    killed = self.killed
                    self.lock.unlock()
                }
                if !leftover.isEmpty {
                    onLine(leftover)
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
            } catch {
                outHandle.readabilityHandler = nil
                errHandle.readabilityHandler = nil
                continuation.resume(returning: CommandResult(exitCode: 127, stderr: error.localizedDescription, cancelled: false))
            }
        }
    }
}
