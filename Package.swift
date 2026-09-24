// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Resolute",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ResoluteKit", targets: ["ResoluteKit"]),
    ],
    targets: [
        .target(name: "ResoluteKit"),
        .testTarget(
            name: "ResoluteKitTests",
            dependencies: ["ResoluteKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
