import Foundation

public struct ReleaseMetadataGate: Sendable {
    public var requiredScreenshotDirectories: [String]
    public var placeholderTextChecks: [PlaceholderTextCheck]
    public var websiteLegacyScreenshotReferences: [String]
    public var websiteIndexPath: String

    public init(
        requiredScreenshotDirectories: [String] = Self.defaultRequiredScreenshotDirectories,
        placeholderTextChecks: [PlaceholderTextCheck] = Self.defaultPlaceholderTextChecks,
        websiteLegacyScreenshotReferences: [String] = Self.defaultWebsiteLegacyScreenshotReferences,
        websiteIndexPath: String = Self.defaultWebsiteIndexPath
    ) {
        self.requiredScreenshotDirectories = requiredScreenshotDirectories
        self.placeholderTextChecks = placeholderTextChecks
        self.websiteLegacyScreenshotReferences = websiteLegacyScreenshotReferences
        self.websiteIndexPath = websiteIndexPath
    }

    public func validate(rootURL: URL) throws -> [ReleaseMetadataGateIssue] {
        var issues: [ReleaseMetadataGateIssue] = []

        for directory in requiredScreenshotDirectories {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: rootURL.appending(path: directory).path,
                isDirectory: &isDirectory
            )
            if !exists || !isDirectory.boolValue {
                issues.append(.missingScreenshotDirectory(directory))
            }
        }

        for check in placeholderTextChecks {
            let url = rootURL.appending(path: check.path)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let contents = try String(contentsOf: url, encoding: .utf8)
            if contents.contains(check.placeholderText) {
                issues.append(.placeholderText(path: check.path, text: check.placeholderText))
            }
        }

        let websiteIndexURL = rootURL.appending(path: websiteIndexPath)
        if FileManager.default.fileExists(atPath: websiteIndexURL.path) {
            let contents = try String(contentsOf: websiteIndexURL, encoding: .utf8)
            for reference in websiteLegacyScreenshotReferences where contents.contains(reference) {
                issues.append(.legacyWebsiteScreenshotReference(path: websiteIndexPath, reference: reference))
            }
        }

        return issues
    }
}

extension ReleaseMetadataGate {
    public static let defaultRequiredScreenshotDirectories = [
        "Darwin/fastlane/screenshots/en-US",
        "Android/fastlane/metadata/android/en-US/images/phoneScreenshots",
        "Deployments/ome-under-construction/public/assets/screenshots",
    ]

    public static let defaultPlaceholderTextChecks = [
        PlaceholderTextCheck(
            path: "Darwin/fastlane/metadata/en-US/description.txt",
            placeholderText: "A great new app built with Skip!"
        ),
        PlaceholderTextCheck(
            path: "Android/fastlane/metadata/android/en-US/full_description.txt",
            placeholderText: "A great new app built with Skip!"
        ),
        PlaceholderTextCheck(
            path: "Android/fastlane/metadata/android/en-US/short_description.txt",
            placeholderText: "A great new app built with Skip!"
        ),
        PlaceholderTextCheck(
            path: "Darwin/fastlane/metadata/en-US/subtitle.txt",
            placeholderText: "A new Skip app"
        ),
        PlaceholderTextCheck(
            path: "Android/fastlane/metadata/android/en-US/short_description.txt",
            placeholderText: "A new Skip app"
        ),
    ]

    public static let defaultWebsiteIndexPath = "Deployments/ome-under-construction/public/index.html"

    public static let defaultWebsiteLegacyScreenshotReferences = [
        "assets/ome-schedule.jpeg",
        "assets/ome-artist-detail.jpeg",
        "assets/ome-location.jpeg",
        "assets/ome-updates.jpeg",
        "assets/ome-more.jpeg",
    ]
}

public struct PlaceholderTextCheck: Equatable, Hashable, Sendable {
    public var path: String
    public var placeholderText: String

    public init(path: String, placeholderText: String) {
        self.path = path
        self.placeholderText = placeholderText
    }
}

public enum ReleaseMetadataGateIssue: Equatable, Hashable, Sendable {
    case missingScreenshotDirectory(String)
    case placeholderText(path: String, text: String)
    case legacyWebsiteScreenshotReference(path: String, reference: String)
}
