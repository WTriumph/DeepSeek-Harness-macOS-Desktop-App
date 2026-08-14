import Foundation
import HarnessDesktopCore
import Testing

@Suite("dsh process lifecycle", .serialized)
struct HarnessProcessControllerTests {
    @Test func readySignalAndGracefulStop() throws {
        let fixture = try ProcessFixture()
        defer { fixture.remove() }
        let script = try fixture.writeScript("""
        trap 'exit 0' TERM
        echo 'dsh web: http://127.0.0.1:43123'
        while true; do sleep 1; done
        """)
        let semaphore = DispatchSemaphore(value: 0)
        let controller = fixture.makeController(script: script)
        controller.onStateChange = { state in
            if state == .ready(URL(string: "http://127.0.0.1:43123")!) { semaphore.signal() }
        }
        try controller.start()
        #expect(semaphore.wait(timeout: .now() + 3) == .success)
        controller.stopAndWait(timeout: 2)
        #expect(!controller.isRunning)
    }

    @Test func escalatesToKillAfterDeadline() throws {
        let fixture = try ProcessFixture()
        defer { fixture.remove() }
        let script = try fixture.writeScript("""
        trap '' TERM
        echo 'dsh web: http://127.0.0.1:43124'
        while true; do sleep 1; done
        """)
        let semaphore = DispatchSemaphore(value: 0)
        let controller = fixture.makeController(script: script)
        controller.onStateChange = { state in
            if state == .ready(URL(string: "http://127.0.0.1:43124")!) { semaphore.signal() }
        }
        try controller.start()
        #expect(semaphore.wait(timeout: .now() + 3) == .success)
        let started = Date()
        controller.stopAndWait(timeout: 0.2)
        #expect(Date().timeIntervalSince(started) < 2)
        #expect(!controller.isRunning)
    }

    @Test func stopIsIdempotent() throws {
        let fixture = try ProcessFixture()
        defer { fixture.remove() }
        let script = try fixture.writeScript("""
        trap 'exit 0' TERM
        echo 'dsh web: http://127.0.0.1:43125'
        while true; do sleep 1; done
        """)
        let semaphore = DispatchSemaphore(value: 0)
        let controller = fixture.makeController(script: script)
        controller.onStateChange = { state in
            if state == .ready(URL(string: "http://127.0.0.1:43125")!) { semaphore.signal() }
        }
        try controller.start()
        #expect(semaphore.wait(timeout: .now() + 3) == .success)
        controller.stopAndWait(timeout: 1)
        controller.stopAndWait(timeout: 1)
        #expect(!controller.isRunning)
    }
}

private struct ProcessFixture {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("process-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func makeController(script: URL) -> HarnessProcessController {
        let log = LogFile(fileURL: root.appendingPathComponent("desktop.log"))
        let configuration = HarnessRuntimeConfiguration(
            nodeExecutable: URL(fileURLWithPath: "/bin/sh"),
            dshEntryPoint: script,
            workingDirectory: root,
            environment: ProcessInfo.processInfo.environment
        )
        return HarnessProcessController(configuration: configuration, logger: log)
    }

    func writeScript(_ body: String) throws -> URL {
        let script = root.appendingPathComponent("fake-dsh-\(UUID().uuidString).sh")
        try Data(body.utf8).write(to: script)
        return script
    }
}
