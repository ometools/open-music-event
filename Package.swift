// swift-tools-version: 6.1
// This is a Skip (https://skip.dev) package.
import Foundation
import PackageDescription

// Build selection

enum PackageBuild: Equatable {
    case app
    case androidApp
    case appView
    case database
    case lexicon
}

// OME_APPVIEW selects the standalone server graph. OME_ANDROID_APP_BUILD
// selects Android-specific package variants. With neither set, SwiftPM exposes
// the complete app development graph, including the AppView targets.
let environment = ProcessInfo.processInfo.environment
let packageBuild: PackageBuild = {
    if environment["OME_LEXICON"] == "1" { return .lexicon }
    if environment["OME_DATABASE"] == "1" { return .database }
    if environment["OME_APPVIEW"] == "1" {
        return .appView
    }
    if environment["OME_ANDROID_APP_BUILD"] == "1" {
        return .androidApp
    }
    return .app
}()

let isAndroidAppBuild = packageBuild == .androidApp
let isSkipBridgeHostBuild = environment["SKIP_BRIDGE"] == "1" && !isAndroidAppBuild
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
    isAndroidAppBuild || isSkipBridgeHostBuild
    ? ["SkipAndroidBridge", "BlueskyProfiles"]
    : [.defaults, "BlueskyProfiles"]

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
        url: "https://github.com/pointfreeco/TCA26",
        branch: "main",
        traits: ["Dependencies"]
    )
}()
let composableAtmosphereUserInputDependency: Package.Dependency = .package(
    name: "composable-atmosphere-userinput",
    path: environment["OME_COMPOSABLE_ATMOSPHERE_USERINPUT_PATH"].map(packagePath)
        ?? "/Users/woody/Developer/ometools/worktrees/composable-atmosphere-userinput-reorg"
)
let composableWorkspaceDependency: Package.Dependency = {
    if let path = environment["OME_COMPOSABLE_WORKSPACE_PATH"] {
        return .package(
            name: "swift-composable-workspace",
            path: packagePath(path)
        )
    }
    return .package(
        name: "swift-composable-workspace",
        path: "/Users/woody/Developer/ometools/worktrees/swift-composable-workspace-atmosphere-reorg"
    )
}()
let sourceControlDependency: Package.Dependency = {
    if let path = environment["OME_SOURCE_CONTROL_CLIENT_PATH"] {
        return .package(
            name: "swift-dependencies-source-control-client",
            path: packagePath(path)
        )
    }
    return .package(
        url: "https://source.woody.fm/swift-dependencies-source-control-client",
        branch: "main"
    )
}()
let dependenciesHTTPClientDependency: Package.Dependency = {
    if let path = environment["OME_DEPENDENCIES_HTTP_CLIENT_PATH"] {
        return .package(
            name: "swift-dependencies-http-client",
            path: packagePath(path)
        )
    }
    if isAndroidAppBuild {
        return .package(
            name: "swift-dependencies-http-client",
            path: workspacePackagePath("swift-dependencies-http-client")
        )
    }
    return .package(
        url: "https://tangled.org/woody.fm/swift-dependencies-http-client",
        from: "0.3.0"
    )
}()
let atmosphereFamilyRoot = environment["OME_COMPOSABLE_ATMOSPHERE_PATH"].map(packagePath)
    ?? "/Users/woody/Developer/swift-packages/swift-composable-atmosphere-reorg-auth"
