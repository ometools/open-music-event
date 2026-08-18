// swift-tools-version: 6.1
// This is a Skip (https://skip.dev) package.
import Foundation
import PackageDescription

// Build selection

enum PackageBuild: Equatable {
    case app
    case androidApp
    case appView
}

// OME_APPVIEW selects the standalone server graph. OME_ANDROID_APP_BUILD
// selects Android-specific package variants. With neither set, SwiftPM exposes
// the complete app development graph, including the AppView targets.
let environment = ProcessInfo.processInfo.environment
let packageBuild: PackageBuild = {
    if environment["OME_APPVIEW"] == "1" {
        return .appView
    }
    if environment["OME_ANDROID_APP_BUILD"] == "1" {
        return .androidApp
    }
    return .app
}()

let isAndroidAppBuild = packageBuild == .androidApp
let grdbPackageName = isAndroidAppBuild ? "grdb-sqlcipher" : "GRDB.swift"
let sharingTraits: Set<Package.Dependency.Trait> =
    isAndroidAppBuild ? [] : [.defaults]
let sqliteDataTraits: Set<Package.Dependency.Trait> =
    isAndroidAppBuild
    ? ["SQLiteDataTagged", "GRDBCIPHER"]
    : [.defaults, "SQLiteDataTagged"]
let tcaTraits: Set<Package.Dependency.Trait> =
    isAndroidAppBuild
    ? ["Dependencies"]
    : [.defaults, "Dependencies"]
let composableAtmosphereTraits: Set<Package.Dependency.Trait> =
    isAndroidAppBuild
    ? ["TCA26", "SkipAndroidBridge"]
    : [.defaults, "TCA26"]

// Build-specific dependency variants

let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
func packagePath(_ relativePath: String) -> String {
    URL(fileURLWithPath: relativePath, relativeTo: packageDirectory)
        .standardizedFileURL
        .path
}
func workspacePackagePath(_ name: String) -> String {
    let workspaceContainer = packageDirectory.deletingLastPathComponent()
    let workspaceRoot = workspaceContainer.lastPathComponent == "worktrees"
        ? workspaceContainer.deletingLastPathComponent()
        : workspaceContainer
    let candidates: [URL]
    if isAndroidAppBuild {
        candidates = [
            workspaceRoot.appendingPathComponent("worktrees").appendingPathComponent(name),
            workspaceContainer.appendingPathComponent(name),
            workspaceRoot.appendingPathComponent(name),
        ]
    } else {
        candidates = [
            workspaceRoot.appendingPathComponent(name),
            workspaceContainer.appendingPathComponent(name),
            workspaceRoot.appendingPathComponent("worktrees").appendingPathComponent(name),
        ]
    }
    return candidates.first { FileManager.default.fileExists(atPath: $0.path) }?.path
        ?? candidates[0].path
}
let tca26Dependency: Package.Dependency = {
    if let path = environment["OME_TCA26_PATH"] {
        return .package(
            name: "TCA26",
            path: packagePath(path),
            traits: ["Dependencies"]
        )
    }
    if isAndroidAppBuild {
        return .package(
            name: "TCA26",
            path: workspacePackagePath("TCA26"),
            traits: tcaTraits
        )
    }
    return .package(
        name: "TCA26",
        path: packagePath(".build/checkouts/TCA26"),
        traits: ["Dependencies"]
    )
}()
let appViewComposableCalendarEventsDependency: Package.Dependency
if let composableCalendarEventsPath = environment["OME_COMPOSABLE_CALENDAR_EVENTS_PATH"] {
    appViewComposableCalendarEventsDependency = .package(
        name: "composable-calendar-events",
        path: composableCalendarEventsPath
    )
} else {
    appViewComposableCalendarEventsDependency = .package(
        url: "https://source.woody.fm/composable-calendar-events",
        branch: "main"
    )
}
let appViewComposableAtmosphereDependency: Package.Dependency
if let composableAtmospherePath = environment["OME_COMPOSABLE_ATMOSPHERE_PATH"] {
    appViewComposableAtmosphereDependency = .package(
        name: "swift-composable-atmosphere",
        path: composableAtmospherePath,
        traits: []
    )
} else {
    appViewComposableAtmosphereDependency = .package(
        url: "https://source.woody.fm/swift-composable-atmosphere",
        branch: "main",
        traits: []
    )
}
let composableNotificationsDependency: Package.Dependency = {
    if let path = environment["OME_COMPOSABLE_NOTIFICATIONS_PATH"] {
        return .package(
            name: "swift-composable-notifications",
            path: packagePath(path)
        )
    }
    return .package(
        url: "https://source.woody.fm/swift-composable-notifications",
        branch: "main"
    )
}()
let skipstonePlugins: [Target.PluginUsage] = packageBuild == .appView
    ? []
    : [.plugin(name: "skipstone", package: "skip")]
