// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "DeepSeekHarnessDesktop",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "HarnessDesktopCore", targets: ["HarnessDesktopCore"]),
        .executable(name: "DeepSeekHarnessDesktop", targets: ["DeepSeekHarnessDesktop"]),
        .executable(name: "DeepSeekHarnessUninstaller", targets: ["DeepSeekHarnessUninstaller"]),
    ],
    targets: [
        .target(
            name: "HarnessDesktopCore",
            path: "desktop/Sources/HarnessDesktopCore"
        ),
        .executableTarget(
            name: "DeepSeekHarnessDesktop",
            dependencies: ["HarnessDesktopCore"],
            path: "desktop/Sources/DeepSeekHarnessDesktop"
        ),
        .executableTarget(
            name: "DeepSeekHarnessUninstaller",
            dependencies: ["HarnessDesktopCore"],
            path: "desktop/Sources/DeepSeekHarnessUninstaller"
        ),
        .testTarget(
            name: "HarnessDesktopCoreTests",
            dependencies: ["HarnessDesktopCore"],
            path: "desktop/Tests/HarnessDesktopCoreTests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
