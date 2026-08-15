import Foundation

public enum UninstallMode: String, CaseIterable, Sendable {
    case applicationOnly = "app-only"
    case standard
    case complete
}

public struct UninstallPlan {
    public let locations: AppDataLocations
    public let mode: UninstallMode
    public let workspacePaths: [URL]

    public init(
        locations: AppDataLocations,
        mode: UninstallMode = .standard,
        workspacePaths: [URL] = []
    ) {
        self.locations = locations
        self.mode = mode
        self.workspacePaths = workspacePaths
    }

    public func removalPaths() throws -> [URL] {
        switch mode {
        case .applicationOnly:
            return []
        case .standard:
            return try locations.validatedOwnedPaths()
        case .complete:
            var paths = try locations.validatedOwnedPaths()
            paths.append(locations.legacyHarnessHome.standardizedFileURL)
            paths.append(locations.sharedAgentsHome.standardizedFileURL)
            paths.append(contentsOf: try workspacePaths.map(validateWorkspacePath))
            return collapseNestedPaths(paths)
        }
    }

    @discardableResult
    public func removeData(
        dryRun: Bool = false,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        let paths = try removalPaths()
        guard !dryRun else { return paths }

        if mode != .applicationOnly,
           locations.home == fileManager.homeDirectoryForCurrentUser.standardizedFileURL
        {
            UserDefaults.standard.removePersistentDomain(forName: AppDataLocations.bundleIdentifier)
        }
        for path in paths where fileManager.fileExists(atPath: path.path) || isSymbolicLink(path, fileManager: fileManager) {
            try fileManager.removeItem(at: path)
        }
        return paths
    }

    @available(*, deprecated, renamed: "removeData(dryRun:fileManager:)")
    @discardableResult
    public func removeOwnedData(
        dryRun: Bool = false,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        try removeData(dryRun: dryRun, fileManager: fileManager)
    }

    private func validateWorkspacePath(_ url: URL) throws -> URL {
        let candidate = url.standardizedFileURL
        let path = candidate.path
        let homePath = locations.home.path
        let homePrefix = homePath.hasSuffix("/") ? homePath : homePath + "/"

        guard candidate.isFileURL, path.hasPrefix("/"), path != "/", path != homePath else {
            throw UninstallError.unsafeWorkspace(path)
        }
        guard !homePath.hasPrefix(path.hasSuffix("/") ? path : path + "/") else {
            throw UninstallError.unsafeWorkspace(path)
        }
        guard candidate != locations.legacyHarnessHome,
              candidate != locations.sharedAgentsHome,
              !locations.ownedPaths.contains(where: { candidate == $0 || isDescendant(candidate, of: $0) })
        else {
            throw UninstallError.unsafeWorkspace(path)
        }

        if path.hasPrefix(homePrefix) {
            let relative = String(path.dropFirst(homePrefix.count))
            let firstComponent = relative.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
            let protectedHomeComponents: Set<String> = ["Library", "Applications", ".Trash", ".dsh", ".agents"]
            guard !protectedHomeComponents.contains(firstComponent) else {
                throw UninstallError.unsafeWorkspace(path)
            }
            return candidate
        }

        let components = candidate.pathComponents
        guard components.count >= 4, components[1] == "Volumes" else {
            throw UninstallError.unsafeWorkspace(path)
        }
        return candidate
    }

    private func collapseNestedPaths(_ paths: [URL]) -> [URL] {
        let sorted = Array(Set(paths.map(\.standardizedFileURL))).sorted {
            $0.pathComponents.count < $1.pathComponents.count
        }
        return sorted.reduce(into: []) { result, candidate in
            guard !result.contains(where: { candidate == $0 || isDescendant(candidate, of: $0) }) else { return }
            result.append(candidate)
        }
    }

    private func isDescendant(_ candidate: URL, of parent: URL) -> Bool {
        let prefix = parent.path.hasSuffix("/") ? parent.path : parent.path + "/"
        return candidate.path.hasPrefix(prefix)
    }

    private func isSymbolicLink(_ url: URL, fileManager: FileManager) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]) else { return false }
        return values.isSymbolicLink == true
    }
}

