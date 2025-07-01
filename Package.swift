// swift-tools-version: 6.0
// This is a Skip (https://skip.tools) package.
import PackageDescription

let package = Package(
    name: "open-music-event",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14), .tvOS(.v17), .watchOS(.v10), .macCatalyst(.v17)],
    products: [
        .library(name: "OpenMusicEvent", type: .dynamic, targets: ["OpenMusicEvent"]),
    ],
    dependencies: [
        .package(path: "Core"),

        .package(url: "https://github.com/woodymelling/swift-file-tree", branch: "android-support"),

        .package(url: "https://source.skip.tools/skip.git", from: "1.5.18"),
        .package(url: "https://source.skip.tools/skip-fuse-ui.git", "0.0.0"..<"2.0.0"),
        .package(url: "https://github.com/swift-everywhere/grdb-sqlcipher.git", from: "7.5.0"),

        .package(url: "https://github.com/pointfreeco/swift-tagged", from: "0.10.0"),
        .package(url: "https://github.com/pointfreeco/swift-case-paths", from: "1.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.4.1"),
        .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.3.3"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.18.0"),

        .package(url: "https://github.com/apple/swift-collections", from: "1.0.4"),
        .package(url: "https://github.com/vapor-community/Zip.git", from: "2.2.6"),
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

                .product(name: "CasePaths", package: "swift-case-paths"),


                .product(name: "Zip", package: "zip"),
            ],
            plugins: [.plugin(name: "skipstone", package: "skip")]
        ),
    ]
)
