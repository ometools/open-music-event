import Foundation
import OpenMusicEventReleaseTools
import Testing

struct ReleaseMetadataGateTests {
    @Test
    func reportsTemplateMetadataMissingScreenshotsAndLegacyWebsiteImages() throws {
        let fixture = try TemporaryDirectory()
        defer { fixture.remove() }

        try fixture.write(
            "Darwin/fastlane/metadata/en-US/description.txt",
            contents: "A great new app built with Skip!"
        )
        try fixture.write(
            "Android/fastlane/metadata/android/en-US/short_description.txt",
            contents: "A new Skip app"
        )
        try fixture.write(
            "Deployments/ome-under-construction/public/index.html",
            contents: #"""
            <section aria-labelledby="clarity-title">
              <img src="assets/ome-schedule.jpeg">
              <img src="assets/ome-location.jpeg">
            </section>
            """#
        )

        let issues = try ReleaseMetadataGate().validate(rootURL: fixture.url)

        #expect(issues.contains(.missingScreenshotDirectory("Darwin/fastlane/screenshots/en-US")))
        #expect(issues.contains(.missingScreenshotDirectory("Android/fastlane/metadata/android/en-US/images/phoneScreenshots")))
        #expect(issues.contains(.missingScreenshotDirectory("Deployments/ome-under-construction/public/assets/screenshots")))
        #expect(issues.contains(.placeholderText(
            path: "Darwin/fastlane/metadata/en-US/description.txt",
            text: "A great new app built with Skip!"
        )))
        #expect(issues.contains(.placeholderText(
            path: "Android/fastlane/metadata/android/en-US/short_description.txt",
            text: "A new Skip app"
        )))
        #expect(issues.contains(.legacyWebsiteScreenshotReference(
            path: "Deployments/ome-under-construction/public/index.html",
            reference: "assets/ome-schedule.jpeg"
        )))
        #expect(issues.contains(.legacyWebsiteScreenshotReference(
            path: "Deployments/ome-under-construction/public/index.html",
            reference: "assets/ome-location.jpeg"
        )))
    }
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        self.url = FileManager.default.temporaryDirectory
            .appending(path: "ome-release-metadata-gate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func write(_ relativePath: String, contents: String) throws {
        let url = self.url.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
