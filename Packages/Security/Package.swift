// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Security",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Security", targets: ["Security"])
    ],
    targets: [
        .target(name: "Security"),
        .testTarget(name: "SecurityTests", dependencies: ["Security"])
    ],
    swiftLanguageModes: [.v6]
)
