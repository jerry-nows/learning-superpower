// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Security",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "SecurityKit", targets: ["SecurityKit"])
    ],
    targets: [
        .target(name: "SecurityKit", path: "Sources/Security"),
        .testTarget(name: "SecurityTests", dependencies: ["SecurityKit"])
    ],
    swiftLanguageModes: [.v6]
)
