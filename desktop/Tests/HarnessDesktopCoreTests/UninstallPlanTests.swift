import Foundation
import HarnessDesktopCore
import Testing

@Suite("clean uninstall", .serialized)
struct UninstallPlanTests {
    @Test func removesOnlyOwnedDataAndPreservesSharedTargets() throws {
        let home = try makeUninstallHome(prefix: "uninstall-tests")
        defer { try? FileManager.default.removeItem(at: home) }
        let locations = AppDataLocations(home: home)
        try locations.ensureRuntimeDirectories()
        try FileManager.default.createDirectory(at: locations.legacyHarnessHome, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: locations.sharedAgentsHome, withIntermediateDirectories: true)
        let workspace = home.appendingPathComponent("Workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: workspace.appendingPathComponent("project.txt"))
        try Data("keep".utf8).write(to: locations.legacyHarnessHome.appendingPathComponent("session.jsonl"))

        let external = home.appendingPathComponent("External", isDirectory: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: external.appendingPathComponent("target.txt"))
        try FileManager.default.createSymbolicLink(
            atPath: locations.applicationSupport.appendingPathComponent("external-link").path,
            withDestinationPath: external.path
        )

        try UninstallPlan(locations: locations).removeOwnedData()

        #expect(!FileManager.default.fileExists(atPath: locations.applicationSupport.path))
        #expect(FileManager.default.fileExists(atPath: locations.legacyHarnessHome.path))
        #expect(FileManager.default.fileExists(atPath: locations.sharedAgentsHome.path))
        #expect(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("project.txt").path))
        #expect(FileManager.default.fileExists(atPath: external.appendingPathComponent("target.txt").path))
    }

    @Test func dryRunDoesNotDelete() throws {
        let home = try makeUninstallHome(prefix: "uninstall-dry-run")
        defer { try? FileManager.default.removeItem(at: home) }
        let locations = AppDataLocations(home: home)
        try locations.ensureRuntimeDirectories()
        let paths = try UninstallPlan(locations: locations).removeOwnedData(dryRun: true)
        #expect(paths == locations.ownedPaths)
        #expect(FileManager.default.fileExists(atPath: locations.applicationSupport.path))
    }
}

private func makeUninstallHome(prefix: String) throws -> URL {
    let home = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    return home
}
