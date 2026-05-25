// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "img2b",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "img2b",
            path: "Sources/img2b"
        )
    ]
)
