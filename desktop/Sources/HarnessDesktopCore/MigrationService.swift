import Foundation

public struct MigrationManifestEntry: Hashable, Comparable {
    public enum Kind: String, Comparable {
        case directory
        case file
        case symbolicLink

        public static func < (lhs: Kind, rhs: Kind) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public let relativePath: String
    public let kind: Kind
    public let fileSize: Int64?
    public let symbolicLinkDestination: String?

    public static func < (lhs: MigrationManifestEntry, rhs: MigrationManifestEntry) -> Bool {
        if lhs.relativePath != rhs.relativePath { return lhs.relativePath < rhs.relativePath }
        return lhs.kind < rhs.kind
    }
}

public final class MigrationService {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func shouldOfferMigration(locations: AppDataLocations) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: locations.legacyHarnessHome.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return false
        }
        return isDirectoryEmptyOrMissing(locations.harnessHome)
    }

    public func importLegacyHome(locations: AppDataLocations) throws {
        let source = locations.legacyHarnessHome
        let destination = locations.harnessHome
        guard shouldOfferMigration(locations: locations) else {
            throw MigrationError.notEligible
        }

        try fileManager.createDirectory(at: locations.applicationSupport, withIntermediateDirectories: true)
        let temporary = locations.applicationSupport
            .appendingPathComponent(".Harness.import-\(UUID().uuidString)", isDirectory: true)

        do {
            try fileManager.copyItem(at: source, to: temporary)
            let sourceManifest = try manifest(for: source)
            let copiedManifest = try manifest(for: temporary)
            guard sourceManifest == copiedManifest else {
                let missing = Set(sourceManifest).subtracting(copiedManifest).sorted()
                let extra = Set(copiedManifest).subtracting(sourceManifest).sorted()
                throw MigrationError.verificationFailed("missing=\(missing), extra=\(extra)")
            }

            if fileManager.fileExists(atPath: destination.path) {
                guard isDirectoryEmptyOrMissing(destination) else {
                    throw MigrationError.destinationNotEmpty
                }
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: temporary, to: destination)
            try restrictCredentialPermissions(in: destination)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    public func manifest(for root: URL) throws -> [MigrationManifestEntry] {
        let enumerationRoot = root.standardizedFileURL
        let rootPath = comparablePath(enumerationRoot.path)
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(
            at: enumerationRoot,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in false }
        ) else {
            throw MigrationError.cannotEnumerate(root.path)
        }

        var entries: [MigrationManifestEntry] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            let itemPath = comparablePath(url.path)
            guard itemPath.hasPrefix(rootPath + "/") else {
                throw MigrationError.cannotEnumerate(root.path)
            }
            let relativePath = String(itemPath.dropFirst(rootPath.count + 1))
            let kind: MigrationManifestEntry.Kind
            let size: Int64?
            let linkDestination: String?

            if values.isSymbolicLink == true {
                kind = .symbolicLink
                size = nil
                linkDestination = try fileManager.destinationOfSymbolicLink(atPath: url.path)
            } else if values.isDirectory == true {
                kind = .directory
                size = nil
                linkDestination = nil
            } else if values.isRegularFile == true {
                kind = .file
                size = Int64(values.fileSize ?? 0)
                linkDestination = nil
            } else {
                throw MigrationError.unsupportedEntry(relativePath)
            }

            entries.append(.init(
                relativePath: relativePath,
                kind: kind,
                fileSize: size,
                symbolicLinkDestination: linkDestination
            ))
        }
        return entries.sorted()
    }

    private func isDirectoryEmptyOrMissing(_ directory: URL) -> Bool {
        guard fileManager.fileExists(atPath: directory.path) else { return true }
        guard let contents = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return false }
        return contents.isEmpty
    }

    private func restrictCredentialPermissions(in harnessHome: URL) throws {
        let credentials = harnessHome.appendingPathComponent(".credentials.yaml", isDirectory: false)
        guard fileManager.fileExists(atPath: credentials.path) else { return }
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: credentials.path)
    }

    private func comparablePath(_ path: String) -> String {
        path.hasPrefix("/private/var/") ? String(path.dropFirst("/private".count)) : path
    }
}

public enum MigrationError: LocalizedError, Equatable {
    case notEligible
    case destinationNotEmpty
    case verificationFailed(String)
    case cannotEnumerate(String)
    case unsupportedEntry(String)

    public var errorDescription: String? {
        switch self {
        case .notEligible:
            return "Legacy Harness data is unavailable or the desktop data directory is already in use."
        case .destinationNotEmpty:
            return "The desktop Harness data directory is not empty."
        case .verificationFailed(let detail):
            return "The copied Harness data did not match the source: \(detail)"
        case .cannotEnumerate(let path):
            return "Cannot enumerate Harness data at \(path)."
        case .unsupportedEntry(let path):
            return "Harness data contains an unsupported filesystem entry at \(path)."
        }
    }
}
