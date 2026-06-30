// swift-tools-version: 6.1
// This is a Skip (https://skip.dev) package.
import PackageDescription

let package = Package(
    name: "open-music-event",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v15)],
    products: [
        .executable(name: "ome", targets: ["OpenMusicEventCLI"]),
        .library(name: "BlueskyActorCache", targets: ["BlueskyActorCache"]),
        .library(name: "OpenMusicEventApp", type: .dynamic, targets: ["OpenMusicEventApp"]),
        .library(name: "OpenMusicEventAppEventViewer", targets: ["OpenMusicEventAppEventViewer"]),
        .library(name: "OpenMusicEventEditors", targets: ["OpenMusicEventEditors"]),
        .library(name: "OpenMusicEventViewers", targets: ["OpenMusicEventViewers"]),
        .library(name: "OpenMusicEventAuthentication", targets: ["OpenMusicEventAuthentication"]),
        .library(name: "OpenMusicEventDatabase", targets: ["OpenMusicEventDatabase"]),
        .library(name: "OpenMusicEventImages", targets: ["OpenMusicEventImages"]),
        .library(name: "OpenMusicEventLexicon", targets: ["OpenMusicEventLexicon"]),
        .library(name: "OpenMusicEventSource", targets: ["OpenMusicEventSource"]),
        .library(name: "OpenMusicEventSourceEditing", targets: ["OpenMusicEventSourceEditing"]),
        .library(name: "OpenMusicEventTimeZones", targets: ["OpenMusicEventTimeZones"]),
        .library(name: "OpenMusicEventWhiteLabel", targets: ["OpenMusicEventWhiteLabel"]),
        .library(name: "OpenMusicEventWhiteLabelApp", targets: ["OpenMusicEventWhiteLabelApp"]),
        .library(name: "ErrorHandling", targets: ["ErrorHandling"]),
        .library(name: "SourceEditing", targets: ["SourceEditing"]),
        .library(name: "LiquidGlassSegmentedPicker", targets: ["LiquidGlassSegmentedPicker"]),
        .library(name: "ScheduleComponents", targets: ["ScheduleComponents"]),
        .library(name: "SwiftUITabFeatures", targets: ["SwiftUITabFeatures"]),
    ],
    dependencies: [
        .package(url: "https://source.woody.fm/swift-composable-forms", branch: "main"),
        .package(url: "https://source.woody.fm/swift-frontmatter-parsing", branch: "main"),
        .package(url: "https://source.woody.fm/swift-file-tree", branch: "main"),
        .package(url: "https://source.woody.fm/swift-dependencies-http-client", branch: "main"),
        .package(path: "/Users/woody/Developer/swift-packages/swift-composable-atmosphere", traits: ["TCA26"]),
        .package(url: "https://source.woody.fm/swift-tagged-types-macro", branch: "main"),
        .package(url: "https://source.woody.fm/swift-urlqueryitem-coder", branch: "main"),
        .package(url: "https://source.woody.fm/swift-web-metadata", branch: "main", traits: ["Dependencies"]),
        .package(url: "https://source.woody.fm/swift-dependencies-source-control-client", branch: "main"),


        .package(url: "https://source.skip.tools/skip.git", from: "1.8.6"),
        .package(url: "https://source.skip.tools/skip-fuse-ui.git", from: "1.0.0"),

        .package(url: "https://github.com/pointfreeco/swift-clocks", branch: "clocks-2"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", branch: "26"),
        .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-tagged", from: "0.10.0"),
        .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.0.0"),
        .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.9.0"),
        .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.0.0", traits: ["SQLiteDataTagged"]),
        .package(url: "https://github.com/pointfreeco/TCA26", branch: "main", traits: ["Dependencies"]),


        .package(url: "https://github.com/14T/DateRangePicker", branch: "main"),
        .package(url: "https://github.com/apple/swift-crypto", from: "3.0.0"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.6.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.0.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(url: "https://github.com/apple/swift-http-types", from: "1.4.0"),
        .package(url: "https://github.com/1024jp/GzipSwift", from: "6.0.0"),
        .package(url: "https://github.com/kateinoigakukun/swift-tar", branch: "main"),
        .package(url: "https://github.com/omaralbeik/Drops.git", from: "1.7.0"),


    ],
    targets: [
        .target(
            name: "OpenMusicEventApp",
            dependencies: [
                "BlueskyActorCache",
                "ErrorHandling",
                "OpenMusicEventAppEventViewer",
                "OpenMusicEventAuthentication",
                "OpenMusicEventDatabase",
                "OpenMusicEventImages",
                "OpenMusicEventLexicon",
                "OpenMusicEventSource",
                "OpenMusicEventSourceClone",
                "OpenMusicEventSourceEditing",
                "OpenMusicEventTimeZones",
                "SourceEditing",
                .product(name: "ComposableArchitecture2", package: "TCA26"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Drops", package: "Drops", condition: .when(platforms: [.iOS])),
                .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
                .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
                .product(name: "SourceControlClient", package: "swift-dependencies-source-control-client"),
                .product(name: "SourceControlClientGit", package: "swift-dependencies-source-control-client"),
                .product(name: "SQLiteData", package: "sqlite-data"),
            ],
            resources: [.process("Resources")],
            plugins: [.plugin(name: "skipstone", package: "skip")]
        ),
        .target(
            name: "OpenMusicEventAuthentication",
            dependencies: [
                "OpenMusicEventSourceClone",
                .product(name: "ATProto", package: "swift-composable-atmosphere"),
                .product(name: "ATProtoOAuth", package: "swift-composable-atmosphere"),
                .product(name: "ATProtoServer", package: "swift-composable-atmosphere"),
                .product(name: "ComposableArchitecture2", package: "TCA26"),
                .product(name: "ComposableForms", package: "swift-composable-forms"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Sharing", package: "swift-sharing"),
                .product(name: "TCATProtoAuthentication", package: "swift-composable-atmosphere"),
                .product(name: "WebMetadataClient", package: "swift-web-metadata"),
                .product(name: "XRPCClient", package: "swift-composable-atmosphere"),
            ],
            resources: [.process("Resources")]
        ),
        .target(
            name: "OpenMusicEventAppEventViewer",
            dependencies: [
                "BlueskyActorCache",
                "ErrorHandling",
                "LiquidGlassSegmentedPicker",
                "OpenMusicEventDatabase",
                "OpenMusicEventEditors",
                "OpenMusicEventImages",
                "OpenMusicEventLexicon",
                "OpenMusicEventAuthentication",
                "OpenMusicEventSourceEditing",
                "OpenMusicEventTimeZones",
                "OpenMusicEventViewers",
                "ScheduleComponents",
                "SourceEditing",
                "SwiftUITabFeatures",
                .product(name: "ATProto", package: "swift-composable-atmosphere"),
                .product(name: "ATProtoOAuth", package: "swift-composable-atmosphere"),
                .product(name: "ComposableArchitecture2", package: "TCA26"),
                .product(name: "ComposableForms", package: "swift-composable-forms"),
                .product(name: "DateRangePicker", package: "DateRangePicker", condition: .when(platforms: [.iOS])),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Sharing", package: "swift-sharing"),
                .product(name: "SQLiteData", package: "sqlite-data"),
                .product(name: "TCATProtoAuthentication", package: "swift-composable-atmosphere"),
                .product(name: "XRPCClient", package: "swift-composable-atmosphere"),
            ],
            plugins: [.plugin(name: "skipstone", package: "skip")]
        ),
        .target(
            name: "OpenMusicEventViewers",
            dependencies: [
                "OpenMusicEventLexicon",
                .product(name: "ComposableArchitecture2", package: "TCA26"),
            ]
        ),
        .target(
            name: "OpenMusicEventEditors",
            dependencies: [
                "OpenMusicEventViewers",
                .product(name: "ComposableArchitecture2", package: "TCA26"),
            ]
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
            name: "BlueskyActorCache",
            dependencies: [
                .product(name: "ATProto", package: "swift-composable-atmosphere"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "SQLiteData", package: "sqlite-data"),
                .product(name: "XRPCClient", package: "swift-composable-atmosphere"),
            ]
        ),
        .target(
            name: "ErrorHandling",
            dependencies: [
                .product(name: "ComposableArchitecture2", package: "TCA26"),
                .product(name: "Dependencies", package: "swift-dependencies"),
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
                .product(name: "Tagged", package: "swift-tagged"),
            ]
        ),
        .target(
            name: "OpenMusicEventWhiteLabel",
            dependencies: [
                "OpenMusicEventLexicon",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ],
            plugins: [.plugin(name: "skipstone", package: "skip")]
        ),
        .target(
            name: "OpenMusicEventWhiteLabelApp",
            dependencies: [
                "ErrorHandling",
                "OpenMusicEventApp",
                "OpenMusicEventDatabase",
                "OpenMusicEventLexicon",
                "OpenMusicEventSource",
                "OpenMusicEventSourceClone",
                "OpenMusicEventSourceEditing",
                "OpenMusicEventWhiteLabel",
                "SourceEditing",
                .product(name: "ComposableArchitecture2", package: "TCA26"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "HTTPClient", package: "swift-dependencies-http-client"),
                .product(name: "SQLiteData", package: "sqlite-data"),
            ],
            plugins: [.plugin(name: "skipstone", package: "skip")]
        ),

        .target(
            name: "OpenMusicEventLexicon",
            dependencies: [
                "OpenMusicEventTimeZones",
                .product(name: "ATProto", package: "swift-composable-atmosphere"),
                .product(name: "Lexicon", package: "swift-composable-atmosphere"),
                .product(name: "LexiconSQLiteData", package: "swift-composable-atmosphere"),
                .product(name: "SQLiteData", package: "sqlite-data"),
            ]
        ),
        .target(
            name: "OpenMusicEventSourceEditing",
            dependencies: [
                "OpenMusicEventLexicon",
                "OpenMusicEventSource",
                "OpenMusicEventSourceClone",
                "SourceEditing",
                .product(name: "ATProto", package: "swift-composable-atmosphere"),
                .product(name: "ATProtoOAuth", package: "swift-composable-atmosphere"),
                .product(name: "CustomDump", package: "swift-custom-dump"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "FileTree", package: "swift-file-tree"),
                .product(name: "Gzip", package: "gzipswift"),
                .product(name: "HTTPClient", package: "swift-dependencies-http-client"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "Lexicon", package: "swift-composable-atmosphere"),
                .product(name: "SourceControlClient", package: "swift-dependencies-source-control-client"),
                .product(name: "SQLiteData", package: "sqlite-data"),
                .product(name: "XRPCClient", package: "swift-composable-atmosphere"),
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
                .product(name: "Lexicon", package: "swift-composable-atmosphere"),
                "Yams",
            ]
        ),
        .target(
            name: "OpenMusicEventSourceClone",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "ATProto", package: "swift-composable-atmosphere"),
                .product(name: "ATProtoOAuth", package: "swift-composable-atmosphere"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Gzip", package: "gzipswift"),
                .product(name: "HTTPClient", package: "swift-dependencies-http-client"),
                .product(name: "Sharing", package: "swift-sharing"),
                .product(name: "SourceControlClient", package: "swift-dependencies-source-control-client"),
                .product(name: "Tar", package: "swift-tar"),
                .product(name: "XRPCClient", package: "swift-composable-atmosphere"),
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
            name: "BlueskyActorCacheTests",
            dependencies: [
                "BlueskyActorCache",
                .product(name: "CustomDump", package: "swift-custom-dump"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "HTTPClient", package: "swift-dependencies-http-client"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "SQLiteData", package: "sqlite-data"),
                .product(name: "XRPCClient", package: "swift-composable-atmosphere"),
            ]
        ),
        .testTarget(
            name: "OpenMusicEventCLITests",
            dependencies: [
                "OpenMusicEventSourceClone",
                .product(name: "ATProto", package: "swift-composable-atmosphere"),
                .product(name: "CustomDump", package: "swift-custom-dump"),
                .product(name: "HTTPClient", package: "swift-dependencies-http-client"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "SourceControlClient", package: "swift-dependencies-source-control-client"),
                .product(name: "XRPCClient", package: "swift-composable-atmosphere"),
            ]
        ),
        .testTarget(
            name: "ErrorHandlingTests",
            dependencies: [
                "ErrorHandling",
                .product(name: "Clocks", package: "swift-clocks"),
                .product(name: "ComposableArchitecture2", package: "TCA26"),
                .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
                .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
            ]
        ),
        .testTarget(
            name: "OpenMusicEventAuthenticationTests",
            dependencies: [
                "OpenMusicEventAuthentication",
                .product(name: "Clocks", package: "swift-clocks"),
                .product(name: "ComposableArchitecture2", package: "TCA26"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
                .product(name: "TCATProtoAuthentication", package: "swift-composable-atmosphere"),
                .product(name: "WebMetadataClient", package: "swift-web-metadata"),
            ]
        ),
        .testTarget(
            name: "OpenMusicEventAppTests",
            dependencies: [
                "BlueskyActorCache",
                "ErrorHandling",
                "OpenMusicEventApp",
                "OpenMusicEventAuthentication",
                "OpenMusicEventLexicon",
                "OpenMusicEventSourceEditing",
                .product(name: "ATProto", package: "swift-composable-atmosphere"),
                .product(name: "Clocks", package: "swift-clocks"),
                .product(name: "ComposableArchitecture2", package: "TCA26"),
                .product(name: "CustomDump", package: "swift-custom-dump"),
                .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
                .product(name: "HTTPClient", package: "swift-dependencies-http-client"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
                .product(name: "SourceControlClient", package: "swift-dependencies-source-control-client"),
                .product(name: "SQLiteData", package: "sqlite-data"),
                .product(name: "XRPCClient", package: "swift-composable-atmosphere"),
            ]
        ),
        .testTarget(
            name: "OpenMusicEventWhiteLabelTests",
            dependencies: [
                "OpenMusicEventApp",
                "OpenMusicEventAppEventViewer",
                "OpenMusicEventLexicon",
                "OpenMusicEventSource",
                "OpenMusicEventSourceEditing",
                "OpenMusicEventWhiteLabel",
                "OpenMusicEventWhiteLabelApp",
                .product(name: "ATProto", package: "swift-composable-atmosphere"),
                .product(name: "ComposableArchitecture2", package: "TCA26"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
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
                .product(name: "ATProto", package: "swift-composable-atmosphere"),
                .product(name: "CustomDump", package: "swift-custom-dump"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "OpenMusicEventSourceTests",
            dependencies: [
                "OpenMusicEventLexicon",
                "OpenMusicEventSource",
                .product(name: "ATProto", package: "swift-composable-atmosphere"),
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
