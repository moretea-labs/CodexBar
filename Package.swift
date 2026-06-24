// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CodexBar", targets: ["CodexBar"])
    ],
    targets: [
        .executableTarget(
            name: "CodexBar",
            path: "Sources/CodexBar"
        )
    ]
)
