// swift-tools-version: 5.9
// Swift Playgrounds Package.swift — for iPhone/iPad via Swift Playgrounds 4
// GitHub Actions uses the root Package.swift (no AppleProductTypes)
import PackageDescription
import AppleProductTypes

let package = Package(
    name: "Autumn",
    platforms: [.iOS("17.0")],
    products: [
        .iOSApplication(
            name: "Autumn",
            targets: ["AutumnApp"],
            bundleIdentifier: "DART-Meadow-LLC.Autumn",
            teamIdentifier: "L7AHWS9Q6V",
            displayVersion: "1.0.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .leaf),
            accentColor: .literal(.init(colorSpace: .sRGB, red: 0.0, green: 0.898, blue: 1.0)),
            supportedDeviceFamilies: [.phone, .pad],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeLeft,
                .landscapeRight,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ],
            capabilities: [
                .microphone(purposeString: "Voice input for AI conversation"),
                .speechRecognition(purposeString: "Transcribe voice messages")
            ],
            appCategory: .productivity
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/gonzalezreal/swift-markdown-ui",
            from: "2.4.0"
        )
    ],
    targets: [
        .target(
            name: "LEATRCore",
            path: "Sources/LEATRCore"
        ),
        .target(
            name: "AutumnServices",
            dependencies: ["LEATRCore"],
            path: "Sources/AutumnServices"
        ),
        .executableTarget(
            name: "AutumnApp",
            dependencies: [
                "LEATRCore",
                "AutumnServices",
                .product(name: "MarkdownUI", package: "swift-markdown-ui")
            ],
            path: "Sources/AutumnApp",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