let skipRootPath = environment["SKIPLOCAL"].map {
    URL(fileURLWithPath: $0).deletingLastPathComponent()
}
let skipDependency: Package.Dependency
let skipFuseUIDependency: Package.Dependency
let skipKitDependency: Package.Dependency
if let skipRootPath {
    skipDependency = .package(name: "skip", path: skipRootPath.appendingPathComponent("skip").path)
    skipFuseUIDependency = .package(
        name: "skip-fuse-ui",
        path: skipRootPath.appendingPathComponent("skip-fuse-ui").path
    )
    let skipKitPath = skipRootPath.appendingPathComponent("skip-kit").path
    skipKitDependency = FileManager.default.fileExists(atPath: skipKitPath)
        ? .package(name: "skip-kit", path: skipKitPath)
        : .package(url: "https://source.skip.tools/skip-kit.git", from: "1.0.0")
} else {
    skipDependency = .package(url: "https://source.skip.tools/skip.git", from: "1.8.6")
    skipFuseUIDependency = .package(url: "https://source.skip.tools/skip-fuse-ui.git", from: "1.0.0")
    skipKitDependency = .package(url: "https://source.skip.tools/skip-kit.git", from: "1.0.0")
}
let skipSharingDependency: Package.Dependency
let skipAndroidBridgeDependency: Package.Dependency
let skipKeychainDependency: Package.Dependency? = isAndroidAppBuild
    ? .package(url: "https://source.skip.tools/skip-keychain.git", "0.3.2"..<"2.0.0")
    : nil
if let skipRootPath {
    skipSharingDependency = .package(
        name: "skip-sharing",
        path: skipRootPath.appendingPathComponent("skip-sharing").path
    )
    skipAndroidBridgeDependency = .package(
        name: "skip-android-bridge",
        path: skipRootPath.appendingPathComponent("skip-android-bridge").path
    )
} else {
    let skipSharingPath = [
        "../../swift-packages/3rd-party/skip/skip-sharing",
        "../../../swift-packages/3rd-party/skip/skip-sharing",
    ]
        .map(packagePath)
        .first { FileManager.default.fileExists(atPath: $0) }
        ?? packagePath("../../swift-packages/3rd-party/skip/skip-sharing")
    let skipAndroidBridgePath = [
        "../../swift-packages/3rd-party/skip/skip-android-bridge",
        "../../../swift-packages/3rd-party/skip/skip-android-bridge",
    ]
        .map(packagePath)
        .first { FileManager.default.fileExists(atPath: $0) }
        ?? packagePath("../../swift-packages/3rd-party/skip/skip-android-bridge")
    skipSharingDependency = .package(name: "skip-sharing", path: skipSharingPath)
    skipAndroidBridgeDependency = isAndroidAppBuild
        ? .package(name: "skip-android-bridge", path: skipAndroidBridgePath)
        : .package(url: "https://source.skip.tools/skip-android-bridge.git", from: "0.6.1")
}

// Products

