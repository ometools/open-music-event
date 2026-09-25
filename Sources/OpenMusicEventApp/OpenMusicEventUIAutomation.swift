import ATProto
import Dependencies
import Foundation
import HTTPClient
import HTTPTypes
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSource
import SQLiteData
import SwiftUI

private enum OpenMusicEventUIAutomationKey: DependencyKey {
    static let liveValue = OpenMusicEventUIAutomation.normal
    static let testValue = OpenMusicEventUIAutomation.normal
}

extension DependencyValues {
    var openMusicEventUIAutomation: OpenMusicEventUIAutomation {
        get { self[OpenMusicEventUIAutomationKey.self] }
        set { self[OpenMusicEventUIAutomationKey.self] = newValue }
    }
}

enum OpenMusicEventUIAutomationFixtureError: Error, Equatable {
    case missingBundledSource
}

enum OpenMusicEventUIAutomationFixture {
    /// Saturday, August 1, 2026 at 6:15 PM in Testival's America/Denver time zone.
    /// One frozen clock keeps Browse, Schedule, and performance indicators in agreement.
    static let now = Date(timeIntervalSince1970: 1_785_629_700)
    static let organizerID = OME.Organizer.ID("did:web:example.com")!
    static let eventID = OME.Event.ID(
        organizerID: organizerID,
        eventID: OME.ID<OME.Event>(rawValue: "testival-source-testival-2026")
    )
    static let sourceReference = "tangled.org/open-music-event/testival-source"
    static let sourceRef = "main"
    static let refreshRevision = "testival-refresh-b"
    static let refreshArtifactRepository =
        "https://resources.openmusicevent.test/open-music-event/testival-source"
    static let refreshArtifactURL = URL(
        string: "\(refreshArtifactRepository)/archive/\(refreshRevision).tar.gz"
    )!
    static let refreshArtifactSHA256 =
        "r7PUPbDE4x1C1vB6GEu4pRm1A9/aztbcxiK131Roetc="
    static let refreshArtifactByteCount = 21_198
    static let calendarEventPath = "/xrpc/\(OME.CalendarEvent.GetEvent.nsid)"

    static let bundledFiles = [
        "calendar.yml",
        "events/testival-2026/event.yml",
        "events/testival-2026/maps/main.yml",
        "events/testival-2026/maps/public-map.png",
        "events/testival-2026/maps/safety-map.png",
        "events/testival-2026/stages/canopy.yml",
        "events/testival-2026/stages/meadow.yml",
        "events/testival-2026/stages/workshop-grove.yml",
        "events/testival-2026/contributors/artist-one.md",
        "events/testival-2026/contributors/artist-three.md",
        "events/testival-2026/contributors/artist-two.md",
        "events/testival-2026/contributors/facilitator-four.md",
        "events/testival-2026/schedules/saturday.yml",
        "events/testival-2026/schedules/sunday.yml",
        "events/testival-2026/channels/general.yml",
        "events/testival-2026/channels/safety.yml",
        "events/testival-2026/communications/general/channel-info.yaml",
        "events/testival-2026/communications/general/welcome.md",
    ]

    static func sourceURL(bundle: Bundle = .module) throws -> URL {
        let fileManager = FileManager.default
        let sourceURL = fileManager.temporaryDirectory
            .appendingPathComponent("OMEUIAutomation", isDirectory: true)
            .appendingPathComponent("TestivalSource", isDirectory: true)

        if fileManager.fileExists(atPath: sourceURL.path) {
            try fileManager.removeItem(at: sourceURL)
        }
        try fileManager.createDirectory(at: sourceURL, withIntermediateDirectories: true)

        // Android exposes package resources as asset URLs, while SwiftPM flattens
        // processed resources in the iOS bundle. Materialize the bundled source into
        // a real directory so the normal source validator can traverse it.
        for relativePath in bundledFiles {
            try materializeBundledFile(
                at: "UIAutomation/TestivalSource/\(relativePath)",
                as: relativePath,
                in: sourceURL,
                bundle: bundle,
                fileManager: fileManager
            )
        }

        return sourceURL
    }

    static func refreshArtifactData(bundle: Bundle = .module) throws -> Data {
        // Keep the already-gzipped bytes behind an opaque resource extension. Android's
        // resource pipeline otherwise expands `.gz` files before placing them in the APK,
        // which would no longer match the AppView-advertised size and checksum.
        guard let artifactURL = bundle.url(
            forResource: "testival-refresh-b-gzip",
            withExtension: "fixture",
            subdirectory: "UIAutomation"
        ) ?? bundle.url(
            forResource: "testival-refresh-b-gzip",
            withExtension: "fixture"
        ) else {
            throw OpenMusicEventUIAutomationFixtureError.missingBundledSource
        }
        return try Data(contentsOf: artifactURL)
    }

    /// Installs the two responses a real AppView owns: the catalog projection and the immutable
    /// source artifact it advertises. Everything after this raw HTTP boundary is production code.
    static func prepareServerResponses(
        _ dependencies: inout DependencyValues,
        appViewHost: ATProto.PDSHost
    ) {
        let liveDataForURL = dependencies.dataForURL
        dependencies.dataForURL = { request, body in
            if isRefreshCatalogRequest(request) {
                return (
                    try refreshCalendarEventData(appViewHost: appViewHost),
                    HTTPResponse(status: .ok)
                )
            }
            if isRefreshArtifactRequest(request) {
                return (
                    try refreshArtifactData(),
                    HTTPResponse(status: .ok)
                )
            }
            return try await liveDataForURL(request, body)
        }
    }

