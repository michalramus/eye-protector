// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EyeProtector",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "EyeProtectorCore"),
        .target(name: "CurfewCore"),
        .target(
            name: "ShieldUI",
            dependencies: ["EyeProtectorCore"]
        ),
        .executableTarget(
            name: "EyeProtectorApp",
            dependencies: ["EyeProtectorCore", "ShieldUI"]
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