let applicationProducts: [Product] = [
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
    .library(name: "OpenMusicEventApp", type: .dynamic, targets: ["OpenMusicEventApp"]),
    .library(name: "OpenMusicEventEntry", targets: ["OpenMusicEventEntry"]),
    .library(name: "OpenMusicEventAppRouting", targets: ["OpenMusicEventAppRouting"]),
    .library(name: "OpenMusicEventAppEventViewer", targets: ["OpenMusicEventAppEventViewer"]),
    .library(name: "OpenMusicEventEditors", targets: ["OpenMusicEventEditors"]),
    .library(name: "OpenMusicEventViewers", targets: ["OpenMusicEventViewers"]),
    .library(name: "OpenMusicEventImages", targets: ["OpenMusicEventImages"]),
    .library(name: "OpenMusicEventWhiteLabelApp", targets: ["OpenMusicEventWhiteLabelApp"]),
    .library(name: "LiquidGlassSegmentedPicker", targets: ["LiquidGlassSegmentedPicker"]),
    .library(name: "ScheduleComponents", targets: ["ScheduleComponents"]),
    .library(name: "SwiftUITabFeatures", targets: ["SwiftUITabFeatures"]),
]

let appViewProducts: [Product] = [
    .library(name: "OpenMusicEventAppViewServer", targets: ["OpenMusicEventAppViewServer"]),
    .executable(name: "OpenMusicEventAppView", targets: ["OpenMusicEventAppView"]),
    .executable(name: "OpenMusicEventAppViewLambda", targets: ["OpenMusicEventAppViewLambda"]),
]

// Package dependencies

let routingDependency: Package.Dependency = .package(
    url: "https://github.com/pointfreeco/swift-tagged",
    from: "0.10.0"
)
let jwsetKitDependency: Package.Dependency = .package(
    url: "https://github.com/woodymelling/JWSETKit",
    branch: "fix/apple-commoncrypto-rsa-selection"
)

