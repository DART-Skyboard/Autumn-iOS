import ProjectDescription

let project = Project(
    name: "Autumn",
    targets: [
        .target(
            name: "AutumnApp",
            destinations: .iOS,
            product: .app,
            bundleId: "DART-Meadow-LLC.Autumn",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .file(path: "Sources/AutumnApp/Info.plist"),
            sources: [
                "Sources/AutumnApp/**",
                "Sources/AutumnServices/**",
                "Sources/LEATRCore/**"
            ],
            dependencies: [
                .external(name: "MarkdownUI")
            ],
            settings: .settings(base: [
                "DEVELOPMENT_TEAM": "L7AHWS9Q6V",
                "CODE_SIGN_STYLE": "Automatic",
                "MARKETING_VERSION": "1.0.0",
                "CURRENT_PROJECT_VERSION": "1",
                "ENABLE_BITCODE": "NO"
            ])
        )
    ]
)
