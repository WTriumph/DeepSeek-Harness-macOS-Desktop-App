import Darwin
import Foundation
import HarnessDesktopCore

struct Arguments {
    let waitPID: pid_t
    let appBundle: URL
    let home: URL

    init(_ values: [String]) throws {
        func value(after flag: String) -> String? {
            guard let index = values.firstIndex(of: flag), values.indices.contains(index + 1) else { return nil }
            return values[index + 1]
        }
        guard let pidText = value(after: "--wait-pid"), let pid = pid_t(pidText), pid > 1 else {
            throw UninstallerError.invalidArguments
        }
        guard let bundlePath = value(after: "--bundle"), let homePath = value(after: "--home") else {
            throw UninstallerError.invalidArguments
        }
        waitPID = pid
        appBundle = URL(fileURLWithPath: bundlePath, isDirectory: true).standardizedFileURL
        home = URL(fileURLWithPath: homePath, isDirectory: true).standardizedFileURL
    }
}

enum UninstallerError: LocalizedError {
    case invalidArguments
    case unsafeHome(String)
    case unsafeBundle(String)
    case parentStillRunning(pid_t)

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "Usage: DeepSeekHarnessUninstaller --wait-pid <pid> --bundle <app> --home <home>"
        case .unsafeHome(let path):
            return "Refusing unexpected home directory: \(path)"
        case .unsafeBundle(let path):
            return "Refusing unsafe application bundle: \(path)"
        case .parentStillRunning(let pid):
            return "DeepSeek Harness process \(pid) did not exit."
        }
    }
}

func waitForExit(pid: pid_t, timeout: TimeInterval = 30) throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if Darwin.kill(pid, 0) != 0 && errno == ESRCH { return }
        usleep(100_000)
    }
    throw UninstallerError.parentStillRunning(pid)
}

func validate(_ arguments: Arguments) throws {
    let actualHome = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
    guard arguments.home == actualHome else {
        throw UninstallerError.unsafeHome(arguments.home.path)
    }
    let bundle = arguments.appBundle
    guard bundle.pathExtension.lowercased() == "app",
          bundle.path != "/",
          bundle.path != arguments.home.path,
          FileManager.default.fileExists(atPath: bundle.path)
    else {
        throw UninstallerError.unsafeBundle(bundle.path)
    }
}

func trashApplication(_ bundle: URL, home: URL) throws {
    do {
        try FileManager.default.trashItem(at: bundle, resultingItemURL: nil)
    } catch {
        let trash = home.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let destination = trash.appendingPathComponent(
            "DeepSeek Harness \(UUID().uuidString).app",
            isDirectory: true
        )
        try FileManager.default.moveItem(at: bundle, to: destination)
    }
}

func removeTemporaryHelper() {
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    let parent = executable.deletingLastPathComponent()
    guard parent.path.hasPrefix(FileManager.default.temporaryDirectory.path),
          parent.lastPathComponent.hasPrefix("com.deepseek.harness.uninstaller-")
    else {
        return
    }
    try? FileManager.default.removeItem(at: parent)
}

do {
    let arguments = try Arguments(Array(CommandLine.arguments.dropFirst()))
    try validate(arguments)
    try waitForExit(pid: arguments.waitPID)
    let plan = UninstallPlan(locations: AppDataLocations(home: arguments.home))
    try plan.removeOwnedData()
    try trashApplication(arguments.appBundle, home: arguments.home)
    removeTemporaryHelper()
    exit(EXIT_SUCCESS)
} catch {
    fputs("DeepSeek Harness uninstall failed: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
