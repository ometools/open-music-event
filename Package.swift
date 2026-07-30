// swift-tools-version: 6.1
// This is a Skip (https://skip.dev) package.
import Foundation
import PackageDescription

#if os(macOS)
let skipstonePlugins: [Target.PluginUsage] = [.plugin(name: "skipstone", package: "skip")]
let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
func packagePath(_ relativePath: String) -> String {
    URL(fileURLWithPath: relativePath, relativeTo: packageDirectory)
        .standardizedFileURL
        .path
}
let skipSharingPath = [
    "../../swift-packages/3rd-party/skip/skip-sharing",
    "../../../swift-packages/3rd-party/skip/skip-sharing",
].map(packagePath)
    .first { FileManager.default.fileExists(atPath: $0) }
    ?? packagePath("../../swift-packages/3rd-party/skip/skip-sharing")
#else
let skipstonePlugins: [Target.PluginUsage] = []
#endif

var products: [Product] = [
    .executable(name: "ome", targets: ["OpenMusicEventCLI"]),
    .executable(name: "ome-release-check", targets: ["OpenMusicEventReleaseCheck"]),
    .library(name: "BlueskyActorCache", targets: ["BlueskyActorCache"]),
    .library(name: "OpenMusicEventAuthentication", targets: ["OpenMusicEventAuthentication"]),
    .library(name: "OpenMusicEventAppViewServer", targets: ["OpenMusicEventAppViewServer"]),
    .library(name: "OpenMusicEventComponents", targets: ["OpenMusicEventComponents"]),
    .library(name: "OpenMusicEventDatabase", targets: ["OpenMusicEventDatabase"]),
    .library(name: "OpenMusicEventLexicon", targets: ["OpenMusicEventLexicon"]),
    .library(name: "OpenMusicEventReleaseTools", targets: ["OpenMusicEventReleaseTools"]),
    .library(name: "OpenMusicEventRouting", targets: ["OpenMusicEventRouting"]),
    .library(name: "OpenMusicEventSource", targets: ["OpenMusicEventSource"]),
    .library(name: "OpenMusicEventSourceEditing", targets: ["OpenMusicEventSourceEditing"]),
    .library(name: "OpenMusicEventTimeZones", targets: ["OpenMusicEventTimeZones"]),
    .library(name: "OpenMusicEventWhiteLabel", targets: ["OpenMusicEventWhiteLabel"]),
    .library(name: "ErrorHandling", targets: ["ErrorHandling"]),
    .library(name: "SourceEditing", targets: ["SourceEditing"]),
    .executable(name: "OpenMusicEventAppView", targets: ["OpenMusicEventAppView"]),
    .executable(name: "OpenMusicEventAppViewLambda", targets: ["OpenMusicEventAppViewLambda"]),
]

#if os(macOS)
products.append(contentsOf: [
    .library(name: "OpenMusicEventApp", type: .dynamic, targets: ["OpenMusicEventApp"]),
    .library(name: "OpenMusicEventAppEventViewer", targets: ["OpenMusicEventAppEventViewer"]),
    .library(name: "OpenMusicEventEditors", targets: ["OpenMusicEventEditors"]),
    .library(name: "OpenMusicEventViewers", targets: ["OpenMusicEventViewers"]),
    .library(name: "OpenMusicEventImages", targets: ["OpenMusicEventImages"]),
    .library(name: "OpenMusicEventWhiteLabelApp", targets: ["OpenMusicEventWhiteLabelApp"]),
    .library(name: "LiquidGlassSegmentedPicker", targets: ["LiquidGlassSegmentedPicker"]),
    .library(name: "ScheduleComponents", targets: ["ScheduleComponents"]),
    .library(name: "SwiftUITabFeatures", targets: ["SwiftUITabFeatures"]),
])
#endif

