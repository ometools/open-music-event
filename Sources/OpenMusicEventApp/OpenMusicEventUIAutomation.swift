import Dependencies
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSource
import SQLiteData
import SwiftUI

private enum OpenMusicEventUIAutomationKey: DependencyKey {
    static let liveValue = false
    static let testValue = false
}

extension DependencyValues {
    var openMusicEventUIAutomation: Bool {
        get { self[OpenMusicEventUIAutomationKey.self] }
        set { self[OpenMusicEventUIAutomationKey.self] = newValue }
    }
}

enum OpenMusicEventUIAutomationFixtureError: Error, Equatable {
    case missingBundledSource
}

enum OpenMusicEventUIAutomationFixture {
    static let organizerID = OME.Organizer.ID("did:web:example.com")!
    static let sourceReference = "tangled.org/open-music-event/testival-source"
    static let sourceRef = "main"

    static let bundledFiles = [
        "calendar.yml",
        "events/testival-2026/event.yml",
        "events/testival-2026/stages/meadow.yml",
        "events/testival-2026/contributors/artist-one.md",
        "events/testival-2026/schedules/saturday.yml",
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
        // processed resources in the iOS bundle. Materialize the same five bundled
        // files into a real directory so the normal source validator can traverse it.
        for relativePath in bundledFiles {
            let pathComponents = relativePath.split(separator: "/").map(String.init)
            guard let fileName = pathComponents.last else {
                throw OpenMusicEventUIAutomationFixtureError.missingBundledSource
            }
            let fileURL = URL(fileURLWithPath: fileName)
            let extensionName = fileURL.pathExtension
            let resourceName = fileURL.deletingPathExtension().lastPathComponent
            let relativeDirectory = pathComponents.dropLast().joined(separator: "/")
            let nestedDirectory = [
                "UIAutomation/TestivalSource",
                relativeDirectory.isEmpty ? nil : relativeDirectory,
            ]
            .compactMap { $0 }
            .joined(separator: "/")

            guard let bundledURL = bundle.url(
                forResource: resourceName,
                withExtension: extensionName,
                subdirectory: nestedDirectory
            ) ?? bundle.url(
                forResource: resourceName,
                withExtension: extensionName
            ) else {
                throw OpenMusicEventUIAutomationFixtureError.missingBundledSource
            }

            let destinationURL = sourceURL.appendingPathComponent(relativePath)
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(contentsOf: bundledURL).write(to: destinationURL, options: .atomic)
        }
        return sourceURL
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
    let uiAutomation: Bool
    @State var preparation: OpenMusicEventApplicationPreparation

    /* SKIP @bridge */public init() {
        @Dependency(\.openMusicEventUIAutomation) var uiAutomation
        self.uiAutomation = uiAutomation
        self._preparation = State(initialValue: uiAutomation ? .preparing : .ready)
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
        guard uiAutomation, preparation == .preparing else { return }
        @Dependency(\.defaultDatabase) var database
        do {
            try await OpenMusicEventUIAutomationFixture.importSource(into: database)
            preparation = .ready
        } catch {
            preparation = .failed(String(describing: error))
        }
    }
}
