import Foundation
import HarnessDesktopCore
import Testing

@Suite("macOS application data locations")
struct AppDataLocationsTests {
    @Test func ownedPathsUseStandardMacDirectories() throws {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let locations = AppDataLocations(home: home)
        #expect(
            locations.harnessHome.path
                == "/Users/tester/Library/Application Support/DeepSeek Harness/Harness"
        )
        #expect(locations.ownedPaths.contains(locations.preferences))
        #expect(!locations.ownedPaths.contains(locations.legacyHarnessHome))
        #expect(!locations.ownedPaths.contains(locations.sharedAgentsHome))
        _ = try locations.validatedOwnedPaths()
    }

    @Test func rejectsSharedAndUnownedPaths() {
        let locations = AppDataLocations(home: URL(fileURLWithPath: "/Users/tester", isDirectory: true))
        #expect(throws: (any Error).self) { try locations.validateOwnedPath(locations.legacyHarnessHome) }
        #expect(throws: (any Error).self) { try locations.validateOwnedPath(locations.sharedAgentsHome) }
        #expect(throws: (any Error).self) { try locations.validateOwnedPath(locations.home) }
        #expect(throws: (any Error).self) {
            try locations.validateOwnedPath(locations.home.appendingPathComponent("Documents"))
        }
    }
}
