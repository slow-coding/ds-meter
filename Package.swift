// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DSMeter",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "DSMeter", path: "Sources/DSMeter")
    ]
)