    static func refreshCalendarEvent(appViewHost: ATProto.PDSHost) -> OME.CalendarEvent {
        OME.CalendarEvent(
            uri: OME.Event.reference(id: eventID).uri,
            name: "Testival 2026",
            description: "A compact, deterministic festival that exercises attendee refresh.",
            organizer: OME.CalendarEvent.Organizer(id: organizerID),
            source: OME.CalendarEvent.Source(
                collection: OME.Event.nsid,
                appViewHost: appViewHost,
                sourceRecord: OME.SourceRecord(
                    kind: .tangled,
                    reference: sourceReference,
                    ref: refreshRevision
                ),
                resolvedArtifact: OME.CalendarEvent.Source.Artifact(
                    url: refreshArtifactURL,
                    revision: refreshRevision,
                    checksumSHA256: refreshArtifactSHA256,
                    byteCount: refreshArtifactByteCount
                ),
                resolvedRepository: OME.CalendarEvent.Source.Repository(
                    reference: refreshArtifactRepository,
                    ref: refreshRevision
                )
            ),
            timeZoneIdentifier: "America/Denver"
        )
    }

    static func refreshCalendarEventData(appViewHost: ATProto.PDSHost) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(refreshCalendarEvent(appViewHost: appViewHost))
    }

    static func isRefreshCatalogRequest(_ request: HTTPRequest) -> Bool {
        guard request.method == .get,
              let url = request.url,
              url.path == calendarEventPath
        else { return false }
        let requestedEventURI = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )?
        .queryItems?
        .first(where: { $0.name == "uri" })?
        .value
        return requestedEventURI == OME.Event.reference(id: eventID).uri.description
    }

    static func isRefreshArtifactRequest(_ request: HTTPRequest) -> Bool {
        guard request.method == .get,
              let url = request.url
        else { return false }

        // swift-foundation's Android URL equality and absent-query representation do not
        // currently agree with Darwin's for this HTTPS URL. The fixture owns this synthetic
        // host, so matching its exact archive path remains specific without relying on either.
        return url.host?.lowercased() == refreshArtifactURL.host?.lowercased()
            && url.path == refreshArtifactURL.path
    }

    static func materializeBundledFile(
        at bundledPath: String,
        as sourcePath: String,
        in sourceURL: URL,
        bundle: Bundle,
        fileManager: FileManager
    ) throws {
        let pathComponents = bundledPath.split(separator: "/").map(String.init)
        guard let fileName = pathComponents.last else {
            throw OpenMusicEventUIAutomationFixtureError.missingBundledSource
        }
        let fileURL = URL(fileURLWithPath: fileName)
        let extensionName = fileURL.pathExtension
        let resourceName = fileURL.deletingPathExtension().lastPathComponent
        let relativeDirectory = pathComponents.dropLast().joined(separator: "/")

        guard let bundledURL = bundle.url(
            forResource: resourceName,
            withExtension: extensionName,
            subdirectory: relativeDirectory
        ) ?? bundle.url(
            forResource: resourceName,
            withExtension: extensionName
        ) else {
            throw OpenMusicEventUIAutomationFixtureError.missingBundledSource
        }

        let destinationURL = sourceURL.appendingPathComponent(sourcePath)
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contentsOf: bundledURL).write(to: destinationURL, options: .atomic)
    }

    @discardableResult
    static func importSource(
        into database: any DatabaseWriter,
        sourceURL: URL? = nil
    ) async throws -> OpenMusicEventSourceValidationResult {
        let sourceURL = try sourceURL ?? self.sourceURL()
        return try await OpenMusicEventSourceValidator(
            OpenMusicEventSourceValidationRequest(
                source: sourceURL.path,
                organizerID: organizerID,
                sourceProvenance: OME.SourceDatabaseInsertion.SourceProvenance(
                    kind: .tangled,
                    reference: sourceReference,
                    ref: sourceRef
                ),
                ref: sourceRef
            )
        )
        .validateAndInsert(into: database)
    }
}

enum OpenMusicEventApplicationPreparation: Equatable {
    case preparing
    case ready
    case failed(String)
}

/// The platform entry view keeps ordinary launches immediate while giving UI automation one
/// deterministic preparation gate. The existing application root is unchanged after the fixture
/// has crossed the same validator and database insertion boundary as a real event source.
/* SKIP @bridge */@MainActor public struct OpenMusicEventApplicationEntryView: View {
    let uiAutomation: OpenMusicEventUIAutomation
    @State var preparation: OpenMusicEventApplicationPreparation

    /* SKIP @bridge */public init() {
        @Dependency(\.openMusicEventUIAutomation) var uiAutomation
        self.uiAutomation = uiAutomation
        self._preparation = State(initialValue: uiAutomation == .attendee ? .preparing : .ready)
    }

    public var body: some View {
        Group {
            switch preparation {
            case .preparing:
                VStack(spacing: 12.0) {
                    ProgressView()
                    Text("Preparing Testival")
                }
                .accessibilityIdentifier("view.ui-automation-preparing")

            case .ready:
                OpenMusicEventApplicationRootView()

            case let .failed(message):
                VStack(alignment: .leading, spacing: 12.0) {
                    Text("Unable to Prepare Testival")
                        .font(.headline)
                    Text(message)
                        .font(.body)
                }
                .padding()
                .accessibilityIdentifier("view.ui-automation-failed")
            }
        }
        .task {
            await prepareFixtureIfNeeded()
        }
    }

    func prepareFixtureIfNeeded() async {
        guard uiAutomation == .attendee, preparation == .preparing else { return }
        @Dependency(\.defaultDatabase) var database
        do {
            try await OpenMusicEventUIAutomationFixture.importSource(into: database)
            preparation = .ready
        } catch {
            preparation = .failed(String(describing: error))
        }
    }
}
