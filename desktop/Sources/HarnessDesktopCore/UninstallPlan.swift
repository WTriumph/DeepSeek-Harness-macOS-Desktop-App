import Foundation

public struct UninstallPlan {
    public let locations: AppDataLocations

    public init(locations: AppDataLocations) {
        self.locations = locations
    }

    public func removalPaths() throws -> [URL] {
        try locations.validatedOwnedPaths()
    }

    @discardableResult
    public func removeOwnedData(
        dryRun: Bool = false,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        let paths = try removalPaths()
        guard !dryRun else { return paths }

        UserDefaults.standard.removePersistentDomain(forName: AppDataLocations.bundleIdentifier)
        for path in paths where fileManager.fileExists(atPath: path.path) {
            try fileManager.removeItem(at: path)
        }
        return paths
    }
}

public enum BackupService {
    public static func createHarnessBackup(source: URL, destination: URL) throws {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw BackupError.sourceMissing(source.path)
        }
        let process = Process()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [
            "-c", "-k", "--sequesterRsrc", "--keepParent",
            source.path,
            destination.path,
        ]
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw BackupError.failed(detail.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

public enum BackupError: LocalizedError, Equatable {
    case sourceMissing(String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .sourceMissing(let path):
            return "Harness data does not exist at \(path)."
        case .failed(let detail):
            return detail.isEmpty ? "Harness data backup failed." : "Harness data backup failed: \(detail)"
        }
    }
}
