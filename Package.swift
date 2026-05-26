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
        .library(name: "OpenMusicEventAuthentication", targets: ["OpenMusicEventAuthentication"]),
        .library(name: "OpenMusicEventDatabase", targets: ["OpenMusicEventDatabase"]),
        .library(name: "OpenMusicEventImages", targets: ["OpenMusicEventImages"]),
        .library(name: "OpenMusicEventLexicon", targets: ["OpenMusicEventLexicon"]),
        .library(name: "OpenMusicEventSource", targets: ["OpenMusicEventSource"]),
        .library(name: "OpenMusicEventSourceEditing", targets: ["OpenMusicEventSourceEditing"]),
        .library(name: "OpenMusicEventTimeZones", targets: ["OpenMusicEventTimeZones"]),
        .library(name: "ErrorHandling", targets: ["ErrorHandling"]),
        .library(name: "SourceEditing", targets: ["SourceEditing"]),
        .library(name: "LiquidGlassSegmentedPicker", targets: ["LiquidGlassSegmentedPicker"]),
        .library(name: "ScheduleComponents", targets: ["ScheduleComponents"]),
        .library(name: "SwiftUITabFeatures", targets: ["SwiftUITabFeatures"]),
    ],
    dependencies: [
        .package(url: "https://source.skip.tools/skip.git", from: "1.8.6"),
        .package(url: "https://source.skip.tools/skip-fuse-ui.git", from: "1.0.0"),

        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.9.0"),
        .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-tagged", from: "0.10.0"),
        .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.0.0"),
        .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.9.0"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.6.0"),
        .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.0.0", traits: ["SQLiteDataTagged"]),
        .package(url: "https://github.com/pointfreeco/TCA26", branch: "main"),
        .package(path: "../../../swift-packages/tca26-forms"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.0.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(path: "../../../swift-packages/swift-frontmatter-parsing"),
        .package(path: "../../../swift-packages/swift-file-tree"),
        .package(name: "swift-dependencies-http-client", path: "../../../swift-packages/swift-dependencies-http-client"),
        .package(name: "swift-tagged-types-macro", path: "../../../swift-packages/swift-tagged-types-macro"),
        .package(name: "swift-urlqueryitem-coder", path: "../../../swift-packages/3rd-party/swift-urlqueryitem-coder"),
        .package(url: "https://github.com/1024jp/GzipSwift", from: "6.0.0"),
        .package(url: "https://github.com/kateinoigakukun/swift-tar", branch: "main"),
        .package(url: "https://github.com/omaralbeik/Drops.git", from: "1.7.0"),


        .package(name: "tcatproto", path: "../../../composable-atmosphere/tcatproto"),
    ],
    targets: [
        .target(
            name: "OpenMusicEvent",
            dependencies: [
                "ErrorHandling",
                "OpenMusicEventAppEventViewer",
                "OpenMusicEventAuthentication",
                "OpenMusicEventDatabase",
                "OpenMusicEventImages",
                "OpenMusicEventLexicon",
                "OpenMusicEventSource",
                "OpenMusicEventSourceEditing",
                "OpenMusicEventTimeZones",
                "SourceEditing",
                .product(name: "ComposableArchitecture2", package: "TCA26"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Drops", package: "Drops", condition: .when(platforms: [.iOS])),
                .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
                .product(name: "SQLiteData", package: "sqlite-data"),
            ],
            resources: [.process("Resources")],
            plugins: [.plugin(name: "skipstone", package: "skip")]
        ),
        .target(
            name: "OpenMusicEventAuthentication",
            dependencies: [
                .product(name: "ATProtoOAuth", package: "tcatproto"),
                .product(name: "ComposableArchitecture2", package: "TCA26"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Sharing", package: "swift-sharing"),
                .product(name: "TCATProtoAuthentication", package: "tcatproto"),
                .product(name: "XRPCClient", package: "tcatproto"),
            ],
            resources: [.process("Resources")]
        ),
        .target(
            name: "OpenMusicEventAppEventViewer",
            dependencies: [
                "ErrorHandling",
                "LiquidGlassSegmentedPicker",
                "OpenMusicEventDatabase",
                "OpenMusicEventImages",
                "OpenMusicEventLexicon",
                "OpenMusicEventSourceEditing",
                "OpenMusicEventTimeZones",
                "ScheduleComponents",
                "SourceEditing",
                "SwiftUITabFeatures",
                .product(name: "ComposableArchitecture2", package: "TCA26"),
                .product(name: "ComposableForms", package: "tca26-forms"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Sharing", package: "swift-sharing"),
                .product(name: "SQLiteData", package: "sqlite-data"),
            ],
            plugins: [.plugin(name: "skipstone", package: "skip")]
        ),
        .target(
            name: "OpenMusicEventImages",
            dependencies: [
                "OpenMusicEventDatabase",
                "OpenMusicEventLexicon",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ],
            plugins: [.plugin(name: "skipstone", package: "skip")]
        ),
        .target(
            name: "ErrorHandling",
            dependencies: [
                .product(name: "ComposableArchitecture2", package: "TCA26"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
            ]
        ),
        .target(
            name: "LiquidGlassSegmentedPicker",
            plugins: [.plugin(name: "skipstone", package: "skip")]
        ),
        .target(
            name: "SourceEditing",
            dependencies: [
                .product(name: "CustomDump", package: "swift-custom-dump"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "SQLiteData", package: "sqlite-data"),
            ]
        ),
        .target(
            name: "OpenMusicEventDatabase",
            dependencies: [
                "OpenMusicEventLexicon",
                "OpenMusicEventSource",
                "OpenMusicEventSourceEditing",
                "OpenMusicEventTimeZones",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "HTTPClient", package: "swift-dependencies-http-client"),
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
            name: "OpenMusicEventSourceEditing",
            dependencies: [
                "OpenMusicEventLexicon",
                "OpenMusicEventSource",
                "SourceEditing",
                .product(name: "CustomDump", package: "swift-custom-dump"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "FileTree", package: "swift-file-tree"),
                .product(name: "Lexicon", package: "tcatproto"),
                .product(name: "SQLiteData", package: "sqlite-data"),
            ]
        ),
        .target(
            name: "OpenMusicEventSource",
            dependencies: [
                "OpenMusicEventLexicon",
                "OpenMusicEventSourceClone",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "FrontmatterParsing", package: "swift-frontmatter-parsing"),
                .product(name: "FileTree", package: "swift-file-tree"),
                .product(name: "Lexicon", package: "tcatproto"),
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
            name: "ScheduleComponents",
            dependencies: [
                .product(name: "Dependencies", package: "swift-dependencies"),
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
            name: "ErrorHandlingTests",
            dependencies: [
                "ErrorHandling",
                .product(name: "ComposableArchitecture2", package: "TCA26"),
                .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
                .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
            ]
        ),
        .testTarget(
            name: "OpenMusicEventAuthenticationTests",
            dependencies: [
                "OpenMusicEventAuthentication",
                .product(name: "ComposableArchitecture2", package: "TCA26"),
                .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
                .product(name: "TCATProtoAuthentication", package: "tcatproto"),
            ]
        ),
        .testTarget(
            name: "OpenMusicEventTests",
            dependencies: [
                "ErrorHandling",
                "OpenMusicEvent",
                "OpenMusicEventAuthentication",
                "OpenMusicEventLexicon",
                "OpenMusicEventSourceEditing",
                .product(name: "ATProto", package: "tcatproto"),
                .product(name: "ComposableArchitecture2", package: "TCA26"),
                .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
                .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
                .product(name: "SQLiteData", package: "sqlite-data"),
            ]
        ),
        .testTarget(
            name: "ScheduleComponentsTests",
            dependencies: [
                "ScheduleComponents",
            ]
        ),
        .testTarget(
            name: "SourceEditingTests",
            dependencies: [
                "SourceEditing",
                .product(name: "CustomDump", package: "swift-custom-dump"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "OpenMusicEventDatabaseTests",
            dependencies: [
                "OpenMusicEventDatabase",
                "SourceEditing",
                .product(name: "ATProto", package: "tcatproto"),
                .product(name: "CustomDump", package: "swift-custom-dump"),
                .product(name: "GRDB", package: "GRDB.swift"),
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
