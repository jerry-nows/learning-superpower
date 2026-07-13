// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LoginFeature",
    platforms: [.iOS(.v17)],
    products: [
        .library(
            name: "LoginFeature",
            targets: ["LoginDomain", "LoginData", "LoginPresentation"]
        )
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../Security"),
        .package(path: "../Networking")
    ],
    targets: [
        .target(name: "LoginDomain"),
        .target(
            name: "LoginData",
            dependencies: [
                "LoginDomain",
                .product(name: "Networking", package: "Networking"),
                .product(name: "Security", package: "Security")
            ]
        ),
        .target(
            name: "LoginPresentation",
            dependencies: [
                "LoginDomain",
                .product(name: "DesignSystem", package: "DesignSystem")
            ]
        ),
        .testTarget(name: "LoginDomainTests", dependencies: ["LoginDomain"]),
        .testTarget(name: "LoginDataTests", dependencies: ["LoginData"]),
        .testTarget(name: "LoginPresentationTests", dependencies: ["LoginPresentation"])
    ],
    swiftLanguageModes: [.v6]
)
