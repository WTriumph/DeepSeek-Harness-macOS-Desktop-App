import Darwin
import Foundation

public enum HarnessProcessState: Equatable {
    case idle
    case starting
    case ready(URL)
    case stopping
    case stopped(Int32)
    case failed(String)
}

public struct HarnessRuntimeConfiguration {
    public let nodeExecutable: URL
    public let dshEntryPoint: URL
    public let workingDirectory: URL
    public let environment: [String: String]

    public init(
        nodeExecutable: URL,
        dshEntryPoint: URL,
        workingDirectory: URL,
        environment: [String: String]
    ) {
        self.nodeExecutable = nodeExecutable
        self.dshEntryPoint = dshEntryPoint
        self.workingDirectory = workingDirectory
        self.environment = environment
    }
}

public final class HarnessProcessController {
    public var onStateChange: ((HarnessProcessState) -> Void)?

    private let configuration: HarnessRuntimeConfiguration
    private let logger: LogFile
    private let lock = NSLock()
    private let ioQueue = DispatchQueue(label: "com.deepseek.harness.desktop.process-io")

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdoutLines = LineAccumulator()
    private var stderrLines = LineAccumulator()
    private var stderrTail = ""
    private var state: HarnessProcessState = .idle
    private var stopping = false
    private var generation = UUID()
    private var processGroupID: pid_t?

    public init(configuration: HarnessRuntimeConfiguration, logger: LogFile) {
        self.configuration = configuration
        self.logger = logger
    }

    public var currentState: HarnessProcessState {
        lock.withLock { state }
    }

    public var isRunning: Bool {
        lock.withLock { process?.isRunning == true }
    }

    public func start() throws {
        let fileManager = FileManager.default
        guard fileManager.isExecutableFile(atPath: configuration.nodeExecutable.path) else {
            throw HarnessProcessError.nodeMissing(configuration.nodeExecutable.path)
        }
        guard fileManager.fileExists(atPath: configuration.dshEntryPoint.path) else {
            throw HarnessProcessError.dshMissing(configuration.dshEntryPoint.path)
        }
        try fileManager.createDirectory(at: configuration.workingDirectory, withIntermediateDirectories: true)

        let canStart = lock.withLock { self.process?.isRunning != true }
        guard canStart else { throw HarnessProcessError.alreadyRunning }

        let newGeneration = UUID()
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = configuration.nodeExecutable
        process.arguments = [
            configuration.dshEntryPoint.path,
            "web",
            "--host", "127.0.0.1",
            "--port", "0",
        ]
        process.currentDirectoryURL = configuration.workingDirectory
        process.environment = configuration.environment
        process.standardOutput = stdout
        process.standardError = stderr

        lock.withLock {
            generation = newGeneration
            self.process = process
            stdoutPipe = stdout
            stderrPipe = stderr
            stdoutLines = LineAccumulator()
            stderrLines = LineAccumulator()
            stderrTail = ""
            stopping = false
            processGroupID = nil
            state = .starting
        }
        notify(.starting)
        logger.append("desktop: starting embedded dsh")

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            self?.ioQueue.async { self?.consume(data, stream: .stdout, generation: newGeneration) }
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            self?.ioQueue.async { self?.consume(data, stream: .stderr, generation: newGeneration) }
        }
        process.terminationHandler = { [weak self] terminated in
            self?.ioQueue.async { self?.handleTermination(terminated, generation: newGeneration) }
        }

