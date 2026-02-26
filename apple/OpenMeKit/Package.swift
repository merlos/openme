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
    targets: [
        .target(
            name: "OpenMeKit",
            path: "Sources/OpenMeKit"
        ),
    ]
)
