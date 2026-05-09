// swift-tools-version: 6.1
// This is a Skip (https://skip.dev) package.
import PackageDescription

let package = Package(
    name: "open-music-event",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v15)],
    products: [
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
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(path: "../../Core/swift-file-tree"),


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
                .product(name: "Lexicon", package: "tcatproto"),
                .product(name: "LexiconSQLiteData", package: "tcatproto"),
                .product(name: "SQLiteData", package: "sqlite-data"),
            ]
        ),
        .target(
            name: "OpenMusicEventSource",
            dependencies: [
                "OpenMusicEventLexicon",
                .product(name: "FileTree", package: "swift-file-tree"),
                "Yams",
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
                .product(name: "CustomDump", package: "swift-custom-dump"),
            ]
        ),
        .testTarget(
            name: "OpenMusicEventSourceTests",
            dependencies: [
                "OpenMusicEventSource",
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
