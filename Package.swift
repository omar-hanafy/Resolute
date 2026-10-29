// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Resolute",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ResoluteKit", targets: ["ResoluteKit"]),
        .executable(name: "resolute", targets: ["resolute"]),
        .executable(name: "ResoluteApp", targets: ["ResoluteApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        // Displays, modes, overrides and everything else the app and the command share.
        .target(name: "ResoluteKit"),
        // The design system: tokens, materials, pictures and components. AppKit and
        // SwiftUI only; it knows nothing about displays.
        .target(name: "ResoluteDesign"),
        .executableTarget(
            name: "resolute",
            dependencies: [
                "ResoluteKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "ResoluteApp",
            dependencies: ["ResoluteKit", "ResoluteDesign"],
            // Notes for maintainers, not a resource.
            exclude: ["Integrations/README.md"]
        ),
        .testTarget(
            name: "ResoluteKitTests",
            dependencies: ["ResoluteKit"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "ResoluteDesignTests", dependencies: ["ResoluteDesign"]),
        .testTarget(name: "ResoluteAppTests", dependencies: ["ResoluteApp", "ResoluteKit", "ResoluteDesign"]),
        .testTarget(
            name: "ResoluteCLITests",
            dependencies: ["resolute", "ResoluteKit", .product(name: "ArgumentParser", package: "swift-argument-parser")]
        ),
    ]
)