func atmosphereFamilyDependency(_ name: String) -> Package.Dependency {
    .package(name: name, path: atmosphereFamilyRoot + "/Packages/" + name)
}
let composableAtmosphereDependency: Package.Dependency = .package(
    name: "swift-composable-atmosphere",
    path: atmosphereFamilyRoot,
    traits: composableAtmosphereTraits
)
let atprotoDependency = atmosphereFamilyDependency("swift-atproto")
let atprotoOAuthDependency = atmosphereFamilyDependency("swift-atproto-oauth")
let atprotoSQLiteDependency = atmosphereFamilyDependency("swift-atproto-sqlite")
let atprotoServerDependency = atmosphereFamilyDependency("swift-atproto-server")
let blueskyDependency = atmosphereFamilyDependency("swift-bluesky")
let composableAtmosphereConstellationDependency: Package.Dependency = .package(
    name: "composable-atmosphere-constellation",
    path: environment["OME_COMPOSABLE_ATMOSPHERE_CONSTELLATION_PATH"].map(packagePath)
        ?? "/Users/woody/Developer/ometools/worktrees/composable-atmosphere-constellation-reorg"
)
let composableAtmosphereTangledDependency: Package.Dependency = .package(
    name: "composable-atmosphere-tangled",
    path: environment["OME_COMPOSABLE_ATMOSPHERE_TANGLED_PATH"].map(packagePath)
        ?? "/Users/woody/Developer/ometools/worktrees/composable-atmosphere-tangled-reorg"
)
let appViewComposableCalendarEventsDependency: Package.Dependency
appViewComposableCalendarEventsDependency = .package(
    name: "composable-calendar-events",
    path: environment["OME_COMPOSABLE_CALENDAR_EVENTS_PATH"].map(packagePath)
        ?? "/Users/woody/Developer/ometools/worktrees/composable-calendar-events-reorg"
)
let composableNotificationsDependency: Package.Dependency = {
    if let path = environment["OME_COMPOSABLE_NOTIFICATIONS_PATH"] {
        return .package(
            name: "swift-composable-notifications",
            path: packagePath(path)
        )
    }
    if isAndroidAppBuild {
        return .package(
            name: "swift-composable-notifications",
            path: workspacePackagePath("swift-composable-notifications")
        )
    }
    return .package(
        name: "swift-composable-notifications",
        path: "/Users/woody/Developer/ometools/worktrees/swift-composable-notifications-atmosphere-reorg"
    )
}()
let skipstonePlugins: [Target.PluginUsage] = packageBuild == .appView || packageBuild == .database || packageBuild == .lexicon
    ? []
    : [.plugin(name: "skipstone", package: "skip")]
let workspaceSkipRootPath = [
    "../../swift-packages/3rd-party/skip",
    "../../../swift-packages/3rd-party/skip",
]
    .map(packagePath)
    .first { FileManager.default.fileExists(atPath: $0) }
let skipRootPath: URL? = {
    if let skipLocal = environment["SKIPLOCAL"] {
        return URL(fileURLWithPath: skipLocal).deletingLastPathComponent()
    }
    guard isAndroidAppBuild, let workspaceSkipRootPath else {
        return nil
    }
    return URL(fileURLWithPath: workspaceSkipRootPath)
}()
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
    .library(
        name: "SwiftUITabFeaturesFuseFixtures",
        type: .dynamic,
        targets: ["SwiftUITabFeaturesFuseFixtures"]
    ),
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
let swiftSharingPath = environment["SKIP_SHARING_SWIFT_SHARING"]
    ?? workspacePackagePath("swift-sharing")
let swiftSharingDependency: Package.Dependency = isAndroidAppBuild
    ? .package(
        name: "swift-sharing",
        path: swiftSharingPath,
        traits: sharingTraits
    )
    : .package(
        url: "https://github.com/pointfreeco/swift-sharing",
        from: "2.10.1",
        traits: sharingTraits
    )
let jwsetKitDependency: Package.Dependency = .package(
    url: "https://github.com/woodymelling/JWSETKit",
    branch: "fix/apple-commoncrypto-rsa-selection"
)

let fileTreeDependency: Package.Dependency = {
    if let path = environment["OME_FILE_TREE_PATH"] {
        return .package(name: "swift-file-tree", path: path)
    }
    return .package(url: "https://source.woody.fm/swift-file-tree", branch: "main")
}()

let clocksDependency: Package.Dependency = {
    if let path = environment["OME_CLOCKS_PATH"] {
        return .package(name: "swift-clocks", path: path)
    }
    return .package(url: "https://github.com/pointfreeco/swift-clocks", branch: "clocks-2")
}()

let customDumpDependency: Package.Dependency = {
    if let path = environment["OME_CUSTOM_DUMP_PATH"] {
        return .package(name: "swift-custom-dump", path: path)
    }
    return .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.0.0")
}()