var applicationDependencies: [Package.Dependency] = [
    .package(url: "https://source.woody.fm/composable-atmosphere-userinput", branch: "main"),
    .package(
        url: "https://source.woody.fm/composable-calendar-events",
        branch: "main"
    ),
    composableNotificationsDependency,
    isAndroidAppBuild
        ? .package(name: "swift-composable-forms", path: workspacePackagePath("swift-composable-forms-android"))
        : .package(url: "https://source.woody.fm/swift-composable-forms", branch: "main"),
    .package(url: "https://source.woody.fm/swift-frontmatter-parsing", branch: "main"),
    .package(url: "https://source.woody.fm/swift-file-tree", branch: "main"),
    .package(url: "https://source.woody.fm/swift-composable-workspace", branch: "main"),
    .package(url: "https://source.woody.fm/swift-dependencies-http-client", branch: "main"),
    isAndroidAppBuild
        ? .package(
            name: "swift-composable-atmosphere",
            path: workspacePackagePath("swift-composable-atmosphere"),
            traits: composableAtmosphereTraits
        )
        : .package(
            url: "https://source.woody.fm/swift-composable-atmosphere",
            branch: "main",
            traits: ["TCA26"]
        ),
    .package(url: "https://source.woody.fm/composable-atmosphere-constellation", branch: "main"),
    .package(url: "https://source.woody.fm/composable-atmosphere-tangled", branch: "main"),
    .package(url: "https://source.woody.fm/swift-tagged-types-macro", branch: "main"),
    .package(url: "https://source.woody.fm/swift-urlqueryitem-coder", branch: "main"),
    .package(url: "https://source.woody.fm/swift-web-metadata", branch: "main", traits: ["Dependencies"]),
    .package(url: "https://source.woody.fm/swift-dependencies-source-control-client", branch: "main"),
    .package(url: "https://github.com/pointfreeco/swift-clocks", branch: "clocks-2"),
    .package(url: "https://github.com/pointfreeco/swift-case-paths", branch: "26"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", branch: "26"),
    .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.8.1", traits: sharingTraits),
    routingDependency,
    .package(url: "https://github.com/apple/swift-collections", from: "1.5.1"),
    .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.0.0"),
    .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.9.0"),
    isAndroidAppBuild
        ? .package(name: "sqlite-data", path: workspacePackagePath("sqlite-data"), traits: sqliteDataTraits)
        : .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.0.0", traits: ["SQLiteDataTagged"]),
    isAndroidAppBuild
        ? .package(name: "swift-structured-queries", path: workspacePackagePath("swift-structured-queries"), traits: ["StructuredQueriesTagged"])
        : .package(url: "https://github.com/pointfreeco/swift-structured-queries", exact: "0.32.0", traits: ["StructuredQueriesTagged"]),
    tca26Dependency,
    .package(url: "https://github.com/apple/swift-crypto", from: "4.0.0"),
    isAndroidAppBuild
        ? .package(url: "https://github.com/swift-everywhere/grdb-sqlcipher.git", from: "7.5.0", traits: ["GRDBCIPHER"])
        : .package(url: "https://github.com/groue/GRDB.swift", from: "7.6.0"),
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.0.0"),
    .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
    .package(url: "https://github.com/apple/swift-http-types", from: "1.4.0"),
    .package(url: "https://github.com/1024jp/GzipSwift", from: "6.0.0"),
    .package(url: "https://github.com/kateinoigakukun/swift-tar", branch: "main"),
    .package(url: "https://github.com/tuist/Noora", from: "0.15.0"),
    skipDependency,
    skipFuseUIDependency,
    skipKitDependency,
    skipAndroidBridgeDependency,
    .package(url: "https://github.com/14T/DateRangePicker", branch: "main"),
    .package(url: "https://github.com/omaralbeik/Drops.git", from: "1.7.0"),
]

if isAndroidAppBuild {
    applicationDependencies.append(skipSharingDependency)
    if let skipKeychainDependency {
        applicationDependencies.append(skipKeychainDependency)
    }
}

let appViewDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/awslabs/swift-aws-lambda-events.git", from: "1.4.0"),
    .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.22.0"),
    .package(url: "https://github.com/hummingbird-project/hummingbird-lambda.git", from: "2.1.0"),
    .package(url: "https://github.com/swift-server/swift-service-lifecycle", from: "2.6.0"),
] + (packageBuild == .appView ? [
    appViewComposableCalendarEventsDependency,
    appViewComposableAtmosphereDependency,
    tca26Dependency,
    composableNotificationsDependency,
    .package(url: "https://github.com/apple/swift-crypto", from: "4.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-case-paths", branch: "26"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", branch: "26"),
    .package(
        url: "https://source.woody.fm/swift-dependencies-http-client",
        branch: "main"
    ),
    .package(url: "https://github.com/apple/swift-http-types", from: "1.4.0"),
    .package(url: "https://github.com/groue/GRDB.swift", from: "7.6.0"),
    .package(
        url: "https://github.com/pointfreeco/sqlite-data",
        from: "1.0.0",
        traits: ["SQLiteDataTagged"]
    ),
    .package(
        url: "https://github.com/pointfreeco/swift-structured-queries",
        exact: "0.32.0",
        traits: ["StructuredQueriesTagged"]
    ),
    .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.0.0"),
    .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.9.0"),
    .package(url: "https://source.woody.fm/swift-frontmatter-parsing", branch: "main"),
    .package(url: "https://source.woody.fm/swift-file-tree", branch: "main"),
    .package(url: "https://github.com/apple/swift-collections", from: "1.5.1"),
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.0.0"),
    .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
    .package(url: "https://github.com/1024jp/GzipSwift", from: "6.0.0"),
    .package(url: "https://github.com/kateinoigakukun/swift-tar", branch: "main"),
] : [])

// Target dependencies

var openMusicEventAuthenticationDependencies: [Target.Dependency] = [
    "BlueskyActorCache",
    "OpenMusicEventSourceClone",
    "OpenMusicEventComponents",
    .product(
        name: "ComposableAtmosphereUserInput",
        package: "composable-atmosphere-userinput"
    ),
    .product(name: "ATProto", package: "swift-composable-atmosphere"),
    .product(name: "ATProtoOAuth", package: "swift-composable-atmosphere"),
    .product(name: "ATProtoServer", package: "swift-composable-atmosphere"),
    .product(name: "ComposableArchitecture2", package: "TCA26"),
    .product(name: "ComposableForms", package: "swift-composable-forms"),
    .product(name: "ComposableNotifications", package: "swift-composable-notifications"),
    .product(name: "ComposableNotificationsHTTP", package: "swift-composable-notifications"),
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
    .product(name: "Dependencies", package: "swift-dependencies"),
    .product(name: "Gzip", package: "gzipswift"),
    .product(name: "HTTPClient", package: "swift-dependencies-http-client"),
    .product(name: "Tar", package: "swift-tar"),
]

if packageBuild != .appView {
    openMusicEventSourceCloneDependencies.append(contentsOf: [
        .product(name: "ATProtoOAuth", package: "swift-composable-atmosphere"),
        .product(name: "Crypto", package: "swift-crypto"),
        .product(name: "Sharing", package: "swift-sharing"),
        .product(name: "SourceControlClient", package: "swift-dependencies-source-control-client"),
        .product(name: "TangledLexicon", package: "composable-atmosphere-tangled"),
        .product(name: "Tagged", package: "swift-tagged"),
        .product(name: "XRPCClient", package: "swift-composable-atmosphere"),
    ])
}

openMusicEventAuthenticationDependencies.append(contentsOf: [
    .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
])
if isAndroidAppBuild {
    openMusicEventAuthenticationDependencies.append(
        .product(name: "SkipSharing", package: "skip-sharing", condition: .when(platforms: [.android]))
    )
    openMusicEventAuthenticationDependencies.append(
        .product(name: "SkipKeychain", package: "skip-keychain", condition: .when(platforms: [.android]))
    )
    openMusicEventSourceCloneDependencies.append(
        .product(name: "SkipSharing", package: "skip-sharing", condition: .when(platforms: [.android]))
    )
}

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

openMusicEventComponentsDependencies.append(
    .product(name: "SkipFuseUI", package: "skip-fuse-ui")
)
if packageBuild != .appView {
    openMusicEventTimeZonesDependencies.append(
        .product(name: "SkipFuseUI", package: "skip-fuse-ui")
    )
}
openMusicEventWhiteLabelDependencies.append(
    .product(name: "SkipFuseUI", package: "skip-fuse-ui")
)
scheduleComponentsDependencies.append(
    .product(name: "SkipFuseUI", package: "skip-fuse-ui")
)

// Targets

let routingTarget = Target.target(
    name: "OpenMusicEventRouting",
    dependencies: [
        "OpenMusicEventLexicon",
        .product(name: "Tagged", package: "swift-tagged"),
    ]
)

let routingTestTarget = Target.testTarget(
    name: "OpenMusicEventRoutingTests",
    dependencies: [
        "OpenMusicEventRouting",
        .product(name: "CustomDump", package: "swift-custom-dump"),
    ]
)

let openMusicEventTimeZonesTarget = Target.target(
    name: "OpenMusicEventTimeZones",
    dependencies: openMusicEventTimeZonesDependencies,
    exclude: packageBuild == .appView ? ["Skip"] : [],
    plugins: skipstonePlugins
)

let openMusicEventLexiconTarget = Target.target(
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
        .product(name: "XRPCClient", package: "swift-composable-atmosphere"),
    ]
)

