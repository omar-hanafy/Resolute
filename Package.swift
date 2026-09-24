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
        .target(name: "ResoluteKit"),
        .executableTarget(
            name: "resolute",
            dependencies: [
                "ResoluteKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(name: "ResoluteApp", dependencies: ["ResoluteKit"]),
        .testTarget(
            name: "ResoluteKitTests",
            dependencies: ["ResoluteKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
