import Foundation

public struct AppDataLocations: Equatable {
    public static let bundleIdentifier = "com.deepseek.harness.desktop"
    public static let applicationName = "DeepSeek Harness"

    public let home: URL
    public let library: URL
    public let applicationSupport: URL
    public let harnessHome: URL
    public let bootstrapWorkspace: URL
    public let caches: URL
    public let logs: URL
    public let preferences: URL
    public let savedApplicationState: URL
    public let webKit: URL
    public let httpStorages: URL
    public let cookies: URL
    public let legacyHarnessHome: URL
    public let sharedAgentsHome: URL

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        bundleIdentifier: String = AppDataLocations.bundleIdentifier
    ) {
        let standardizedHome = home.standardizedFileURL
        let library = standardizedHome.appendingPathComponent("Library", isDirectory: true)
        let applicationSupport = library
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(AppDataLocations.applicationName, isDirectory: true)

        self.home = standardizedHome
        self.library = library
        self.applicationSupport = applicationSupport
        self.harnessHome = applicationSupport.appendingPathComponent("Harness", isDirectory: true)
        self.bootstrapWorkspace = applicationSupport.appendingPathComponent("Bootstrap Workspace", isDirectory: true)
        self.caches = library
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
        self.logs = library
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(AppDataLocations.applicationName, isDirectory: true)
        self.preferences = library
            .appendingPathComponent("Preferences", isDirectory: true)
            .appendingPathComponent("\(bundleIdentifier).plist", isDirectory: false)
        self.savedApplicationState = library
            .appendingPathComponent("Saved Application State", isDirectory: true)
            .appendingPathComponent("\(bundleIdentifier).savedState", isDirectory: true)
        self.webKit = library
            .appendingPathComponent("WebKit", isDirectory: true)
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
        self.httpStorages = library
            .appendingPathComponent("HTTPStorages", isDirectory: true)
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
        self.cookies = library
            .appendingPathComponent("Cookies", isDirectory: true)
            .appendingPathComponent("\(bundleIdentifier).binarycookies", isDirectory: false)
        self.legacyHarnessHome = standardizedHome.appendingPathComponent(".dsh", isDirectory: true)
        self.sharedAgentsHome = standardizedHome.appendingPathComponent(".agents", isDirectory: true)
    }

    public var nodeCompileCache: URL {
        caches.appendingPathComponent("node-compile-cache", isDirectory: true)
    }

    public var desktopLog: URL {
        logs.appendingPathComponent("desktop.log", isDirectory: false)
    }

    public var ownedPaths: [URL] {
        [
            applicationSupport,
            caches,
            logs,
            preferences,
            savedApplicationState,
            webKit,
            httpStorages,
            cookies,
        ]
    }

    public func ensureRuntimeDirectories(fileManager: FileManager = .default) throws {
        for directory in [applicationSupport, harnessHome, bootstrapWorkspace, caches, nodeCompileCache, logs] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    public func validatedOwnedPaths() throws -> [URL] {
        try ownedPaths.map { try validateOwnedPath($0) }
    }

    public func validateOwnedPath(_ url: URL) throws -> URL {
        let candidate = url.standardizedFileURL
        let homePath = home.path.hasSuffix("/") ? home.path : home.path + "/"
        guard candidate.path.hasPrefix(homePath), candidate.path != home.path else {
            throw AppDataLocationError.unsafePath(candidate.path)
        }
        guard candidate != legacyHarnessHome, candidate != sharedAgentsHome else {
            throw AppDataLocationError.sharedPath(candidate.path)
        }
        guard ownedPaths.map(\.standardizedFileURL).contains(candidate) else {
            throw AppDataLocationError.unownedPath(candidate.path)
        }
        return candidate
    }
}

public enum AppDataLocationError: LocalizedError, Equatable {
    case unsafePath(String)
    case sharedPath(String)
    case unownedPath(String)

    public var errorDescription: String? {
        switch self {
        case .unsafePath(let path):
            return "Refusing unsafe application-data path: \(path)"
        case .sharedPath(let path):
            return "Refusing shared user-data path: \(path)"
        case .unownedPath(let path):
            return "Refusing path not owned by DeepSeek Harness Desktop: \(path)"
        }
    }
}
