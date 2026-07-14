import ProjectDescription

let project = Project(
    name: "CommerceApp",
    organizationName: "Jerry Nows",
    packages: [
        .local(path: "../../Packages/Core"),
        .local(path: "../../Packages/DesignSystem"),
        .local(path: "../../Packages/LoginFeature"),
        .local(path: "../../Packages/Security"),
        .local(path: "../../Packages/Networking"),
        .remote(
            url: "https://github.com/hmlongco/Factory.git",
            requirement: .upToNextMajor(from: "3.3.1")
        ),
        .remote(
            url: "https://github.com/quickbirdstudios/XCoordinator.git",
            requirement: .upToNextMajor(from: "2.2.1")
        )
    ],
    settings: .settings(
        base: [
            "SWIFT_STRICT_CONCURRENCY": "complete",
            "SWIFT_VERSION": "6.0"
        ]
    ),
    targets: [
        .target(
            name: "CommerceApp",
            destinations: .iOS,
            product: .app,
            bundleId: "com.jerrynows.commerce",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .file(path: "Resources/Info.plist"),
            sources: ["Sources/**"],
            resources: [
                .glob(pattern: "Resources/**", excluding: ["Resources/Info.plist"])
            ],
            dependencies: [
                .package(product: "Core"),
                .package(product: "DesignSystem"),
                .package(product: "LoginFeature"),
                .package(product: "SecurityKit"),
                .package(product: "Networking"),
                .package(product: "FactoryKit"),
                .package(product: "XCoordinator")
            ]
        ),
        .target(
            name: "CommerceAppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.jerrynows.commerce.tests",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .default,
            sources: ["Tests/**"],
            dependencies: [.target(name: "CommerceApp")]
        ),
        .target(
            name: "CommerceAppUITests",
            destinations: .iOS,
            product: .uiTests,
            bundleId: "com.jerrynows.commerce.uitests",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .default,
            sources: ["UITests/**"],
            dependencies: [.target(name: "CommerceApp")]
        )
    ]
)
