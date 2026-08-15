import Foundation
import HarnessDesktopCore
import Testing

@Suite("clean uninstall", .serialized)
struct UninstallPlanTests {
    @Test func standardUninstallRemovesOwnedDataAndPreservesUserAssets() throws {
        let home = try makeUninstallHome(prefix: "uninstall-standard")
        defer { try? FileManager.default.removeItem(at: home) }
        let locations = AppDataLocations(home: home)
        try seedLocations(locations)

        let workspace = home.appendingPathComponent("Workspace", isDirectory: true)
        try seedDirectory(workspace)
        let external = home.appendingPathComponent("External", isDirectory: true)
        try seedDirectory(external)
        try FileManager.default.createSymbolicLink(
            atPath: locations.applicationSupport.appendingPathComponent("external-link").path,
            withDestinationPath: external.path
        )

        try UninstallPlan(locations: locations, mode: .standard).removeData()

        #expect(!FileManager.default.fileExists(atPath: locations.applicationSupport.path))
        #expect(FileManager.default.fileExists(atPath: locations.legacyHarnessHome.path))
        #expect(FileManager.default.fileExists(atPath: locations.sharedAgentsHome.path))
        #expect(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("keep.txt").path))
        #expect(FileManager.default.fileExists(atPath: external.appendingPathComponent("keep.txt").path))
    }

    @Test func applicationOnlyLeavesEveryDataPathUntouched() throws {
        let home = try makeUninstallHome(prefix: "uninstall-app-only")
        defer { try? FileManager.default.removeItem(at: home) }
        let locations = AppDataLocations(home: home)
        try seedLocations(locations)

        let removed = try UninstallPlan(locations: locations, mode: .applicationOnly).removeData()

        #expect(removed.isEmpty)
        #expect(FileManager.default.fileExists(atPath: locations.applicationSupport.path))
        #expect(FileManager.default.fileExists(atPath: locations.legacyHarnessHome.path))
        #expect(FileManager.default.fileExists(atPath: locations.sharedAgentsHome.path))
    }

    @Test func completeUninstallRemovesSharedDataAndRegisteredWorkspacesOnly() throws {
        let home = try makeUninstallHome(prefix: "uninstall-complete")
        defer { try? FileManager.default.removeItem(at: home) }
        let locations = AppDataLocations(home: home)
        try seedLocations(locations)
        let registered = home.appendingPathComponent("Projects/Registered", isDirectory: true)
        let unregistered = home.appendingPathComponent("Projects/Keep", isDirectory: true)
        try seedDirectory(registered)
        try seedDirectory(unregistered)

        let plan = UninstallPlan(
            locations: locations,
            mode: .complete,
            workspacePaths: [registered]
        )
        try plan.removeData()

        #expect(!FileManager.default.fileExists(atPath: locations.applicationSupport.path))
        #expect(!FileManager.default.fileExists(atPath: locations.legacyHarnessHome.path))
        #expect(!FileManager.default.fileExists(atPath: locations.sharedAgentsHome.path))
        #expect(!FileManager.default.fileExists(atPath: registered.path))
        #expect(FileManager.default.fileExists(atPath: unregistered.appendingPathComponent("keep.txt").path))
    }

    @Test func completeUninstallDoesNotFollowWorkspaceSymlink() throws {
        let home = try makeUninstallHome(prefix: "uninstall-workspace-symlink")
        defer { try? FileManager.default.removeItem(at: home) }
        let locations = AppDataLocations(home: home)
        try seedLocations(locations)

        let target = home.appendingPathComponent("Preserved Target", isDirectory: true)
        let workspaceLink = home.appendingPathComponent("Registered Workspace", isDirectory: true)
        try seedDirectory(target)
        try FileManager.default.createSymbolicLink(
            at: workspaceLink,
            withDestinationURL: target
        )

        try UninstallPlan(
            locations: locations,
            mode: .complete,
            workspacePaths: [workspaceLink]
        ).removeData()

        #expect(!FileManager.default.fileExists(atPath: workspaceLink.path))
        #expect(FileManager.default.fileExists(atPath: target.appendingPathComponent("keep.txt").path))
    }

    @Test func completeUninstallRejectsBroadOrSystemWorkspacePaths() throws {
        let home = try makeUninstallHome(prefix: "uninstall-unsafe")
        defer { try? FileManager.default.removeItem(at: home) }
        let locations = AppDataLocations(home: home)

        for unsafe in [
            home,
            home.appendingPathComponent("Library", isDirectory: true),
            URL(fileURLWithPath: "/", isDirectory: true),
            URL(fileURLWithPath: "/private/tmp/project", isDirectory: true),
            URL(fileURLWithPath: "/Volumes/Disk", isDirectory: true),
        ] {
            #expect(throws: (any Error).self) {
                try UninstallPlan(
                    locations: locations,
                    mode: .complete,
                    workspacePaths: [unsafe]
                ).removalPaths()
            }
        }
    }

    @Test func dryRunDoesNotDelete() throws {
        let home = try makeUninstallHome(prefix: "uninstall-dry-run")
        defer { try? FileManager.default.removeItem(at: home) }
        let locations = AppDataLocations(home: home)
        try locations.ensureRuntimeDirectories()

        let paths = try UninstallPlan(locations: locations, mode: .standard).removeData(dryRun: true)

        #expect(paths == locations.ownedPaths)
        #expect(FileManager.default.fileExists(atPath: locations.applicationSupport.path))
    }

    @Test func discoversWorkspaceAndSessionPathsWithoutReadingOtherValues() throws {
        let data = Data(
            """
            {
              "unit": {"name": "workspace", "version": 2},
              "global": {},
              "tables": {
                "workspaces": {
                  "one": {"path": "/Users/tester/Project", "title": "Project"}
                },
                "sessions": {
                  "a": {"identity": {"cwd": "/Users/tester/Project"}},
                  "b": {"identity": {"cwd": "/Volumes/Work/Other"}}
                }
              }
            }
            """.utf8
        )

        let paths = try WorkspaceDiscovery.pathsFromStorageData(data)

        #expect(paths == Set([
            URL(fileURLWithPath: "/Users/tester/Project", isDirectory: true),
            URL(fileURLWithPath: "/Volumes/Work/Other", isDirectory: true),
        ]))
    }

    @Test func backupRefusesDestinationInsideRemovalPath() throws {
        let home = try makeUninstallHome(prefix: "uninstall-backup")
        defer { try? FileManager.default.removeItem(at: home) }
        let source = home.appendingPathComponent("Source", isDirectory: true)
        try seedDirectory(source)
        let destination = source.appendingPathComponent("backup.zip", isDirectory: false)

        #expect(throws: (any Error).self) {
            try BackupService.createBackup(
                items: [BackupItem(source: source, archivePath: "Data/Source")],
                destination: destination,
                removalPaths: [source]
            )
        }
    }

    private func seedLocations(_ locations: AppDataLocations) throws {
        try locations.ensureRuntimeDirectories()
        try seedDirectory(locations.legacyHarnessHome)
        try seedDirectory(locations.sharedAgentsHome)
    }

    private func seedDirectory(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: directory.appendingPathComponent("keep.txt"))
    }

    private func makeUninstallHome(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
