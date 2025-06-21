// swift-tools-version: 6.1
// This is a Skip (https://skip.tools) package.
import PackageDescription

let package = Package(
    name: "open-music-event",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v15)
    ],
    products: [
        .library(name: "OpenMusicEvent", targets: ["OpenMusicEvent"])
    ],
    dependencies: [
        .package(path: "Core"),

        .package(url: "https://github.com/apple/swift-collections", from: "1.0.4"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),

        .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.3.3"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.4.1"),
        .package(url: "https://github.com/pointfreeco/swift-navigation", from: "2.3.0"),
        .package(url: "https://github.com/pointfreeco/sharing-grdb", from: "0.4.0"),
        .package(url: "https://github.com/groue/GRDBSnapshotTesting.git", from: "0.4.2"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.18.0"),

        .package(url: "https://github.com/woodymelling/skip-image-caching", branch: "main"),
        .package(url: "https://github.com/vapor-community/Zip.git", from: "2.2.6"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0")
    ],
    targets: [
        .target(
            name: "OpenMusicEvent",
            dependencies: [
                .product(name: "OpenMusicEventParser", package: "Core"),
                .product(name: "CoreModels", package: "Core"),
                .product(name: "SharingGRDB", package: "sharing-grdb"),
                .product(name: "ImageCaching", package: "skip-image-caching"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "Zip", package: "zip"),
                .product(name: "SwiftUINavigation", package: "swift-navigation"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
                .product(name: "Logging", package: "swift-log")
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "OpenMusicEventTests",
            dependencies: [
                "OpenMusicEvent",
                .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
                .product(name: "GRDBSnapshotTesting", package: "grdbsnapshottesting"),
                .product(name: "DependenciesTestSupport", package: "swift-dependencies")
            ]
        )
    ]
)
