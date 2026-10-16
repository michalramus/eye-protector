// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EyeProtector",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "EyeProtectorCore"),
        .executableTarget(
            name: "EyeProtectorApp",
            dependencies: ["EyeProtectorCore"]
        ),
        .testTarget(
            name: "EyeProtectorCoreTests",
            dependencies: ["EyeProtectorCore"]
        ),
    ]
)
