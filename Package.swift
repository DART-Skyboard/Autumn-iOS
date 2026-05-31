// swift-tools-version: 5.9
// Standard SPM Package.swift — used by GitHub Actions / Xcode on Mac
// For Swift Playgrounds on iPhone/iPad, use Package.swiftpm (see .swiftpm/ folder)
import PackageDescription

let package = Package(
    name: "Autumn",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "LEATRCore",      targets: ["LEATRCore"]),
        .library(name: "AutumnServices", targets: ["AutumnServices"]),
        .executable(name: "AutumnApp",   targets: ["AutumnApp"])
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
            // resources removed — no Resources folder
        )
    ]
)
