// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MenuFeature",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(
            name: "MenuFeature",
            targets: ["MenuDomain", "MenuData", "MenuPresentation"]
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
            dependencies: []
        ),
        .target(
            name: "MenuData",
            dependencies: [
                "MenuDomain",
                .product(name: "Core", package: "Core"),
                .product(name: "Networking", package: "Networking")
            ]
        ),
        .target(
            name: "MenuPresentation",
            dependencies: [
                "MenuDomain",
                "MenuData",
                .product(name: "DesignSystem", package: "DesignSystem")
            ]
        ),
        .testTarget(name: "MenuDomainTests", dependencies: ["MenuDomain"]),
        .testTarget(name: "MenuDataTests", dependencies: ["MenuData"]),
        .testTarget(name: "MenuPresentationTests", dependencies: ["MenuPresentation"])
    ],
    swiftLanguageModes: [.v6]
)
