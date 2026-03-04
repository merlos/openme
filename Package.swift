// swift-tools-version: 5.9
// This root Package.swift exists solely so consumers can add OpenMeKit via
// Swift Package Manager using a standard semver tag:
//
//   .package(url: "https://github.com/merlos/openme", from: "0.1.0")
//
// Development work (tests, DocC) uses apple/OpenMeKit/Package.swift directly.
// Do NOT add swift-docc-plugin here — it is a dev-only dependency.

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
            path: "apple/OpenMeKit/Sources/OpenMeKit"
        ),
    ]
)