var applicationDependencies: [Package.Dependency] = [
    .package(
        path: workspacePackagePath("swift-hero-image-list"),
        traits: ["Skip"]
    ),
    composableAtmosphereUserInputDependency,
    appViewComposableCalendarEventsDependency,
    composableNotificationsDependency,
    isAndroidAppBuild
        ? .package(name: "swift-composable-forms", path: workspacePackagePath("swift-composable-forms-android"))
        : .package(name: "swift-composable-forms", path: "/Users/woody/Developer/ometools/worktrees/swift-composable-forms-atmosphere-reorg"),
    .package(url: "https://source.woody.fm/swift-frontmatter-parsing", branch: "main"),
    fileTreeDependency,
    composableWorkspaceDependency,
    .package(url: "https://github.com/pointfreeco/combine-schedulers", exact: "1.2.0"),
    dependenciesHTTPClientDependency,
    composableAtmosphereDependency,
    atprotoDependency,
    atprotoOAuthDependency,
    atprotoSQLiteDependency,
    atprotoServerDependency,
    blueskyDependency,
    composableAtmosphereConstellationDependency,
    composableAtmosphereTangledDependency,
    .package(url: "https://tangled.org/woody.fm/swift-tagged-types-macro", from: "0.1.0"),
    .package(url: "https://tangled.org/woody.fm/swift-urlqueryitem-coder", from: "1.1.0"),
    .package(url: "https://source.woody.fm/swift-web-metadata", branch: "main", traits: ["Dependencies"]),
    sourceControlDependency,
    clocksDependency,
    .package(url: "https://github.com/pointfreeco/swift-case-paths", branch: "protocol-case-paths"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", branch: "26"),
    swiftSharingDependency,
    routingDependency,
    // Collections 1.7 references a Swift 6.4 runtime symbol missing before macOS/iOS 27.
    .package(url: "https://github.com/apple/swift-collections", .upToNextMinor(from: "1.6.0")),
    customDumpDependency,
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.0.0"),
    .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.9.0"),
    isAndroidAppBuild
        ? .package(name: "sqlite-data", path: workspacePackagePath("sqlite-data"), traits: sqliteDataTraits)
        : .package(url: "https://github.com/pointfreeco/sqlite-data", exact: "1.6.6", traits: ["SQLiteDataTagged"]),
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
    skipAndroidBridgeDependency,
    .package(url: "https://github.com/14T/DateRangePicker", branch: "main"),
    .package(url: "https://github.com/omaralbeik/Drops.git", from: "1.7.0"),
]

if let path = environment["OME_SKIP_AUTHENTICATION_SERVICES_PATH"] {
    applicationDependencies.append(.package(name: "skip-authentication-services", path: path))
}

if let path = environment["OME_DEBUG_SNAPSHOTS_PATH"] {
    applicationDependencies.append(.package(name: "swift-debug-snapshots", path: path))
}

if isAndroidAppBuild {
    applicationDependencies.append(skipKitDependency)
}

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
    composableAtmosphereDependency,
    atprotoDependency,
    atprotoOAuthDependency,
    atprotoSQLiteDependency,
    atprotoServerDependency,
    blueskyDependency,
    tca26Dependency,
    composableNotificationsDependency,
    swiftSharingDependency,
    composableAtmosphereConstellationDependency,
    composableAtmosphereTangledDependency,
    composableWorkspaceDependency,
    sourceControlDependency,
    .package(url: "https://github.com/apple/swift-crypto", from: "4.0.0"),
    .package(url: "https://github.com/pointfreeco/combine-schedulers", exact: "1.2.0"),
    .package(url: "https://github.com/pointfreeco/swift-case-paths", branch: "protocol-case-paths"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", branch: "26"),
    .package(
        url: "https://tangled.org/woody.fm/swift-dependencies-http-client",
        from: "0.3.0"
    ),
    .package(url: "https://github.com/apple/swift-http-types", from: "1.4.0"),
    .package(url: "https://github.com/groue/GRDB.swift", from: "7.6.0"),
    .package(
        url: "https://github.com/pointfreeco/sqlite-data",
        exact: "1.6.6",
        traits: ["SQLiteDataTagged"]
    ),
    .package(
        url: "https://github.com/pointfreeco/swift-structured-queries",
        exact: "0.32.0",
        traits: ["StructuredQueriesTagged"]
    ),
    customDumpDependency,
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.0.0"),
    .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.9.0"),
    .package(url: "https://source.woody.fm/swift-frontmatter-parsing", branch: "main"),
    fileTreeDependency,
    // Collections 1.7 references a Swift 6.4 runtime symbol missing before macOS/iOS 27.
    .package(url: "https://github.com/apple/swift-collections", .upToNextMinor(from: "1.6.0")),
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.0.0"),
    .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
    .package(url: "https://github.com/1024jp/GzipSwift", from: "6.0.0"),
    .package(url: "https://github.com/kateinoigakukun/swift-tar", branch: "main"),
] : [])

