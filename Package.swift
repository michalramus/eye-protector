// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EyeProtector",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "EyeProtectorCore"),
        .target(name: "CurfewCore"),
        .executableTarget(
            name: "EyeProtectorApp",
            dependencies: ["EyeProtectorCore"]
        ),
        .testTarget(
            name: "EyeProtectorCoreTests",
            dependencies: ["EyeProtectorCore"]
        ),
        .testTarget(
            name: "CurfewCoreTests",
            dependencies: ["CurfewCore"]
        ),
    ]
)