public enum WorkspaceDiscovery {
    public static func discover(locations: AppDataLocations, fileManager: FileManager = .default) throws -> [URL] {
        let homes = [locations.harnessHome, locations.legacyHarnessHome]
        var paths = Set<URL>()

        for home in homes {
            let storage = home.appendingPathComponent("storages", isDirectory: true)
            for name in ["workspace.json", "session_projcache.json"] {
                let file = storage.appendingPathComponent(name, isDirectory: false)
                guard fileManager.fileExists(atPath: file.path) else { continue }
                let data = try Data(contentsOf: file)
                do {
                    paths.formUnion(try pathsFromStorageData(data))
                } catch {
                    throw UninstallError.invalidWorkspaceStorage(file.path)
                }
            }
        }

        return paths.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    public static func pathsFromStorageData(_ data: Data) throws -> Set<URL> {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tables = root["tables"] as? [String: Any]
        else {
            throw UninstallError.invalidWorkspaceStorage("JSON")
        }

        var result = Set<URL>()
        if let workspaces = tables["workspaces"] as? [String: Any] {
            for value in workspaces.values {
                guard let record = value as? [String: Any], let path = record["path"] as? String else { continue }
                appendAbsoluteDirectory(path, to: &result)
            }
        }
        if let sessions = tables["sessions"] as? [String: Any] {
            for value in sessions.values {
                guard let record = value as? [String: Any],
                      let identity = record["identity"] as? [String: Any],
                      let cwd = identity["cwd"] as? String
                else {
                    continue
                }
                appendAbsoluteDirectory(cwd, to: &result)
            }
        }
        return result
    }

    private static func appendAbsoluteDirectory(_ path: String, to result: inout Set<URL>) {
        guard path.hasPrefix("/"), path != "/" else { return }
        result.insert(URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL)
    }
}

public struct BackupItem: Equatable, Sendable {
    public let source: URL
    public let archivePath: String

    public init(source: URL, archivePath: String) {
        self.source = source
        self.archivePath = archivePath
    }
}

public enum BackupService {
    public static func createBackup(
        items: [BackupItem],
        destination: URL,
        removalPaths: [URL],
        fileManager: FileManager = .default
    ) throws {
        let destination = destination.standardizedFileURL
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw BackupError.destinationExists(destination.path)
        }
        for removalPath in removalPaths {
            let prefix = removalPath.path.hasSuffix("/") ? removalPath.path : removalPath.path + "/"
            guard destination != removalPath, !destination.path.hasPrefix(prefix) else {
                throw BackupError.unsafeDestination(destination.path)
            }
        }

        let temporaryParent = fileManager.temporaryDirectory
            .appendingPathComponent("com.deepseek.harness.backup-\(UUID().uuidString)", isDirectory: true)
        let backupRoot = temporaryParent.appendingPathComponent("DeepSeek Harness Backup", isDirectory: true)
        try fileManager.createDirectory(at: backupRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryParent) }

        var manifest: [String] = [
            "DeepSeek Harness backup / DeepSeek Harness 备份",
            "Created: \(ISO8601DateFormatter().string(from: Date()))",
            "",
        ]
        for item in items where fileManager.fileExists(atPath: item.source.path) {
            let relative = try validatedArchivePath(item.archivePath)
            let target = backupRoot.appendingPathComponent(relative, isDirectory: true)
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.copyItem(at: item.source, to: target)
            manifest.append("\(relative) <- \(item.source.path)")
        }
        try Data(manifest.joined(separator: "\n").utf8)
            .write(to: backupRoot.appendingPathComponent("BACKUP-MANIFEST.txt", isDirectory: false))

        let process = Process()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [
            "-c", "-k", "--sequesterRsrc", "--keepParent",
            backupRoot.path,
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

    public static func createHarnessBackup(source: URL, destination: URL) throws {
        try createBackup(
            items: [BackupItem(source: source, archivePath: "Desktop/Harness")],
            destination: destination,
            removalPaths: []
        )
    }

    private static func validatedArchivePath(_ value: String) throws -> String {
        let components = NSString(string: value).pathComponents
        guard !value.hasPrefix("/"), !components.contains(".."), !components.isEmpty else {
            throw BackupError.unsafeArchivePath(value)
        }
        return components.joined(separator: "/")
    }
}

public enum UninstallError: LocalizedError, Equatable {
    case unsafeWorkspace(String)
    case invalidWorkspaceStorage(String)

    public var errorDescription: String? {
        switch self {
        case .unsafeWorkspace(let path):
            return "拒绝删除不安全的工作区路径 / Refusing unsafe workspace path: \(path)"
        case .invalidWorkspaceStorage(let path):
            return "无法安全读取工作区记录 / Cannot safely read workspace storage: \(path)"
        }
    }
}

public enum BackupError: LocalizedError, Equatable {
    case sourceMissing(String)
    case destinationExists(String)
    case unsafeDestination(String)
    case unsafeArchivePath(String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .sourceMissing(let path):
            return "Harness data does not exist at \(path)."
        case .destinationExists(let path):
            return "备份文件已存在 / Backup destination already exists: \(path)"
        case .unsafeDestination(let path):
            return "备份不能保存在即将删除的位置 / Backup cannot be stored inside a removal path: \(path)"
        case .unsafeArchivePath(let path):
            return "不安全的备份归档路径 / Unsafe backup archive path: \(path)"
        case .failed(let detail):
            return detail.isEmpty ? "Harness data backup failed." : "Harness data backup failed: \(detail)"
        }
    }
}
