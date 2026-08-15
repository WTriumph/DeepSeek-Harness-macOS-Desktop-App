import Foundation
import HarnessDesktopCore
import Testing

@Suite("legacy ~/.dsh migration", .serialized)
struct MigrationServiceTests {
    @Test func importsVerifiedCopyWithoutChangingLegacyHome() throws {
        let root = try temporaryDirectory(prefix: "migration-tests")
        defer { try? FileManager.default.removeItem(at: root) }
        let locations = AppDataLocations(home: root)
        try FileManager.default.createDirectory(at: locations.legacyHarnessHome, withIntermediateDirectories: true)
        try Data("secret".utf8).write(to: locations.legacyHarnessHome.appendingPathComponent(".credentials.yaml"))
        try FileManager.default.createDirectory(
            at: locations.legacyHarnessHome.appendingPathComponent("sessions/session-a"),
            withIntermediateDirectories: true
        )
        try Data("event".utf8).write(
            to: locations.legacyHarnessHome.appendingPathComponent("sessions/session-a/session.jsonl")
        )
        try FileManager.default.createSymbolicLink(
            atPath: locations.legacyHarnessHome.appendingPathComponent("linked-skill").path,
            withDestinationPath: "/tmp/external-skill"
        )

        let service = MigrationService()
        #expect(service.shouldOfferMigration(locations: locations))
        let summary = try service.importLegacyHome(locations: locations)

        #expect(summary.fileCount == 2)
        #expect(summary.directoryCount == 2)
        #expect(summary.symbolicLinkCount == 1)
        #expect(summary.entryCount == 5)
        #expect(summary.containsUserData)

        #expect(
            try String(contentsOf: locations.harnessHome.appendingPathComponent(".credentials.yaml"))
                == "secret"
        )
        #expect(
            try String(contentsOf: locations.legacyHarnessHome.appendingPathComponent(".credentials.yaml"))
                == "secret"
        )
        #expect(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: locations.harnessHome.appendingPathComponent("linked-skill").path
            ) == "/tmp/external-skill"
        )
        let attributes = try FileManager.default.attributesOfItem(
            atPath: locations.harnessHome.appendingPathComponent(".credentials.yaml").path
        )
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test func refusesToOverwriteDesktopData() throws {
        let root = try temporaryDirectory(prefix: "migration-refusal")
        defer { try? FileManager.default.removeItem(at: root) }
        let locations = AppDataLocations(home: root)
        try FileManager.default.createDirectory(at: locations.legacyHarnessHome, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: locations.harnessHome, withIntermediateDirectories: true)
        try Data("existing".utf8).write(to: locations.harnessHome.appendingPathComponent("settings.yaml"))
        #expect(!MigrationService().shouldOfferMigration(locations: locations))
        #expect(throws: (any Error).self) {
            try MigrationService().importLegacyHome(locations: locations)
        }
    }

    @Test func reportsWhenLegacyHomeContainsOnlyAnonymousMetadata() throws {
        let root = try temporaryDirectory(prefix: "migration-metadata-only")
        defer { try? FileManager.default.removeItem(at: root) }
        let locations = AppDataLocations(home: root)
        try FileManager.default.createDirectory(at: locations.legacyHarnessHome, withIntermediateDirectories: true)
        try Data("anonymous".utf8).write(
            to: locations.legacyHarnessHome.appendingPathComponent(".anonymous-user-id")
        )

        let service = MigrationService()
        let inspected = try service.inspectLegacyHome(locations: locations)
        #expect(inspected.fileCount == 1)
        #expect(inspected.entryCount == 1)
        #expect(!inspected.containsUserData)

        let imported = try service.importLegacyHome(locations: locations)
        #expect(imported == inspected)
        #expect(
            try String(contentsOf: locations.harnessHome.appendingPathComponent(".anonymous-user-id"))
                == "anonymous"
        )
    }
}

private func temporaryDirectory(prefix: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}
