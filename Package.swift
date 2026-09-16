// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PRRadar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "PRRadarCore", path: "Sources/PRRadarCore"),
        .executableTarget(
            name: "PRRadar",
            dependencies: ["PRRadarCore"],
            path: "Sources/PRRadar"
        ),
        .testTarget(
            name: "PRRadarCoreTests",
            dependencies: ["PRRadarCore"],
            path: "Tests/PRRadarCoreTests"
        ),
    ]
)
