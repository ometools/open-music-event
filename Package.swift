// swift-tools-version: 6.1
// This is a Skip (https://skip.dev) package.
import Foundation
import PackageDescription

let isOMEAppView = ProcessInfo.processInfo.environment["OME_APPVIEW"] == "1"
let isAndroidAppBuild = ProcessInfo.processInfo.environment["OME_ANDROID_APP_BUILD"] == "1"
let grdbPackageName = isAndroidAppBuild ? "grdb-sqlcipher" : "GRDB.swift"
let sharingTraits: Set<Package.Dependency.Trait> =
    isAndroidAppBuild ? [] : [.defaults]
let sqliteDataTraits: Set<Package.Dependency.Trait> =
    isAndroidAppBuild
    ? ["SQLiteDataTagged", "GRDBCIPHER"]
    : [.defaults, "SQLiteDataTagged", "GRDBCIPHER"]
let tcaTraits: Set<Package.Dependency.Trait> =
    isAndroidAppBuild
    ? ["Dependencies"]
    : [.defaults, "Dependencies"]
let composableAtmosphereTraits: Set<Package.Dependency.Trait> =
    isAndroidAppBuild
    ? ["TCA26", "SkipAndroidBridge"]
    : [.defaults, "TCA26"]
let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
func packagePath(_ relativePath: String) -> String {
    URL(fileURLWithPath: relativePath, relativeTo: packageDirectory)
        .standardizedFileURL
        .path
}
func workspacePackagePath(_ name: String) -> String {
    let workspaceParent = packageDirectory.deletingLastPathComponent()
    let candidates = [
        workspaceParent.appendingPathComponent(name),
        workspaceParent.appendingPathComponent("worktrees").appendingPathComponent(name),
    ]
    return candidates.first { FileManager.default.fileExists(atPath: $0.path) }?.path
        ?? candidates[0].path
}
#if os(macOS)
let skipstonePlugins: [Target.PluginUsage] = [.plugin(name: "skipstone", package: "skip")]
let skipRootPath = ProcessInfo.processInfo.environment["SKIPLOCAL"].map {
    URL(fileURLWithPath: $0).deletingLastPathComponent()
}
let skipDependency: Package.Dependency
let skipFuseUIDependency: Package.Dependency
if let skipRootPath {
    skipDependency = .package(name: "skip", path: skipRootPath.appendingPathComponent("skip").path)
    skipFuseUIDependency = .package(
        name: "skip-fuse-ui",
        path: skipRootPath.appendingPathComponent("skip-fuse-ui").path
    )
} else {
    skipDependency = .package(url: "https://source.skip.tools/skip.git", from: "1.8.6")
    skipFuseUIDependency = .package(url: "https://source.skip.tools/skip-fuse-ui.git", from: "1.0.0")
}
let skipSharingPath = [
    ProcessInfo.processInfo.environment["SKIPLOCAL"].map {
        URL(fileURLWithPath: $0)
            .deletingLastPathComponent()
            .appendingPathComponent("skip-sharing")
            .path
    },
    "../../swift-packages/3rd-party/skip/skip-sharing",
    "../../../swift-packages/3rd-party/skip/skip-sharing",
].compactMap { $0 }
    .map(packagePath)
    .first { FileManager.default.fileExists(atPath: $0) }
    ?? packagePath("../../swift-packages/3rd-party/skip/skip-sharing")
let skipAndroidBridgePath = [
    ProcessInfo.processInfo.environment["SKIPLOCAL"].map {
        URL(fileURLWithPath: $0)
            .deletingLastPathComponent()
            .appendingPathComponent("skip-android-bridge")
            .path
    },
    "../../swift-packages/3rd-party/skip/skip-android-bridge",
    "../../../swift-packages/3rd-party/skip/skip-android-bridge",
].compactMap { $0 }
    .map(packagePath)
    .first { FileManager.default.fileExists(atPath: $0) }
    ?? packagePath("../../swift-packages/3rd-party/skip/skip-android-bridge")
