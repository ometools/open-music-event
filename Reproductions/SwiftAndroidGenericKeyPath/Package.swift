// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SwiftAndroidGenericKeyPath",
    platforms: [.macOS(.v10_15)],
    dependencies: [
        .package(path: "../../../worktrees/swift-sharing"),
        .package(path: "../../../../swift-packages/3rd-party/skip/skip-sharing")
    ],
    targets: [
        .testTarget(
            name: "SwiftAndroidGenericKeyPathTests",
            dependencies: [
                .product(name: "Sharing", package: "swift-sharing"),
                .product(
                    name: "SkipSharing",
                    package: "skip-sharing",
                    condition: .when(platforms: [.android])
                )
            ]
        )
    ]
)
