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
        // Not a script any more: it reads the app's real sprite data rather
        // than keeping a second hand-maintained copy that would drift.
        .executableTarget(
            name: "MakeIcon",
            dependencies: ["PRRadarCore"],
            path: "Sources/MakeIcon"
        ),
        // Renders a character to a PNG without launching anything. The cell
        // cast has `Scripts/mascot.py --png`, which can preview art because
        // it is the thing that draws it; the shelf drawn as outlines lives in
        // Swift and goes through the real layout, so its preview has to as
        // well.
        .executableTarget(
            name: "MascotPreview",
            dependencies: ["PRRadarCore"],
            path: "Sources/MascotPreview"
        ),
        .testTarget(
            name: "PRRadarCoreTests",
            dependencies: ["PRRadarCore"],
            path: "Tests/PRRadarCoreTests",
            // Real GitHub payloads, with the logins and titles replaced. What
            // they are for is the shape, which hand-written JSON can only ever
            // assert about itself — a field the server spells differently, or
            // stops sending, is exactly what a fixture catches and a mock does
            // not.
            resources: [.copy("Fixtures")]
        ),
    ]
)