#else
let skipstonePlugins: [Target.PluginUsage] = []
#endif

var products: [Product] = [
    .executable(name: "ome", targets: ["OpenMusicEventCLI"]),
    .executable(name: "ome-release-check", targets: ["OpenMusicEventReleaseCheck"]),
    .library(name: "BlueskyActorCache", targets: ["BlueskyActorCache"]),
    .library(name: "OpenMusicEventAuthentication", targets: ["OpenMusicEventAuthentication"]),
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
]

if !isAndroidAppBuild {
    products.append(contentsOf: [
        .library(name: "OpenMusicEventAppViewServer", targets: ["OpenMusicEventAppViewServer"]),
        .executable(name: "OpenMusicEventAppView", targets: ["OpenMusicEventAppView"]),
        .executable(name: "OpenMusicEventAppViewLambda", targets: ["OpenMusicEventAppViewLambda"]),
    ])
}

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
    .package(
        url: "https://source.woody.fm/composable-calendar-events",
        branch: "main"
    ),
    isAndroidAppBuild
        ? .package(name: "swift-composable-forms", path: workspacePackagePath("swift-composable-forms-android"))
        : .package(url: "https://source.woody.fm/swift-composable-forms", branch: "main"),
    .package(url: "https://source.woody.fm/swift-frontmatter-parsing", branch: "main"),
    .package(name: "swift-file-tree", path: "../../swift-packages/swift-file-tree"),
    .package(
        name: "swift-composable-workspace",
        path: packagePath("../../swift-packages/swift-composable-workspace")
    ),
    .package(path: "../../swift-packages/swift-dependencies-http-client"),
    isAndroidAppBuild
        ? .package(
            name: "swift-composable-atmosphere",
            path: workspacePackagePath("swift-composable-atmosphere"),
            traits: composableAtmosphereTraits
        )
        : .package(
            name: "swift-composable-atmosphere",
            path: packagePath("../../swift-packages/swift-composable-atmosphere"),
            traits: ["TCA26"]
        ),
    .package(name: "composable-atmosphere-constellation", path: workspacePackagePath("composable-atmosphere-constellation")),
    .package(name: "composable-atmosphere-tangled", path: workspacePackagePath("composable-atmosphere-tangled")),
    .package(url: "https://source.woody.fm/swift-tagged-types-macro", branch: "main"),
    .package(url: "https://source.woody.fm/swift-urlqueryitem-coder", branch: "main"),
    .package(url: "https://source.woody.fm/swift-web-metadata", branch: "main", traits: ["Dependencies"]),
    .package(path: workspacePackagePath("swift-dependencies-source-control-client")),
    .package(url: "https://github.com/pointfreeco/swift-clocks", branch: "clocks-2"),
    .package(url: "https://github.com/pointfreeco/swift-case-paths", branch: "26"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", branch: "26"),
    .package(
        name: "swift-sharing",
        path: workspacePackagePath("swift-sharing"),
        traits: sharingTraits
    ),
    .package(url: "https://github.com/pointfreeco/swift-tagged", from: "0.10.0"),
    .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.0.0"),
    .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.9.0"),
    isAndroidAppBuild
        ? .package(name: "sqlite-data", path: workspacePackagePath("sqlite-data"), traits: sqliteDataTraits)
        : .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.0.0", traits: ["SQLiteDataTagged"]),
    isAndroidAppBuild
        ? .package(name: "swift-structured-queries", path: workspacePackagePath("swift-structured-queries"), traits: ["StructuredQueriesTagged"])
        : .package(url: "https://github.com/pointfreeco/swift-structured-queries", exact: "0.32.0", traits: ["StructuredQueriesTagged"]),
    isAndroidAppBuild
        ? .package(
            name: "TCA26",
            path: workspacePackagePath("TCA26"),
            traits: tcaTraits
        )
        : .package(
            name: "TCA26",
            path: packagePath("../../swift-packages/3rd-party/PointFree/TCA26"),
            traits: ["Dependencies"]
        ),
    .package(url: "https://github.com/apple/swift-crypto", from: "3.0.0"),
    isAndroidAppBuild
        ? .package(url: "https://github.com/swift-everywhere/grdb-sqlcipher.git", from: "7.5.0", traits: ["GRDBCIPHER"])
        : .package(url: "https://github.com/groue/GRDB.swift", from: "7.6.0"),
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.0.0"),
    .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
    .package(url: "https://github.com/apple/swift-http-types", from: "1.4.0"),
    .package(url: "https://github.com/1024jp/GzipSwift", from: "6.0.0"),
    .package(url: "https://github.com/kateinoigakukun/swift-tar", branch: "main"),
    .package(url: "https://github.com/tuist/Noora", from: "0.15.0"),
]

