import Foundation
import HarnessDesktopCore
import Testing

@Suite("desktop launch environment")
struct EnvironmentBuilderTests {
    @Test func buildsDeterministicDesktopEnvironment() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let locations = AppDataLocations(home: home)
        let environment = EnvironmentBuilder.harnessEnvironment(
            locations: locations,
            embeddedNodeDirectory: URL(fileURLWithPath: "/Applications/DeepSeek Harness.app/Contents/Resources/runtime"),
            base: [
                "PATH": "/custom/bin:/usr/bin",
                "NODE_OPTIONS": "--require=/tmp/inject.js",
                "DYLD_INSERT_LIBRARIES": "/tmp/inject.dylib",
                "DEEPSEEK_API_KEY": "preserved",
            ]
        )
        #expect(environment["NODE_OPTIONS"] == nil)
        #expect(environment["DYLD_INSERT_LIBRARIES"] == nil)
        #expect(environment["DEEPSEEK_API_KEY"] == "preserved")
        #expect(environment["DSH_HOME"] == locations.harnessHome.path)
        #expect(environment["PWD"] == locations.bootstrapWorkspace.path)
        #expect(environment["PATH"]?.hasPrefix("/Applications/DeepSeek Harness.app/Contents/Resources/runtime:") == true)
        #expect(environment["PATH"]?.components(separatedBy: ":").filter { $0 == "/usr/bin" }.count == 1)
    }
}
