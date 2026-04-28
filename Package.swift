// swift-tools-version: 6.1
// This is a Skip (https://skip.dev) package.
import PackageDescription

let package = Package(
    name: "open-music-event",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "OpenMusicEvent", type: .dynamic, targets: ["OpenMusicEvent"]),
        .library(name: "OpenMusicEventLexicon", targets: ["OpenMusicEventLexicon"]),
    ],
    dependencies: [
        .package(url: "https://source.skip.tools/skip.git", from: "1.8.6"),
        .package(url: "https://source.skip.tools/skip-fuse-ui.git", from: "1.0.0"),

        .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.0.0", traits: ["SQLiteDataTagged"]),
        .package(url: "https://github.com/pointfreeco/TCA26", branch: "main"),


        .package(url: "https://source.woody.fm/tcatproto", branch: "main"),
//        .package(path: "~/Developer/composable-atmosphere/tcatproto")
    ],
    targets: [
        .target(
            name: "OpenMusicEvent",
            dependencies: [
                .product(name: "SkipFuseUI", package: "skip-fuse-ui")
            ],
            resources: [.process("Resources")],
            plugins: [.plugin(name: "skipstone", package: "skip")]
        ),

        .target(
            name: "OpenMusicEventLexicon",
            dependencies: [
                .product(name: "Lexicon", package: "tcatproto"),
                .product(name: "LexiconSQLiteData", package: "tcatproto"),
                .product(name: "SQLiteData", package: "sqlite-data"),
            ]
        ),
    ]
)