// Target dependencies

var openMusicEventAuthenticationDependencies: [Target.Dependency] = [
    "OpenMusicEventOAuthClient",
    .product(name: "Bluesky", package: "swift-bluesky"),
    "OpenMusicEventSourceClone",
    "OpenMusicEventComponents",
    .product(
        name: "ComposableAtmosphereUserInput",
        package: "composable-atmosphere-userinput"
    ),
    .product(name: "ATProto", package: "swift-atproto"),
    .product(name: "ATProtoOAuth", package: "swift-atproto-oauth"),
    .product(name: "ComposableArchitecture2", package: "TCA26"),
    .product(name: "ComposableForms", package: "swift-composable-forms"),
    .product(name: "ComposableNotifications", package: "swift-composable-notifications"),
    .product(name: "ComposableNotificationsHTTP", package: "swift-composable-notifications"),
    .product(name: "Dependencies", package: "swift-dependencies"),
    .product(name: "HTTPClient", package: "swift-dependencies-http-client"),
    .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
    .product(name: "Sharing", package: "swift-sharing"),
    .product(name: "SQLiteData", package: "sqlite-data"),
    .product(name: "ComposableAtmosphere", package: "swift-composable-atmosphere"),
    .product(name: "WebMetadataClient", package: "swift-web-metadata"),
]

var openMusicEventSourceCloneDependencies: [Target.Dependency] = [
    .product(name: "ArgumentParser", package: "swift-argument-parser"),
    .product(name: "ATProto", package: "swift-atproto"),
    .product(name: "Crypto", package: "swift-crypto"),
    .product(name: "Dependencies", package: "swift-dependencies"),
    .product(name: "Gzip", package: "gzipswift"),
    .product(name: "HTTPClient", package: "swift-dependencies-http-client"),
    .product(name: "Tar", package: "swift-tar"),
]

openMusicEventSourceCloneDependencies.append(contentsOf: [
    .product(name: "ATProtoOAuth", package: "swift-atproto-oauth"),
    .product(name: "Sharing", package: "swift-sharing"),
    .product(name: "SourceControlClient", package: "swift-dependencies-source-control-client"),
    .product(name: "TangledLexicon", package: "composable-atmosphere-tangled"),
    .product(name: "Tagged", package: "swift-tagged"),
])

openMusicEventAuthenticationDependencies.append(contentsOf: [
    .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
])
if isAndroidAppBuild {
    openMusicEventAuthenticationDependencies.append(
        .product(name: "SkipSharing", package: "skip-sharing", condition: .when(platforms: [.android]))
    )
    openMusicEventAuthenticationDependencies.append(
        // The host prebuild must see this product to package its JVM implementation.
        .product(name: "SkipKeychain", package: "skip-keychain")
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
    .product(name: "ATProto", package: "swift-atproto"),
    .product(name: "Dependencies", package: "swift-dependencies"),
]
let skipKitTargetDependencies: [Target.Dependency] = isAndroidAppBuild
    ? [.product(name: "SkipKit", package: "skip-kit")]
    : []
var scheduleComponentsDependencies: [Target.Dependency] = [
    .product(name: "Dependencies", package: "swift-dependencies"),
]

openMusicEventComponentsDependencies.append(contentsOf: [
    .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
    .product(
        name: "SkipAndroidBridge",
        package: "skip-android-bridge",
        condition: .when(platforms: [.android])
    ),
])
if packageBuild == .app || packageBuild == .androidApp {
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

let openMusicEventAppHostTestDependencies: [Target.Dependency] = isAndroidAppBuild
    ? []
    : [
        .target(
            name: "OpenMusicEventAppViewServer",
            condition: .when(platforms: [.macOS])
        ),
        .product(
            name: "ComposableNotificationsServer",
            package: "swift-composable-notifications",
            condition: .when(platforms: [.macOS])
        ),
        .product(
            name: "HummingbirdTesting",
            package: "hummingbird",
            condition: .when(platforms: [.macOS])
        ),
    ]

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
    exclude: (packageBuild == .appView || packageBuild == .lexicon) ? ["Skip"] : [],
    plugins: skipstonePlugins
)

let openMusicEventLexiconTarget = Target.target(
    name: "OpenMusicEventLexicon",
    dependencies: [
        "OpenMusicEventTimeZones",
        .product(name: "ATProto", package: "swift-atproto"),
        .product(name: "CasePaths", package: "swift-case-paths"),
        .product(name: "ATProtoTypes", package: "swift-atproto"),
        .product(name: "ATProtoSQLite", package: "swift-atproto-sqlite"),
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "StructuredQueriesSQLite", package: "swift-structured-queries"),
        .product(name: "Tagged", package: "swift-tagged"),
    ]
)