        do {
            try process.run()
            establishProcessGroup(for: process)
            logger.append("desktop: dsh pid \(process.processIdentifier)")
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            lock.withLock {
                if generation == newGeneration {
                    self.process = nil
                    stdoutPipe = nil
                    stderrPipe = nil
                    state = .failed(error.localizedDescription)
                }
            }
            notify(.failed(error.localizedDescription))
            throw error
        }
    }

    public func restart() throws {
        stopAndWait(timeout: 6)
        try start()
    }

    public func stopAndWait(timeout: TimeInterval = 6) {
        let snapshot: (Process, pid_t?)? = lock.withLock {
            guard let process, process.isRunning else { return nil }
            stopping = true
            state = .stopping
            return (process, processGroupID)
        }
        guard let (process, groupID) = snapshot else { return }

        notify(.stopping)
        let pid = process.processIdentifier
        logger.append("desktop: SIGTERM -> dsh pid \(pid)")
        _ = Darwin.kill(pid, SIGTERM)

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            usleep(50_000)
        }

        if process.isRunning {
            logger.append("desktop: shutdown exceeded \(timeout)s; SIGKILL -> dsh pid \(pid)")
            _ = Darwin.kill(pid, SIGKILL)
            if let groupID, groupID == pid {
                _ = Darwin.kill(-groupID, SIGKILL)
            }
        }

        process.waitUntilExit()
        let handlerDeadline = Date().addingTimeInterval(1)
        while lock.withLock({ self.process === process }) && Date() < handlerDeadline {
            usleep(10_000)
        }
        ioQueue.sync {}
        clearPipeHandlers()
        logger.flush()
    }

    private enum Stream {
        case stdout
        case stderr
    }

    private func consume(_ data: Data, stream: Stream, generation: UUID) {
        guard self.generation == generation else { return }
        if data.isEmpty {
            let remaining: [String]
            switch stream {
            case .stdout: remaining = stdoutLines.flush()
            case .stderr: remaining = stderrLines.flush()
            }
            remaining.forEach { consumeLine($0, stream: stream, generation: generation) }
            return
        }

        let lines: [String]
        switch stream {
        case .stdout: lines = stdoutLines.append(data)
        case .stderr: lines = stderrLines.append(data)
        }
        lines.forEach { consumeLine($0, stream: stream, generation: generation) }
    }

    private func consumeLine(_ line: String, stream: Stream, generation: UUID) {
        guard self.generation == generation else { return }
        let label: String
        switch stream {
        case .stdout: label = "dsh:stdout"
        case .stderr: label = "dsh:stderr"
        }
        logger.append("\(label): \(line)")

        if stream == .stderr {
            lock.withLock {
                stderrTail.append(line)
                stderrTail.append("\n")
                if stderrTail.count > 16_384 {
                    stderrTail.removeFirst(stderrTail.count - 16_384)
                }
            }
            return
        }

        guard let url = HarnessURLParser.parseReadyURL(from: line) else { return }
        let shouldNotify = lock.withLock { () -> Bool in
            guard self.generation == generation, process?.isRunning == true, !stopping else { return false }
            if case .ready = state { return false }
            state = .ready(url)
            return true
        }
        if shouldNotify {
            logger.append("desktop: Harness ready at \(url.absoluteString)")
            notify(.ready(url))
        }
    }

    private func handleTermination(_ terminated: Process, generation: UUID) {
        consume(Data(), stream: .stdout, generation: generation)
        consume(Data(), stream: .stderr, generation: generation)
        clearPipeHandlers()

        let nextState: HarnessProcessState? = lock.withLock {
            guard self.generation == generation else { return nil }
            let code = terminated.terminationStatus
            let wasStopping = stopping
            process = nil
            stdoutPipe = nil
            stderrPipe = nil
            processGroupID = nil
            stopping = false
            if wasStopping {
                state = .stopped(code)
            } else {
                let detail = stderrTail.trimmingCharacters(in: .whitespacesAndNewlines)
                let reason = detail.isEmpty
                    ? "DeepSeek Harness exited unexpectedly (status \(code))."
                    : detail
                state = .failed(reason)
            }
            return state
        }
        if let nextState {
            logger.append("desktop: dsh terminated with status \(terminated.terminationStatus)")
            notify(nextState)
        }
    }

    private func establishProcessGroup(for process: Process) {
        let pid = process.processIdentifier
        let result = Darwin.setpgid(pid, pid)
        let group = Darwin.getpgid(pid)
        lock.withLock {
            processGroupID = (result == 0 || group == pid) ? pid : nil
        }
    }

    private func clearPipeHandlers() {
        lock.withLock {
            stdoutPipe?.fileHandleForReading.readabilityHandler = nil
            stderrPipe?.fileHandleForReading.readabilityHandler = nil
        }
    }

    private func notify(_ nextState: HarnessProcessState) {
        DispatchQueue.main.async { [weak self] in
            self?.onStateChange?(nextState)
        }
    }
}

public enum HarnessProcessError: LocalizedError, Equatable {
    case alreadyRunning
    case nodeMissing(String)
    case dshMissing(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "DeepSeek Harness is already running."
        case .nodeMissing(let path):
            return "Embedded Node.js runtime is missing or not executable: \(path)"
        case .dshMissing(let path):
            return "Embedded DeepSeek Harness entry point is missing: \(path)"
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
