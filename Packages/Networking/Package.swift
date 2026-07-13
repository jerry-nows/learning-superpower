// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Networking",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Networking", targets: ["Networking"])
    ],
    dependencies: [
        .package(url: "https://github.com/Moya/Moya.git", from: "15.0.0")
    ],
    targets: [
        .target(
            name: "Networking",
            dependencies: [
                .product(name: "Moya", package: "Moya")
            ]
        ),
        .testTarget(name: "NetworkingTests", dependencies: ["Networking"])
    ],
    swiftLanguageModes: [.v6]
)
