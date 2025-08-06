// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Core",
    platforms: [
        .iOS(.v17),
        .macOS(.v15),
    ],
    products: [
        .library(name: "CoreModels", targets: ["CoreModels"]),
        .library(name: "OpenMusicEventParser", targets: ["OpenMusicEventParser"]),
        .executable(name: "open-music-event", targets: ["OpenMusicEventCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections", from: "1.0.4"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.3.3"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.4.1"),
        .package(url: "https://github.com/pointfreeco/swift-tagged", from: "0.10.0"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.18.0"),
        .package(url: "https://github.com/pointfreeco/swift-parsing", from: "0.14.0"),

        .package(url: "https://source.skip.tools/skip.git", from: "1.5.18"),

        .package(url: "https://github.com/woodymelling/swift-file-tree", branch: "android-support"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
    ],
    targets: [
        .target(
            name: "CoreModels",
            dependencies: [
                .product(name: "Tagged", package: "swift-tagged"),
                .product(name: "CustomDump", package: "swift-custom-dump"),
            ],
        ),
        .target(
            name: "OpenMusicEventParser",
            dependencies: [
                "CoreModels",
                "Yams",
                .product(name: "FileTree", package: "swift-file-tree"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "CustomDump", package: "swift-custom-dump"),
                .product(name: "Parsing", package: "swift-parsing"),
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "Tagged", package: "swift-tagged"),
            ]
        ),
        .executableTarget(
            name: "OpenMusicEventCLI",
            dependencies: [
                "OpenMusicEventParser",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "OpenMusicEventParserTests",
            dependencies: [
                "OpenMusicEventParser",
                "Yams",
                .product(name: "CustomDump", package: "swift-custom-dump"),
                .product(name: "Parsing", package: "swift-parsing"),
                .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
                .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
                .product(name: "SnapshotTestingCustomDump", package: "swift-snapshot-testing")
            ],
            resources: [
                .copy("ExampleFestivals")
            ]
        ),
    ]
)
