// swift-tools-version: 6.1
// This is a Skip (https://skip.dev) package.
import PackageDescription

let package = Package(
    name: "open-music-event",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v15)],
    products: [
        .executable(name: "ome", targets: ["OpenMusicEventCLI"]),
        .library(name: "OpenMusicEvent", type: .dynamic, targets: ["OpenMusicEvent"]),
        .library(name: "OpenMusicEventAppEventViewer", targets: ["OpenMusicEventAppEventViewer"]),
        .library(name: "OpenMusicEventDatabase", targets: ["OpenMusicEventDatabase"]),
        .library(name: "OpenMusicEventLexicon", targets: ["OpenMusicEventLexicon"]),
        .library(name: "OpenMusicEventSource", targets: ["OpenMusicEventSource"]),
        .library(name: "OpenMusicEventTimeZones", targets: ["OpenMusicEventTimeZones"]),
        .library(name: "SwiftUITabFeatures", targets: ["SwiftUITabFeatures"]),
    ],
    dependencies: [
        .package(url: "https://source.skip.tools/skip.git", from: "1.8.6"),
        .package(url: "https://source.skip.tools/skip-fuse-ui.git", from: "1.0.0"),

        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.9.0"),
        .package(url: "https://github.com/pointfreeco/swift-tagged", from: "0.10.0"),
        .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.0.0"),
        .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.0.0", traits: ["SQLiteDataTagged"]),
        .package(url: "https://github.com/pointfreeco/TCA26", branch: "main"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.0.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(path: "../../../swift-packages/swift-file-tree"),
        .package(url: "https://tangled.org/woody.fm/swift-dependencies-http-client", branch: "main"),
        .package(url: "https://github.com/1024jp/GzipSwift", from: "6.0.0"),
        .package(url: "https://github.com/kateinoigakukun/swift-tar", branch: "main"),


        .package(url: "https://source.woody.fm/tcatproto", branch: "main"),
//        .package(path: "~/Developer/composable-atmosphere/tcatproto")
    ],
    targets: [
        .target(
            name: "OpenMusicEvent",
            dependencies: [
                "OpenMusicEventAppEventViewer",
                "OpenMusicEventDatabase",
                "OpenMusicEventLexicon",
                "OpenMusicEventSource",
                "OpenMusicEventTimeZones",
                .product(name: "ComposableArchitecture2", package: "TCA26"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
                .product(name: "SQLiteData", package: "sqlite-data"),
            ],
            resources: [.process("Resources")],
            plugins: [.plugin(name: "skipstone", package: "skip")]
        ),
        .target(
            name: "OpenMusicEventAppEventViewer",
            dependencies: [
                "OpenMusicEventLexicon",
                "OpenMusicEventTimeZones",
                "SwiftUITabFeatures",
                .product(name: "ComposableArchitecture2", package: "TCA26"),
                .product(name: "Dependencies", package: "swift-dependencies"),
            ],
            plugins: [.plugin(name: "skipstone", package: "skip")]
        ),
        .target(
            name: "OpenMusicEventDatabase",
            dependencies: [
                "OpenMusicEventLexicon",
                "OpenMusicEventSource",
                "OpenMusicEventTimeZones",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "SQLiteData", package: "sqlite-data"),
            ]
        ),

        .target(
            name: "OpenMusicEventLexicon",
            dependencies: [
                "OpenMusicEventTimeZones",
                .product(name: "ATProto", package: "tcatproto"),
                .product(name: "Lexicon", package: "tcatproto"),
                .product(name: "LexiconSQLiteData", package: "tcatproto"),
                .product(name: "SQLiteData", package: "sqlite-data"),
            ]
        ),
        .target(
            name: "OpenMusicEventSource",
            dependencies: [
                "OpenMusicEventLexicon",
                "OpenMusicEventSourceClone",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Lexicon", package: "tcatproto"),
                .product(name: "FileTree", package: "swift-file-tree"),
                "Yams",
            ]
        ),
        .target(
            name: "OpenMusicEventSourceClone",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "ATProto", package: "tcatproto"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Gzip", package: "gzipswift"),
                .product(name: "HTTPClient", package: "swift-dependencies-http-client"),
                .product(name: "Tar", package: "swift-tar"),
            ]
        ),
        .target(
            name: "OpenMusicEventTimeZones",
            dependencies: [
                .product(name: "SQLiteData", package: "sqlite-data"),
            ],
            plugins: [.plugin(name: "skipstone", package: "skip")]
        ),
        .target(
            name: "SwiftUITabFeatures",
            dependencies: [
                .product(name: "Tagged", package: "swift-tagged"),
                .product(name: "CustomDump", package: "swift-custom-dump")
            ],
            plugins: [.plugin(name: "skipstone", package: "skip")]
        ),
        .executableTarget(
            name: "OpenMusicEventCLI",
            dependencies: [
                "OpenMusicEventDatabase",
                "OpenMusicEventLexicon",
                "OpenMusicEventSource",
                "OpenMusicEventSourceClone",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "FileTree", package: "swift-file-tree"),
                .product(name: "HTTPClient", package: "swift-dependencies-http-client"),
            ]
        ),
        .testTarget(
            name: "OpenMusicEventCLITests",
            dependencies: [
                "OpenMusicEventSourceClone",
                .product(name: "CustomDump", package: "swift-custom-dump"),
            ]
        ),
        .testTarget(
            name: "OpenMusicEventTests",
            dependencies: [
                "OpenMusicEvent",
                "OpenMusicEventLexicon",
                .product(name: "ATProto", package: "tcatproto"),
                .product(name: "ComposableArchitecture2", package: "TCA26"),
                .product(name: "SQLiteData", package: "sqlite-data"),
            ]
        ),
        .testTarget(
            name: "OpenMusicEventDatabaseTests",
            dependencies: [
                "OpenMusicEventDatabase",
                .product(name: "ATProto", package: "tcatproto"),
                .product(name: "CustomDump", package: "swift-custom-dump"),
            ]
        ),
        .testTarget(
            name: "OpenMusicEventSourceTests",
            dependencies: [
                "OpenMusicEventLexicon",
                "OpenMusicEventSource",
                .product(name: "ATProto", package: "tcatproto"),
                .product(name: "CustomDump", package: "swift-custom-dump"),
            ],
            resources: [
                .copy("Fixtures")
            ]
        ),
        .testTarget(
            name: "OpenMusicEventTimeZonesTests",
            dependencies: [
                "OpenMusicEventTimeZones",
                .product(name: "SQLiteData", package: "sqlite-data"),
            ]
        ),
        .testTarget(
            name: "SwiftUITabFeaturesTests",
            dependencies: [
                "SwiftUITabFeatures",
            ]
        ),
    ]
)