let openMusicEventLexiconTestTarget = Target.testTarget(
    name: "OpenMusicEventLexiconTests",
    dependencies: [
        "OpenMusicEventLexicon",
        .product(name: "CustomDump", package: "swift-custom-dump"),
    ],
    resources: [.copy("Fixtures")]
)

let openMusicEventSourceCloneTarget = Target.target(
    name: "OpenMusicEventSourceClone",
    dependencies: openMusicEventSourceCloneDependencies
)

let openMusicEventSourceTarget = Target.target(
    name: "OpenMusicEventSource",
    dependencies: [
        "OpenMusicEventLexicon",
        "OpenMusicEventSourceClone",
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "FrontmatterParsing", package: "swift-frontmatter-parsing"),
        .product(name: "FileTree", package: "swift-file-tree"),
        .product(name: "ATProtoTypes", package: "swift-atproto"),
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
            .product(name: "ATProto", package: "swift-atproto"),
            .product(name: "Crypto", package: "swift-crypto"),
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
            .product(name: "ATProto", package: "swift-atproto"),
            .product(name: "ATProtoOAuth", package: "swift-atproto-oauth"),
            .product(name: "CasePaths", package: "swift-case-paths"),
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
            .product(name: "ATProtoTypes", package: "swift-atproto"),
            .product(name: "SourceControlClient", package: "swift-dependencies-source-control-client"),
            .product(name: "Sharing", package: "swift-sharing"),
            .product(name: "SQLiteData", package: "sqlite-data"),
            .product(name: "TangledLexicon", package: "composable-atmosphere-tangled"),
            .product(name: "TangledXRPC", package: "composable-atmosphere-tangled"),
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
            .product(name: "ATProto", package: "swift-atproto"),
            .product(name: "ATProtoOAuth", package: "swift-atproto-oauth"),
            .product(name: "Dependencies", package: "swift-dependencies"),
            .product(name: "FileTree", package: "swift-file-tree"),
            .product(name: "HTTPClient", package: "swift-dependencies-http-client"),
            .product(name: "Noora", package: "Noora"),
            .product(name: "TangledLexicon", package: "composable-atmosphere-tangled"),
            .product(name: "TangledXRPC", package: "composable-atmosphere-tangled"),
        ]
    ),
    .testTarget(
        name: "BlueskyActorCacheTests",
        dependencies: [
            .product(name: "Bluesky", package: "swift-bluesky"),
            .product(name: "ATProto", package: "swift-atproto"),
            .product(name: "CustomDump", package: "swift-custom-dump"),
            .product(name: "Dependencies", package: "swift-dependencies"),
            .product(name: "HTTPClient", package: "swift-dependencies-http-client"),
            .product(name: "HTTPTypes", package: "swift-http-types"),
            .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
            .product(name: "SQLiteData", package: "sqlite-data"),
        ]
    ),
    .testTarget(
        name: "OpenMusicEventCLITests",
        dependencies: [
            "OpenMusicEventCLI",
            "OpenMusicEventSourceClone",
            .product(name: "ATProto", package: "swift-atproto"),
            .product(name: "CustomDump", package: "swift-custom-dump"),
            .product(name: "HTTPClient", package: "swift-dependencies-http-client"),
            .product(name: "HTTPTypes", package: "swift-http-types"),
            .product(name: "SourceControlClient", package: "swift-dependencies-source-control-client"),
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
            .product(name: "ATProto", package: "swift-atproto"),
            .product(name: "CustomDump", package: "swift-custom-dump"),
            .product(name: "GRDB", package: grdbPackageName),
        ]
    ),
    .testTarget(
        name: "OpenMusicEventSourceTests",
        dependencies: [
            "OpenMusicEventLexicon",
            "OpenMusicEventSource",
            .product(name: "ATProto", package: "swift-atproto"),
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
            "OpenMusicEventSourceClone",
            "OpenMusicEventSourceEditing",
            "SourceEditing",
            .product(name: "ATProto", package: "swift-atproto"),
            .product(name: "CustomDump", package: "swift-custom-dump"),
            .product(name: "ComposableWorkspace", package: "swift-composable-workspace"),
            .product(name: "Dependencies", package: "swift-dependencies"),
            .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
            .product(name: "FileTree", package: "swift-file-tree"),
            .product(name: "GRDB", package: grdbPackageName),
            .product(name: "Gzip", package: "gzipswift"),
            .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
            .product(name: "ATProtoTypes", package: "swift-atproto"),
            .product(name: "HTTPClient", package: "swift-dependencies-http-client"),
            .product(name: "SourceControlClient", package: "swift-dependencies-source-control-client"),
            .product(name: "SQLiteData", package: "sqlite-data"),
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            .product(name: "TangledLexicon", package: "composable-atmosphere-tangled"),
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
    "OpenMusicEventOAuthClient",
    .product(name: "HeroImageList", package: "swift-hero-image-list"),
    .product(name: "Bluesky", package: "swift-bluesky"),
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
    "OpenMusicEventTimeZones",
    "OpenMusicEventWhiteLabel",
    .product(name: "ComposableArchitecture2", package: "TCA26"),
    .product(name: "ComposableNotifications", package: "swift-composable-notifications"),
    .product(name: "ComposableNotificationsHTTP", package: "swift-composable-notifications"),
    .product(name: "Dependencies", package: "swift-dependencies"),
    .product(name: "Drops", package: "Drops", condition: .when(platforms: [.iOS])),
    .product(name: "HTTPClient", package: "swift-dependencies-http-client"),
    .product(name: "HTTPTypes", package: "swift-http-types"),
    .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
    .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
    .product(name: "SQLiteData", package: "sqlite-data"),
    .product(name: "ATProto", package: "swift-atproto"),
    .product(name: "ATProtoSQLite", package: "swift-atproto-sqlite"),
]

// The Android app target names SkipKit directly so the host-side Gradle
// prebuild discovers its Kotlin implementation before the native Swift build.
if isAndroidAppBuild {
    openMusicEventAppDependencies += skipKitTargetDependencies
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
            .product(name: "HeroImageList", package: "swift-hero-image-list"),
            .product(name: "Bluesky", package: "swift-bluesky"),
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
            .product(name: "ATProto", package: "swift-atproto"),
            .product(name: "ATProtoSQLite", package: "swift-atproto-sqlite"),
            .product(name: "ATProtoTypes", package: "swift-atproto"),
            .product(name: "ATProtoOAuth", package: "swift-atproto-oauth"),
            .product(name: "ComposableArchitecture2", package: "TCA26"),
            .product(name: "ComposableAuthoring", package: "swift-composable-workspace"),
            .product(name: "ComposableNotifications", package: "swift-composable-notifications"),
            .product(name: "ComposableWorkspace", package: "swift-composable-workspace"),
            .product(name: "ComposableForms", package: "swift-composable-forms"),
            .product(name: "DateRangePicker", package: "DateRangePicker", condition: .when(platforms: [.iOS])),
            .product(name: "Dependencies", package: "swift-dependencies"),
            .product(name: "GRDB", package: grdbPackageName),
            .product(name: "Sharing", package: "swift-sharing"),
            .product(name: "SQLiteData", package: "sqlite-data"),
            .product(name: "ComposableAtmosphere", package: "swift-composable-atmosphere"),
        ] + skipKitTargetDependencies,
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
            "OpenMusicEventLexicon",
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
            .product(name: "ATProto", package: "swift-atproto"),
            .product(name: "ComposableArchitecture2", package: "TCA26"),
            .product(name: "Dependencies", package: "swift-dependencies"),
            .product(name: "HTTPClient", package: "swift-dependencies-http-client"),
            .product(name: "SQLiteData", package: "sqlite-data"),
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
    .target(
        name: "SwiftUITabFeaturesFuseFixtures",
        dependencies: [
            "OpenMusicEventApp",
            "OpenMusicEventAppEventViewer",
            "OpenMusicEventLexicon",
            "SwiftUITabFeatures",
            .product(name: "ComposableArchitecture2", package: "TCA26"),
            .product(name: "Dependencies", package: "swift-dependencies"),
            .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
            .product(name: "SQLiteData", package: "sqlite-data"),
        ],
        plugins: [.plugin(name: "skipstone", package: "skip")]
    ),
    .testTarget(
        name: "OpenMusicEventAuthenticationTests",
        dependencies: [
            .product(name: "Bluesky", package: "swift-bluesky"),
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
            .product(name: "ComposableAtmosphere", package: "swift-composable-atmosphere"),
            .product(name: "WebMetadataClient", package: "swift-web-metadata"),
        ]
    ),
    .testTarget(
        name: "OpenMusicEventAppTests",
        dependencies: [
            .product(name: "Bluesky", package: "swift-bluesky"),
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
            "OpenMusicEventAuthentication",
            "OpenMusicEventImages",
            "OpenMusicEventLexicon",
            "OpenMusicEventViewers",
            "OpenMusicEventWhiteLabel",
            "OpenMusicEventSourceEditing",
            .product(name: "ATProto", package: "swift-atproto"),
            .product(name: "ATProtoTypes", package: "swift-atproto"),
            .product(name: "Clocks", package: "swift-clocks"),
            .product(name: "ComposableArchitecture2", package: "TCA26"),
            .product(name: "CustomDump", package: "swift-custom-dump"),
            .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
            .product(name: "HTTPClient", package: "swift-dependencies-http-client"),
            .product(name: "HTTPTypes", package: "swift-http-types"),
            .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
            .product(name: "Sharing", package: "swift-sharing"),
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            .product(name: "SnapshotTestingCustomDump", package: "swift-snapshot-testing"),
            .product(name: "SourceControlClient", package: "swift-dependencies-source-control-client"),
            .product(name: "SQLiteData", package: "sqlite-data"),
            .product(name: "TangledLexicon", package: "composable-atmosphere-tangled"),
        ] + openMusicEventAppHostTestDependencies,
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
            .product(name: "ATProto", package: "swift-atproto"),
            .product(name: "ComposableArchitecture2", package: "TCA26"),
            .product(name: "Dependencies", package: "swift-dependencies"),
            .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
            .product(name: "HTTPClient", package: "swift-dependencies-http-client"),
            .product(name: "HTTPTypes", package: "swift-http-types"),
            .product(name: "SourceControlClient", package: "swift-dependencies-source-control-client"),
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
        name: "SwiftUITabFeaturesTests",
        dependencies: [
            "SwiftUITabFeatures",
        ]
    ),
    .testTarget(
        name: "SwiftUITabFeaturesFuseFixturesTests",
        dependencies: [
            "SwiftUITabFeaturesFuseFixtures",
            .product(name: "SkipAndroidBridge", package: "skip-android-bridge"),
            .product(name: "SkipTest", package: "skip"),
        ],
        path: "Tests/SwiftUITabFeaturesFuseTests",
        plugins: [.plugin(name: "skipstone", package: "skip")]
    ),
])

