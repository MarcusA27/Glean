// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Glean",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "GleanKit"),
        .executableTarget(
            name: "Glean",
            dependencies: ["GleanKit"]
        )
    ]
)
