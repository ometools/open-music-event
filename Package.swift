// swift-tools-version: 6.2
// This is a Skip (https://skip.tools) package.
import PackageDescription

let package = Package(
    name: "open-music-event",
    defaultLocalization: "en",
    platforms: [.iOS(.v18), .macOS(.v26)],
    products: [
        .library(
            name: "OpenMusicEvent",
            type: .dynamic,
            targets: ["OpenMusicEvent"]
        ),
    ],
    dependencies: [
        // Core holds things that are all platform compatable.
        .package(path: "Core"),

        .package(url: "https://github.com/woodymelling/swift-file-tree", branch: "android-support"),
//
        .package(url: "https://source.skip.tools/skip.git", from: "1.6.0"),
        .package(url: "https://source.skip.tools/skip-fuse-ui.git", from: "1.14.0"),
        .package(url: "https://github.com/woodymelling/swift-dependencies-http-client", from: "0.2.0"),
        .package(url: "https://source.skip.tools/skip-firebase.git", "0.9.0"..<"2.0.0"),
        .package(url: "https://github.com/swift-everywhere/grdb-sqlcipher.git", from: "7.5.0", traits: ["GRDBCIPHER"]),

//        .package(url: "https://github.com/groue/GRDBSnapshotTesting", from: "0.3.0"),

        .package(url: "https://github.com/pointfreeco/swift-tagged", from: "0.10.0"),
        .package(url: "https://github.com/pointfreeco/swift-case-paths", from: "1.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.4.1"),
        .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.3.3"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.18.0"),
        .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-url-routing", from: "0.6.2"),
        .package(url: "https://github.com/pointfreeco/swift-perception", from: "2.0.0"),


        // Pin this version, 1.1 might be
        .package(url: "https://github.com/pointfreeco/combine-schedulers", exact: "1.0.3"),

        .package(url: "https://github.com/apple/swift-collections", from: "1.0.4"),
        .package(url: "https://github.com/vapor-community/Zip.git", from: "2.2.6"),

        .package(url: "https://github.com/kean/Nuke", from: "12.8.0"),
    ],
    targets: [
        .target(
            name: "OpenMusicEvent",
            dependencies: [
                .product(name: "CoreModels", package: "Core"),
                .product(name: "OpenMusicEventParser", package: "Core"),

                .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
                .product(name: "GRDB", package: "grdb-sqlcipher"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
                .product(name: "Sharing", package: "swift-sharing"),

                .product(name: "CasePaths", package: "swift-case-paths"),

                .product(name: "Zip", package: "zip"),
                .product(name: "NukeUI", package: "Nuke", condition: .when(platforms: [.iOS])),
                .product(name: "HTTPClient", package: "swift-dependencies-http-client"),

                .product(name: "SkipFirebaseCore", package: "skip-firebase"),
                .product(name: "SkipFirebaseMessaging", package: "skip-firebase"),

                .product(name: "URLRouting", package: "swift-url-routing"),

                .product(name: "Perception", package: "swift-perception")
            ],
            resources: [.process("Resources")],
            plugins: [
                .plugin(name: "skipstone", package: "skip")
            ]
        ),
        .testTarget(
            name: "OpenMusicEventAppTests",
            dependencies: [
                "OpenMusicEvent",
                .product(name: "CustomDump", package: "swift-custom-dump"),
//                .product(name: "Parsing", package: "swift-parsing"),
                .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
                .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
                .product(name: "SnapshotTestingCustomDump", package: "swift-snapshot-testing"),
//                .product(name: "GRDBSnapshotTesting", package: "GRDBSnapshotTesting"),
            ]
        )
    ]
)

if Context.environment["SKIP_BRIDGE"] ?? "0" != "0" {
    package.dependencies += [.package(url: "https://source.skip.tools/skip-bridge.git", "0.0.0"..<"2.0.0")]
    package.targets.forEach({ target in
        target.dependencies += [.product(name: "SkipBridge", package: "skip-bridge")]
    })
    // all library types must be dynamic to support bridging
    package.products = package.products.map({ product in
        guard let libraryProduct = product as? Product.Library else { return product }
        return .library(name: libraryProduct.name, type: .dynamic, targets: libraryProduct.targets)
    })
}
