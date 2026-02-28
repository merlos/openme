// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenMeKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "OpenMeKit",
            targets: ["OpenMeKit"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-docc-plugin",
            from: "1.0.0"
        ),
    ],
    targets: [
        .target(
            name: "OpenMeKit",
            path: "Sources/OpenMeKit"
        ),
        .testTarget(
            name: "OpenMeKitTests",
            dependencies: ["OpenMeKit"],
            path: "Tests/OpenMeKitTests"
        ),
    ]
)