if !isAndroidAppBuild {
    dependencies.append(contentsOf: [
        .package(url: "https://github.com/awslabs/swift-aws-lambda-events.git", from: "1.4.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.22.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird-lambda.git", from: "2.1.0"),
    ])
}

#if os(macOS)
dependencies.append(contentsOf: [
    skipDependency,
    skipFuseUIDependency,
    .package(name: "skip-android-bridge", path: skipAndroidBridgePath),
    .package(name: "skip-sharing", path: skipSharingPath),
    .package(url: "https://github.com/14T/DateRangePicker", branch: "main"),
    .package(url: "https://github.com/omaralbeik/Drops.git", from: "1.7.0"),
])
#endif

var openMusicEventAuthenticationDependencies: [Target.Dependency] = [
    "BlueskyActorCache",
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
    .product(name: "SQLiteData", package: "sqlite-data"),
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
openMusicEventAuthenticationDependencies.append(contentsOf: [
    .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
    .product(name: "SkipSharing", package: "skip-sharing", condition: .when(platforms: [.android])),
])
openMusicEventSourceCloneDependencies.append(
    .product(name: "SkipSharing", package: "skip-sharing", condition: .when(platforms: [.android]))
)
#endif

var openMusicEventComponentsDependencies: [Target.Dependency] = []
var openMusicEventTimeZonesDependencies: [Target.Dependency] = [
    .product(name: "SQLiteData", package: "sqlite-data"),
]
var openMusicEventWhiteLabelDependencies: [Target.Dependency] = [
    "OpenMusicEventLexicon",
    .product(name: "Dependencies", package: "swift-dependencies"),
]
var scheduleComponentsDependencies: [Target.Dependency] = [
    .product(name: "Dependencies", package: "swift-dependencies"),
]

#if os(macOS)
openMusicEventComponentsDependencies.append(
    .product(name: "SkipFuseUI", package: "skip-fuse-ui")
)
openMusicEventTimeZonesDependencies.append(
    .product(name: "SkipFuseUI", package: "skip-fuse-ui")
)
openMusicEventWhiteLabelDependencies.append(
    .product(name: "SkipFuseUI", package: "skip-fuse-ui")
)
scheduleComponentsDependencies.append(
    .product(name: "SkipFuseUI", package: "skip-fuse-ui")
)
#endif

var targets: [Target] = [
    .target(
        name: "OpenMusicEventAuthentication",
        dependencies: openMusicEventAuthenticationDependencies,
        plugins: skipstonePlugins
    ),
    .target(
        name: "OpenMusicEventComponents",
        dependencies: openMusicEventComponentsDependencies,
        plugins: skipstonePlugins
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
            .product(name: "GRDB", package: grdbPackageName),
            .product(name: "SQLiteData", package: "sqlite-data"),
        ]
    ),
    .target(
        name: "OpenMusicEventDatabase",
        dependencies: [
            "OpenMusicEventLexicon",
            "OpenMusicEventSource",
            "OpenMusicEventSourceClone",
            "OpenMusicEventSourceEditing",
            "OpenMusicEventTimeZones",
            "SourceEditing",
            .product(name: "ATProto", package: "swift-composable-atmosphere"),
            .product(name: "Dependencies", package: "swift-dependencies"),
            .product(name: "HTTPClient", package: "swift-dependencies-http-client"),
            .product(name: "SourceControlClient", package: "swift-dependencies-source-control-client"),
            .product(name: "SQLiteData", package: "sqlite-data"),
            .product(name: "Tagged", package: "swift-tagged"),
        ]
    ),
    .target(
        name: "OpenMusicEventWhiteLabel",
        dependencies: openMusicEventWhiteLabelDependencies,
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
            .product(name: "ComposableAuthoring", package: "swift-composable-workspace"),
            .product(name: "ComposableAuthoringWorkspace", package: "swift-composable-workspace"),
            .product(name: "ComposableWorkspace", package: "swift-composable-workspace"),
            .product(name: "CustomDump", package: "swift-custom-dump"),
            .product(name: "Dependencies", package: "swift-dependencies"),
            .product(name: "FileTree", package: "swift-file-tree"),
            .product(name: "GRDB", package: grdbPackageName),
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
        dependencies: openMusicEventTimeZonesDependencies,
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
            .product(name: "GRDB", package: grdbPackageName),
        ]
    ),
    .testTarget(
        name: "OpenMusicEventDatabaseTests",
        dependencies: [
            "OpenMusicEventDatabase",
            "SourceEditing",
            .product(name: "ATProto", package: "swift-composable-atmosphere"),
            .product(name: "CustomDump", package: "swift-custom-dump"),
            .product(name: "GRDB", package: grdbPackageName),
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
            "OpenMusicEventDatabase",
            "OpenMusicEventLexicon",
            "OpenMusicEventSource",
            "OpenMusicEventSourceEditing",
            "SourceEditing",
            .product(name: "CustomDump", package: "swift-custom-dump"),
            .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
            .product(name: "FileTree", package: "swift-file-tree"),
            .product(name: "GRDB", package: grdbPackageName),
            .product(name: "SQLiteData", package: "sqlite-data"),
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
]

if !isAndroidAppBuild {
    targets.append(contentsOf: [
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
            dependencies: ["OpenMusicEventAppViewServer"]
        ),
        .executableTarget(
            name: "OpenMusicEventAppViewLambda",
            dependencies: [
                "OpenMusicEventAppViewServer",
                .product(name: "AWSLambdaEvents", package: "swift-aws-lambda-events"),
                .product(name: "HummingbirdLambda", package: "hummingbird-lambda"),
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
    ])
}

#if os(macOS)
var openMusicEventAppDependencies: [Target.Dependency] = [
    "BlueskyActorCache",
    .product(name: "ComposableCalendarEvents", package: "composable-calendar-events"),
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
    .product(name: "ComposableAuthoring", package: "swift-composable-workspace"),
    .product(name: "ComposableAuthoringWorkspace", package: "swift-composable-workspace"),
    .product(name: "ComposableArchitecture2", package: "TCA26"),
    .product(name: "ComposableWorkspace", package: "swift-composable-workspace"),
    .product(name: "Dependencies", package: "swift-dependencies"),
    .product(name: "Drops", package: "Drops", condition: .when(platforms: [.iOS])),
    .product(name: "FileTree", package: "swift-file-tree"),
    .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
    .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
    .product(name: "SourceControlClient", package: "swift-dependencies-source-control-client"),
    .product(name: "SQLiteData", package: "sqlite-data"),
    .product(name: "TangledLexicon", package: "composable-atmosphere-tangled"),
    .product(name: "TangledXRPC", package: "composable-atmosphere-tangled"),
    .product(name: "XRPCClient", package: "swift-composable-atmosphere"),
]

if !isAndroidAppBuild {
    openMusicEventAppDependencies.append(
        .product(
            name: "SourceControlClientGit",
            package: "swift-dependencies-source-control-client",
            condition: .when(platforms: [.iOS, .macOS])
        )
    )
}

targets.append(contentsOf: [
    .target(
        name: "OpenMusicEventApp",
        dependencies: openMusicEventAppDependencies,
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
            .product(name: "ComposableAuthoring", package: "swift-composable-workspace"),
            .product(name: "ComposableWorkspace", package: "swift-composable-workspace"),
            .product(name: "ComposableForms", package: "swift-composable-forms"),
            .product(name: "DateRangePicker", package: "DateRangePicker", condition: .when(platforms: [.iOS])),
            .product(name: "Dependencies", package: "swift-dependencies"),
            .product(name: "GRDB", package: grdbPackageName),
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
    .target(name: "LiquidGlassSegmentedPicker"),
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
        dependencies: scheduleComponentsDependencies,
        plugins: [.plugin(name: "skipstone", package: "skip")]
    ),
    .target(
        name: "SwiftUITabFeatures",
        dependencies: [
            "OpenMusicEventComponents",
            .product(name: "Tagged", package: "swift-tagged"),
            .product(name: "CustomDump", package: "swift-custom-dump")
        ],
        plugins: [.plugin(name: "skipstone", package: "skip")]
    ),
    .testTarget(
        name: "OpenMusicEventAuthenticationTests",
        dependencies: [
            "BlueskyActorCache",
            "OpenMusicEventAuthentication",
            .product(name: "Clocks", package: "swift-clocks"),
            .product(name: "ComposableArchitecture2", package: "TCA26"),
            .product(name: "CustomDump", package: "swift-custom-dump"),
            .product(name: "Dependencies", package: "swift-dependencies"),
            .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
            .product(name: "SQLiteData", package: "sqlite-data"),
            .product(name: "TCATProtoAuthentication", package: "swift-composable-atmosphere"),
            .product(name: "WebMetadataClient", package: "swift-web-metadata"),
        ]
    ),
    .testTarget(
        name: "OpenMusicEventAppTests",
        dependencies: [
            "BlueskyActorCache",
            .product(name: "ComposableCalendarEvents", package: "composable-calendar-events"),
            "ErrorHandling",
            "OpenMusicEventApp",
            "OpenMusicEventAuthentication",
            "OpenMusicEventImages",
            "OpenMusicEventLexicon",
            "OpenMusicEventViewers",
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
        ],
        exclude: ["__Snapshots__"]
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
        name: "OpenMusicEventComponentsTests",
        dependencies: [
            "OpenMusicEventComponents",
            .product(name: "CustomDump", package: "swift-custom-dump"),
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
            .product(name: "SourceControlClient", package: "swift-dependencies-source-control-client"),
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

if isOMEAppView {
    products = [
        .library(
            name: "OpenMusicEventAppViewServer",
            targets: ["OpenMusicEventAppViewServer"]
        ),
        .executable(
            name: "OpenMusicEventAppView",
            targets: ["OpenMusicEventAppView"]
        ),
        .executable(
            name: "OpenMusicEventAppViewLambda",
            targets: ["OpenMusicEventAppViewLambda"]
        ),
    ]
    dependencies = [
        .package(
            url: "https://github.com/awslabs/swift-aws-lambda-events.git",
            from: "1.4.0"
        ),
        .package(
            url: "https://github.com/hummingbird-project/hummingbird.git",
            from: "2.22.0"
        ),
        .package(
            url: "https://github.com/hummingbird-project/hummingbird-lambda.git",
            from: "2.1.0"
        ),
        .package(
            url: "https://github.com/pointfreeco/swift-tagged",
            from: "0.10.0"
        ),
    ]

    let appViewTargetNames: Set<String> = [
        "OpenMusicEventAppView",
        "OpenMusicEventAppViewLambda",
        "OpenMusicEventAppViewServer",
        "OpenMusicEventAppViewServerTests",
        "OpenMusicEventRouting",
    ]
    targets = targets.filter { appViewTargetNames.contains($0.name) }
}

let package = Package(
    name: "open-music-event",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v15)],
    products: products,
    dependencies: dependencies,
    targets: targets
)