let openMusicEventLexiconTestTarget = Target.testTarget(
    name: "OpenMusicEventLexiconTests",
    dependencies: [
        "OpenMusicEventLexicon",
        .product(name: "CustomDump", package: "swift-custom-dump"),
    ]
)

let openMusicEventSourceCloneTarget = Target.target(
    name: "OpenMusicEventSourceClone",
    dependencies: openMusicEventSourceCloneDependencies,
    exclude: packageBuild == .appView
        ? [
            "ATProtoRepoDescription.swift",
            "TangledLexicon.swift",
            "TangledOAuthScopes.swift",
            "TangledSSHCredentialsClient.swift",
        ]
        : [],
    swiftSettings: packageBuild == .appView
        ? [.define("OME_SOURCE_ARCHIVE_ONLY")]
        : []
)

let openMusicEventSourceTarget = Target.target(
    name: "OpenMusicEventSource",
    dependencies: [
        "OpenMusicEventLexicon",
        "OpenMusicEventSourceClone",
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "FrontmatterParsing", package: "swift-frontmatter-parsing"),
        .product(name: "FileTree", package: "swift-file-tree"),
        .product(name: "Lexicon", package: "swift-composable-atmosphere"),
        .product(name: "OrderedCollections", package: "swift-collections"),
        "Yams",
    ]
)

