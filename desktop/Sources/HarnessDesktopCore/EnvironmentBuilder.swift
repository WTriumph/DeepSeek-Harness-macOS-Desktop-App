import Foundation

public enum EnvironmentBuilder {
    private static let removedKeys: Set<String> = [
        "NODE_OPTIONS",
        "NODE_PATH",
        "NPM_CONFIG_PREFIX",
        "PNPM_HOME",
        "ELECTRON_RUN_AS_NODE",
    ]

    public static func harnessEnvironment(
        locations: AppDataLocations,
        embeddedNodeDirectory: URL,
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = base.filter { key, _ in
            !removedKeys.contains(key) && !key.hasPrefix("DYLD_")
        }

        let home = locations.home.path
        let preferredPaths = [
            embeddedNodeDirectory.path,
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "\(home)/.cargo/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
        let inheritedPaths = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        environment["PATH"] = unique(preferredPaths + inheritedPaths).joined(separator: ":")
        environment["HOME"] = home
        environment["DSH_HOME"] = locations.harnessHome.path
        environment["NODE_COMPILE_CACHE"] = locations.nodeCompileCache.path
        environment["NODE_ENV"] = "production"
        environment["NO_UPDATE_NOTIFIER"] = "1"
        environment["NPM_CONFIG_UPDATE_NOTIFIER"] = "false"
        environment["PWD"] = locations.bootstrapWorkspace.path
        if environment["LANG"] == nil && environment["LC_CTYPE"] == nil {
            environment["LANG"] = "en_US.UTF-8"
        }
        return environment
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { value in
            !value.isEmpty && seen.insert(value).inserted
        }
    }
}