var dependencies: [Package.Dependency] = [
    .package(url: "https://source.woody.fm/swift-composable-forms", branch: "main"),
    .package(url: "https://source.woody.fm/swift-frontmatter-parsing", branch: "main"),
    .package(name: "swift-file-tree", path: "../../swift-packages/swift-file-tree"),
    .package(path: "../../swift-packages/swift-dependencies-http-client"),
    .package(
        name: "swift-composable-atmosphere",
        path: "../../swift-packages/swift-composable-atmosphere",
        traits: ["TCA26"]
    ),
    .package(path: "../composable-atmosphere-constellation"),
    .package(path: "../composable-atmosphere-tangled"),
    .package(url: "https://source.woody.fm/swift-tagged-types-macro", branch: "main"),
    .package(url: "https://source.woody.fm/swift-urlqueryitem-coder", branch: "main"),
    .package(url: "https://source.woody.fm/swift-web-metadata", branch: "main", traits: ["Dependencies"]),
    .package(path: "../swift-dependencies-source-control-client"),
    .package(url: "https://github.com/awslabs/swift-aws-lambda-events.git", from: "1.4.0"),
    .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.22.0"),
    .package(url: "https://github.com/hummingbird-project/hummingbird-lambda.git", from: "2.1.0"),
    .package(url: "https://github.com/pointfreeco/swift-clocks", branch: "clocks-2"),
    .package(url: "https://github.com/pointfreeco/swift-case-paths", branch: "26"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", branch: "26"),
    .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-tagged", from: "0.10.0"),
    .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.0.0"),
    .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.9.0"),
    .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.0.0", traits: ["SQLiteDataTagged"]),
    .package(url: "https://github.com/pointfreeco/swift-structured-queries", exact: "0.32.0", traits: ["StructuredQueriesTagged" /*"LazyInitializationByDefault"*/]),
    .package(path: "/Users/woody/Developer/swift-packages/3rd-party/PointFree/TCA26", traits: ["Dependencies"]),
    .package(url: "https://github.com/apple/swift-crypto", from: "3.0.0"),
    .package(url: "https://github.com/groue/GRDB.swift", from: "7.6.0"),
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.0.0"),
    .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
    .package(url: "https://github.com/apple/swift-http-types", from: "1.4.0"),
    .package(url: "https://github.com/1024jp/GzipSwift", from: "6.0.0"),
    .package(url: "https://github.com/kateinoigakukun/swift-tar", branch: "main"),
    .package(url: "https://github.com/tuist/Noora", from: "0.15.0"),
]

#if os(macOS)
dependencies.append(contentsOf: [
    .package(url: "https://source.skip.tools/skip.git", from: "1.8.6"),
    .package(url: "https://source.skip.tools/skip-fuse-ui.git", from: "1.0.0"),
    .package(name: "skip-sharing", path: skipSharingPath),
    .package(url: "https://github.com/14T/DateRangePicker", branch: "main"),
    .package(url: "https://github.com/omaralbeik/Drops.git", from: "1.7.0"),
])
#endif

var openMusicEventAuthenticationDependencies: [Target.Dependency] = [
    "OpenMusicEventSourceClone",
    "OpenMusicEventComponents",
    .product(name: "ATProto", package: "swift-composable-atmosphere"),
    .product(name: "ATProtoOAuth", package: "swift-composable-atmosphere"),
    .product(name: "ATProtoServer", package: "swift-composable-atmosphere"),
    .product(name: "ComposableArchitecture2", package: "TCA26"),
    .product(name: "ComposableForms", package: "swift-composable-forms"),
    .product(name: "Dependencies", package: "swift-dependencies"),
    .product(name: "HTTPClient", package: "swift-dependencies-http-client"),
    .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
    .product(name: "Sharing", package: "swift-sharing"),
    .product(name: "TCATProtoAuthentication", package: "swift-composable-atmosphere"),
    .product(name: "WebMetadataClient", package: "swift-web-metadata"),
    .product(name: "XRPCClient", package: "swift-composable-atmosphere"),
]

var openMusicEventSourceCloneDependencies: [Target.Dependency] = [
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
    .product(name: "TangledLexicon", package: "composable-atmosphere-tangled"),
    .product(name: "Tagged", package: "swift-tagged"),
    .product(name: "XRPCClient", package: "swift-composable-atmosphere"),
]

#if os(macOS)
openMusicEventAuthenticationDependencies.append(
    .product(name: "SkipSharing", package: "skip-sharing", condition: .when(platforms: [.android]))
)
openMusicEventSourceCloneDependencies.append(
    .product(name: "SkipSharing", package: "skip-sharing", condition: .when(platforms: [.android]))
)
#endif

var targets: [Target] = [
    .target(
        name: "OpenMusicEventAuthentication",
        dependencies: openMusicEventAuthenticationDependencies
    ),
    .target(
        name: "OpenMusicEventComponents"
    ),
    .target(
        name: "OpenMusicEventReleaseTools"
    ),
    .executableTarget(
        name: "OpenMusicEventReleaseCheck",
        dependencies: [
            "OpenMusicEventReleaseTools",
        ]
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
            .product(name: "ATProto", package: "swift-composable-atmosphere"),
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
        plugins: skipstonePlugins
    ),
    .target(
        name: "OpenMusicEventLexicon",
        dependencies: [
            "OpenMusicEventTimeZones",
            .product(name: "ATProto", package: "swift-composable-atmosphere"),
            .product(name: "CasePaths", package: "swift-case-paths"),
            .product(name: "Lexicon", package: "swift-composable-atmosphere"),
            .product(name: "LexiconSQLiteData", package: "swift-composable-atmosphere"),
            .product(name: "SQLiteData", package: "sqlite-data"),
            .product(name: "StructuredQueriesSQLite", package: "swift-structured-queries"),
            .product(name: "Tagged", package: "swift-tagged"),
        ]
    ),
    .target(
        name: "OpenMusicEventRouting",
        dependencies: [
            .product(name: "Tagged", package: "swift-tagged"),
        ]
    ),
    .target(
        name: "OpenMusicEventAppViewServer",
        dependencies: [
            "OpenMusicEventRouting",
            .product(name: "Hummingbird", package: "hummingbird"),
        ],
        resources: [
            .copy("Resources/Site"),
            .copy("Resources/WellKnown"),
        ]
    ),
    .executableTarget(
        name: "OpenMusicEventAppView",
        dependencies: [
            "OpenMusicEventAppViewServer",
        ]
    ),
    .executableTarget(
        name: "OpenMusicEventAppViewLambda",
        dependencies: [
            "OpenMusicEventAppViewServer",
            .product(name: "AWSLambdaEvents", package: "swift-aws-lambda-events"),
            .product(name: "HummingbirdLambda", package: "hummingbird-lambda"),
        ]
    ),
    .target(
        name: "OpenMusicEventSourceEditing",
        dependencies: [
            "ErrorHandling",
            "OpenMusicEventLexicon",
            "OpenMusicEventSource",
            "OpenMusicEventSourceClone",
            "SourceEditing",
            .product(name: "ATProto", package: "swift-composable-atmosphere"),
            .product(name: "ATProtoOAuth", package: "swift-composable-atmosphere"),
            .product(name: "ComposableAtmosphereConstellation", package: "composable-atmosphere-constellation"),
            .product(name: "ComposableArchitecture2", package: "TCA26"),
            .product(name: "CustomDump", package: "swift-custom-dump"),
            .product(name: "Dependencies", package: "swift-dependencies"),
            .product(name: "FileTree", package: "swift-file-tree"),
            .product(name: "GRDB", package: "GRDB.swift"),
            .product(name: "Gzip", package: "gzipswift"),
            .product(name: "HTTPClient", package: "swift-dependencies-http-client"),
            .product(name: "HTTPTypes", package: "swift-http-types"),
            .product(name: "Lexicon", package: "swift-composable-atmosphere"),
            .product(name: "SourceControlClient", package: "swift-dependencies-source-control-client"),
            .product(name: "Sharing", package: "swift-sharing"),
            .product(name: "SQLiteData", package: "sqlite-data"),
            .product(name: "TangledLexicon", package: "composable-atmosphere-tangled"),
            .product(name: "TangledXRPC", package: "composable-atmosphere-tangled"),
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
        dependencies: openMusicEventSourceCloneDependencies
    ),
    .target(
        name: "OpenMusicEventTimeZones",
        dependencies: [
            .product(name: "SQLiteData", package: "sqlite-data"),
        ],
        plugins: skipstonePlugins
    ),
    .executableTarget(
        name: "OpenMusicEventCLI",
        dependencies: [
            "OpenMusicEventAuthentication",
            "OpenMusicEventDatabase",
            "OpenMusicEventLexicon",
            "OpenMusicEventSource",
            "OpenMusicEventSourceClone",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            .product(name: "ATProto", package: "swift-composable-atmosphere"),
            .product(name: "ATProtoOAuth", package: "swift-composable-atmosphere"),
            .product(name: "Dependencies", package: "swift-dependencies"),
            .product(name: "FileTree", package: "swift-file-tree"),
            .product(name: "HTTPClient", package: "swift-dependencies-http-client"),
            .product(name: "Noora", package: "Noora"),
            .product(name: "TangledLexicon", package: "composable-atmosphere-tangled"),
            .product(name: "TangledXRPC", package: "composable-atmosphere-tangled"),
            .product(name: "XRPCClient", package: "swift-composable-atmosphere"),
        ]
    ),
    .testTarget(
        name: "BlueskyActorCacheTests",
        dependencies: [
            "BlueskyActorCache",
            .product(name: "ATProto", package: "swift-composable-atmosphere"),
            .product(name: "CustomDump", package: "swift-custom-dump"),
            .product(name: "Dependencies", package: "swift-dependencies"),
            .product(name: "HTTPClient", package: "swift-dependencies-http-client"),
            .product(name: "HTTPTypes", package: "swift-http-types"),
            .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
            .product(name: "SQLiteData", package: "sqlite-data"),
            .product(name: "XRPCClient", package: "swift-composable-atmosphere"),
        ]
    ),
    .testTarget(
        name: "OpenMusicEventCLITests",
        dependencies: [
            "OpenMusicEventCLI",
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
        name: "OpenMusicEventLexiconTests",
        dependencies: [
            "OpenMusicEventLexicon",
            .product(name: "ATProto", package: "swift-composable-atmosphere"),
            .product(name: "Lexicon", package: "swift-composable-atmosphere"),
        ]
    ),
    .testTarget(
        name: "OpenMusicEventReleaseToolsTests",
        dependencies: [
            "OpenMusicEventReleaseTools",
            .product(name: "CustomDump", package: "swift-custom-dump"),
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
            .product(name: "Dependencies", package: "swift-dependencies"),
        ],
        resources: [
            .copy("Fixtures")
        ]
    ),
    .testTarget(
        name: "OpenMusicEventSourceEditingTests",
        dependencies: [
            "OpenMusicEventSourceEditing",
            .product(name: "CustomDump", package: "swift-custom-dump"),
            .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
            .product(
                name: "SourceControlClient",
                package: "swift-dependencies-source-control-client"
            ),
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
        name: "OpenMusicEventRoutingTests",
        dependencies: [
            "OpenMusicEventRouting",
            .product(name: "CustomDump", package: "swift-custom-dump"),
        ]
    ),
    .testTarget(
        name: "OpenMusicEventAppViewServerTests",
        dependencies: [
            "OpenMusicEventAppViewServer",
            .product(name: "AWSLambdaEvents", package: "swift-aws-lambda-events"),
            .product(name: "HummingbirdLambda", package: "hummingbird-lambda"),
            .product(name: "HummingbirdLambdaTesting", package: "hummingbird-lambda"),
            .product(name: "HummingbirdTesting", package: "hummingbird"),
        ],
        resources: [
            .copy("Resources/Site"),
            .copy("Resources/WellKnown"),
        ]
    ),
]

#if os(macOS)
targets.append(contentsOf: [
    .target(
        name: "OpenMusicEventApp",
        dependencies: [
            "BlueskyActorCache",
            "ErrorHandling",
            "OpenMusicEventAppEventViewer",
            "OpenMusicEventAuthentication",
            "OpenMusicEventComponents",
            "OpenMusicEventDatabase",
            "OpenMusicEventImages",
            "OpenMusicEventLexicon",
            "OpenMusicEventSource",
            "OpenMusicEventSourceClone",
            "OpenMusicEventSourceEditing",
            "OpenMusicEventTimeZones",
            "OpenMusicEventWhiteLabel",
            "SourceEditing",
            .product(name: "ComposableArchitecture2", package: "TCA26"),
            .product(name: "Dependencies", package: "swift-dependencies"),
            .product(name: "Drops", package: "Drops", condition: .when(platforms: [.iOS])),
            .product(name: "FileTree", package: "swift-file-tree"),
            .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
            .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
            .product(name: "SourceControlClient", package: "swift-dependencies-source-control-client"),
            .product(name: "SourceControlClientGit", package: "swift-dependencies-source-control-client", condition: .when(platforms: [.iOS, .macOS])),
            .product(name: "SQLiteData", package: "sqlite-data"),
            .product(name: "TangledLexicon", package: "composable-atmosphere-tangled"),
            .product(name: "TangledXRPC", package: "composable-atmosphere-tangled"),
            .product(name: "XRPCClient", package: "swift-composable-atmosphere"),
        ],
        resources: [.process("Resources")],
        plugins: [.plugin(name: "skipstone", package: "skip")]
    ),
    .target(
        name: "OpenMusicEventAppEventViewer",
        dependencies: [
            "BlueskyActorCache",
            "ErrorHandling",
            "OpenMusicEventComponents",
            .target(name: "LiquidGlassSegmentedPicker", condition: .when(platforms: [.iOS, .macOS])),
            "OpenMusicEventDatabase",
            "OpenMusicEventEditors",
            "OpenMusicEventImages",
            "OpenMusicEventLexicon",
            "OpenMusicEventAuthentication",
            "OpenMusicEventSourceClone",
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
            "SwiftUITabFeatures",
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
            "OpenMusicEventComponents",
            "OpenMusicEventDatabase",
            "OpenMusicEventLexicon",
            .product(name: "Dependencies", package: "swift-dependencies"),
        ],
        plugins: [.plugin(name: "skipstone", package: "skip")]
    ),
    .target(
        name: "LiquidGlassSegmentedPicker",
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
            .product(name: "ATProto", package: "swift-composable-atmosphere"),
            .product(name: "ComposableArchitecture2", package: "TCA26"),
            .product(name: "Dependencies", package: "swift-dependencies"),
            .product(name: "HTTPClient", package: "swift-dependencies-http-client"),
            .product(name: "SQLiteData", package: "sqlite-data"),
            .product(name: "XRPCClient", package: "swift-composable-atmosphere"),
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
    .testTarget(
        name: "OpenMusicEventAuthenticationTests",
        dependencies: [
            "OpenMusicEventAuthentication",
            .product(name: "Clocks", package: "swift-clocks"),
            .product(name: "ComposableArchitecture2", package: "TCA26"),
            .product(name: "CustomDump", package: "swift-custom-dump"),
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
            "OpenMusicEventWhiteLabel",
            "OpenMusicEventSourceEditing",
            .product(name: "ATProto", package: "swift-composable-atmosphere"),
            .product(name: "Clocks", package: "swift-clocks"),
            .product(name: "ComposableArchitecture2", package: "TCA26"),
            .product(name: "CustomDump", package: "swift-custom-dump"),
            .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
            .product(name: "HTTPClient", package: "swift-dependencies-http-client"),
            .product(name: "HTTPTypes", package: "swift-http-types"),
            .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            .product(name: "SnapshotTestingCustomDump", package: "swift-snapshot-testing"),
            .product(name: "SourceControlClient", package: "swift-dependencies-source-control-client"),
            .product(name: "SQLiteData", package: "sqlite-data"),
            .product(name: "TangledLexicon", package: "composable-atmosphere-tangled"),
            .product(name: "XRPCClient", package: "swift-composable-atmosphere"),
        ]
    ),
    .testTarget(
        name: "OpenMusicEventEditorsTests",
        dependencies: [
            "OpenMusicEventEditors",
        ]
    ),
    .testTarget(
        name: "OpenMusicEventViewersTests",
        dependencies: [
            "OpenMusicEventViewers",
        ]
    ),
    .testTarget(
        name: "OpenMusicEventImagesTests",
        dependencies: [
            "OpenMusicEventImages",
            .product(name: "CustomDump", package: "swift-custom-dump"),
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
            .product(name: "HTTPClient", package: "swift-dependencies-http-client"),
            .product(name: "HTTPTypes", package: "swift-http-types"),
            .product(name: "SQLiteData", package: "sqlite-data"),
            .product(name: "XRPCClient", package: "swift-composable-atmosphere"),
        ]
    ),
    .testTarget(
        name: "ScheduleComponentsTests",
        dependencies: [
            "ScheduleComponents",
        ]
    ),
    .testTarget(
        name: "SwiftUITabFeaturesTests",
        dependencies: [
            "SwiftUITabFeatures",
        ]
    ),
])
#endif

let package = Package(
    name: "open-music-event",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v15)],
    products: products,
    dependencies: dependencies,
    targets: targets
)