// Shared app, command-line, and library targets

var applicationTargets: [Target] = [
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
            .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
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
    openMusicEventLexiconTarget,
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
    openMusicEventSourceTarget,
    openMusicEventSourceCloneTarget,
    openMusicEventTimeZonesTarget,
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
    openMusicEventLexiconTestTarget,
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
]

// App UI targets

var openMusicEventAppDependencies: [Target.Dependency] = [
    "BlueskyActorCache",
    .product(name: "ComposableCalendarEvents", package: "composable-calendar-events"),
    .product(
        name: "ComposableAtmosphereUserInput",
        package: "composable-atmosphere-userinput"
    ),
    .product(
        name: "ComposableAtmosphereUserInputUI",
        package: "composable-atmosphere-userinput"
    ),
    "ErrorHandling",
    "OpenMusicEventEntry",
    "OpenMusicEventAppRouting",
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
    .product(name: "ComposableNotifications", package: "swift-composable-notifications"),
    .product(name: "ComposableNotificationsHTTP", package: "swift-composable-notifications"),
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

applicationTargets.append(contentsOf: [
    .target(
        name: "OpenMusicEventEntry",
        dependencies: [
            "OpenMusicEventAppRouting",
            "OpenMusicEventComponents",
        ],
        plugins: skipstonePlugins
    ),
    .target(
        name: "OpenMusicEventAppRouting",
        dependencies: [
            "OpenMusicEventLexicon",
            "OpenMusicEventRouting",
            "OpenMusicEventViewers",
            .product(name: "ComposableNotifications", package: "swift-composable-notifications"),
        ]
    ),
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
            .product(name: "ComposableNotifications", package: "swift-composable-notifications"),
            .product(name: "ComposableWorkspace", package: "swift-composable-workspace"),
            .product(name: "ComposableForms", package: "swift-composable-forms"),
            .product(name: "DateRangePicker", package: "DateRangePicker", condition: .when(platforms: [.iOS])),
            .product(name: "Dependencies", package: "swift-dependencies"),
            .product(name: "GRDB", package: grdbPackageName),
            .product(name: "Sharing", package: "swift-sharing"),
            .product(name: "SkipKit", package: "skip-kit"),
            .product(name: "SQLiteData", package: "sqlite-data"),
            .product(name: "TCATProtoAuthentication", package: "swift-composable-atmosphere"),
            .product(name: "XRPCClient", package: "swift-composable-atmosphere"),
        ],
        resources: [.process("Resources")],
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
            .product(
                name: "ComposableAtmosphereUserInput",
                package: "composable-atmosphere-userinput"
            ),
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
            .product(
                name: "ComposableAtmosphereUserInput",
                package: "composable-atmosphere-userinput"
            ),
            .product(
                name: "ComposableAtmosphereUserInputUI",
                package: "composable-atmosphere-userinput"
            ),
            "ErrorHandling",
            "OpenMusicEventApp",
            "OpenMusicEventAppViewServer",
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
            .product(
                name: "ComposableNotificationsServer",
                package: "swift-composable-notifications"
            ),
            .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
            .product(name: "HTTPClient", package: "swift-dependencies-http-client"),
            .product(name: "HTTPTypes", package: "swift-http-types"),
            .product(name: "HummingbirdTesting", package: "hummingbird"),
            .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
            .product(name: "Sharing", package: "swift-sharing"),
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

// AppView targets

let appViewTargets: [Target] = [
    .target(
        name: "OpenMusicEventAppViewServer",
        dependencies: [
            "OpenMusicEventLexicon",
            "OpenMusicEventRouting",
            "OpenMusicEventSource",
            .product(name: "AppViewHydrant", package: "swift-composable-atmosphere"),
            .product(name: "AppViewIndex", package: "swift-composable-atmosphere"),
            .product(name: "ComposableCalendarEvents", package: "composable-calendar-events"),
            .product(name: "ComposableArchitecture2", package: "TCA26"),
            .product(name: "ComposableNotifications", package: "swift-composable-notifications"),
            .product(
                name: "ComposableNotificationsServer",
                package: "swift-composable-notifications"
            ),
            .product(
                name: "ComposableNotificationsHTTP",
                package: "swift-composable-notifications"
            ),
            .product(name: "Crypto", package: "swift-crypto"),
            .product(name: "Dependencies", package: "swift-dependencies"),
            .product(name: "GRDB", package: grdbPackageName),
            .product(name: "Hummingbird", package: "hummingbird"),
            .product(name: "HydrantClient", package: "swift-composable-atmosphere"),
            .product(name: "HydrantClientHummingbird", package: "swift-composable-atmosphere"),
            .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
            .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
            .product(name: "SQLiteData", package: "sqlite-data"),
            .product(name: "Tagged", package: "swift-tagged"),
            .product(name: "XRPCHummingbird", package: "swift-composable-atmosphere"),
            .product(name: "XRPCClient", package: "swift-composable-atmosphere"),
        ],
        resources: [
            .copy("Resources/TemporaryOMEBrowseCatalog.json"),
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
            "OpenMusicEventLexicon",
            "OpenMusicEventSourceClone",
            .product(name: "AWSLambdaEvents", package: "swift-aws-lambda-events"),
            .product(name: "CustomDump", package: "swift-custom-dump"),
            .product(name: "HummingbirdLambda", package: "hummingbird-lambda"),
        ]
    ),
    .testTarget(
        name: "OpenMusicEventAppViewServerTests",
        dependencies: [
            "OpenMusicEventAppViewServer",
            .product(name: "AWSLambdaEvents", package: "swift-aws-lambda-events"),
            .product(name: "CustomDump", package: "swift-custom-dump"),
            .product(name: "HTTPClient", package: "swift-dependencies-http-client"),
            .product(name: "HTTPTypes", package: "swift-http-types"),
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

// Selected package graph

let products: [Product]
let dependencies: [Package.Dependency]
let targets: [Target]

switch packageBuild {
case .app:
    products = applicationProducts + appViewProducts
    dependencies = applicationDependencies + appViewDependencies + [jwsetKitDependency]
    targets = applicationTargets + [routingTarget, routingTestTarget] + appViewTargets

case .androidApp:
    products = applicationProducts
    dependencies = applicationDependencies + [jwsetKitDependency]
    targets = applicationTargets + [routingTarget, routingTestTarget]

case .appView:
    products = appViewProducts
    dependencies = [routingDependency, jwsetKitDependency] + appViewDependencies
    targets = [
        routingTarget,
        openMusicEventTimeZonesTarget,
        openMusicEventLexiconTarget,
        openMusicEventLexiconTestTarget,
        openMusicEventSourceCloneTarget,
        openMusicEventSourceTarget,
    ]
        + appViewTargets
}

let package = Package(
    name: "open-music-event",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v15)],
    products: products,
    dependencies: dependencies,
    targets: targets
)