// AppView targets

let appViewTargets: [Target] = [
    .target(
        name: "OpenMusicEventAppViewServer",
        dependencies: [
            "OpenMusicEventOAuthClient",
            "OpenMusicEventDatabase",
            "OpenMusicEventLexicon",
            "OpenMusicEventRouting",
            "OpenMusicEventSource",
            "OpenMusicEventSourceClone",
            "OpenMusicEventSourceEditing",
            "SourceEditing",
            .product(name: "ATProtoAppView", package: "swift-atproto-server"),
            .product(name: "ComposableCalendarEvents", package: "composable-calendar-events"),
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
            .product(name: "FileTree", package: "swift-file-tree"),
            .product(name: "GRDB", package: grdbPackageName),
            .product(name: "Hummingbird", package: "hummingbird"),
            .product(name: "HTTPClient", package: "swift-dependencies-http-client"),
            .product(name: "HTTPTypes", package: "swift-http-types"),
            .product(name: "ATProtoStreams", package: "swift-atproto-server"),
            .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
            .product(name: "ATProtoSQLite", package: "swift-atproto-sqlite"),
            .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
            .product(name: "SQLiteData", package: "sqlite-data"),
            .product(name: "Tagged", package: "swift-tagged"),
            .product(name: "TangledLexicon", package: "composable-atmosphere-tangled"),
            .product(name: "ATProtoHTTP", package: "swift-atproto-server"),
            .product(name: "ATProto", package: "swift-atproto"),
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
            "OpenMusicEventLexicon",
            "OpenMusicEventSourceEditing",
            "SourceEditing",
            .product(name: "AWSLambdaEvents", package: "swift-aws-lambda-events"),
            .product(name: "CustomDump", package: "swift-custom-dump"),
            .product(name: "HTTPClient", package: "swift-dependencies-http-client"),
            .product(name: "HTTPTypes", package: "swift-http-types"),
            .product(name: "HummingbirdLambda", package: "hummingbird-lambda"),
            .product(name: "HummingbirdLambdaTesting", package: "hummingbird-lambda"),
            .product(name: "HummingbirdTesting", package: "hummingbird"),
            .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
            .product(name: "ATProtoTypes", package: "swift-atproto"),
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
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
var targets: [Target]

switch packageBuild {
case .app:
    products = applicationProducts + appViewProducts
    dependencies = applicationDependencies + appViewDependencies + [jwsetKitDependency]
    targets = applicationTargets + [routingTarget, routingTestTarget] + appViewTargets

case .androidApp:
    products = applicationProducts.filter {
        !["ome", "ome-release-check", "OpenMusicEventReleaseTools"].contains($0.name)
    }
    dependencies = applicationDependencies + [jwsetKitDependency]
    targets = applicationTargets.filter { target in
        if target.name.hasSuffix("Tests") {
            return ["OpenMusicEventAppTests", "SwiftUITabFeaturesFuseFixturesTests"].contains(target.name)
        }
        return ![
            "OpenMusicEventCLI",
            "OpenMusicEventReleaseCheck",
            "OpenMusicEventReleaseTools",
        ].contains(target.name)
    } + [routingTarget, routingTestTarget]

case .lexicon:
    products = [
        .library(name: "OpenMusicEventLexicon", targets: ["OpenMusicEventLexicon"]),
        .library(name: "OpenMusicEventRouting", targets: ["OpenMusicEventRouting"]),
        .executable(name: "ome-export-lexicons", targets: ["OpenMusicEventLexiconExport"]),
    ]
    dependencies = [
        atprotoDependency, atprotoSQLiteDependency, routingDependency,
        .package(url: "https://github.com/pointfreeco/swift-case-paths", branch: "protocol-case-paths"),
        .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.0.0"),
        .package(url: "https://github.com/pointfreeco/sqlite-data", exact: "1.6.6", traits: ["SQLiteDataTagged"]),
        .package(url: "https://github.com/pointfreeco/swift-structured-queries", exact: "0.32.0", traits: ["StructuredQueriesTagged"]),
    ]
    targets = [
        openMusicEventTimeZonesTarget, openMusicEventLexiconTarget, openMusicEventLexiconTestTarget,
        routingTarget, routingTestTarget,
        .executableTarget(name: "OpenMusicEventLexiconExport", dependencies: ["OpenMusicEventLexicon"]),
    ]

case .database:
    products = [
        .library(name: "OpenMusicEventDatabase", targets: ["OpenMusicEventDatabase"]),
        .library(name: "OpenMusicEventLexicon", targets: ["OpenMusicEventLexicon"]),
    ]
    dependencies = applicationDependencies
    targets = [
        openMusicEventTimeZonesTarget,
        openMusicEventLexiconTarget,
        openMusicEventSourceCloneTarget,
        openMusicEventSourceTarget,
    ] + applicationTargets.filter {
        [
            "ErrorHandling",
            "OpenMusicEventDatabase",
            "OpenMusicEventDatabaseTests",
            "OpenMusicEventSourceEditing",
            "OpenMusicEventSourceEditingTests",
            "SourceEditing",
        ].contains($0.name)
    }

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
        + applicationTargets.filter {
            [
                "ErrorHandling",
                "OpenMusicEventDatabase",
                "OpenMusicEventSourceEditing",
                "SourceEditing",
            ]
            .contains($0.name)
        }
        + appViewTargets
}

targets.append(.target(name: "OpenMusicEventOAuthClient"))
if !isAndroidAppBuild {
    targets.append(.testTarget(name: "OpenMusicEventOAuthClientTests", dependencies: ["OpenMusicEventOAuthClient"]))
}

let package = Package(
    name: "open-music-event",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v15)],
    products: products,
    dependencies: dependencies,
    targets: targets
)
