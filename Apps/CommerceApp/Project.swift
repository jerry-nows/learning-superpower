import ProjectDescription

let project = Project(
    name: "CommerceApp",
    organizationName: "Jerry Nows",
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
            resources: ["Resources/**"]
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
