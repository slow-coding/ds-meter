// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PIMeter",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "PIMeter", path: "Sources/PIMeter")
    ]
)
