// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MenuFeature",
    platforms: [.iOS(.v17)],
    products: [
        .library(
            name: "MenuFeature",
            targets: ["MenuDomain"]
        )
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../Networking"),
        .package(path: "../Security")
    ],
    targets: [
        .target(
            name: "MenuDomain",
            dependencies: [
                .product(name: "Core", package: "Core"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "Networking", package: "Networking"),
                .product(name: "SecurityKit", package: "Security")
            ]
        ),
        .testTarget(name: "MenuDomainTests", dependencies: ["MenuDomain"])
    ],
    swiftLanguageModes: [.v6]
)
