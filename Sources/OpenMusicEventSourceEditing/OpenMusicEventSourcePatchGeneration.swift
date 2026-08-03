import Dependencies
import FileTree
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSource
import SourceEditing

public struct SourceWorkspacePatchRequest: Equatable, Sendable {
    public var workspace: SourceWorkspace

    public init(workspace: SourceWorkspace) {
        self.workspace = workspace
    }
}

struct OpenMusicEventSourceEventConversion: Sendable {
    var update: @Sendable (
        OpenMusicEventSourceEvent,
        OME.Event.ID
    ) async throws -> OpenMusicEventSourceEvent
}

public struct SourceWorkspacePatchConversion: Sendable {
    public var update: @Sendable (
        OpenMusicEventSourceRepository,
        SourceWorkspacePatchRequest
    ) async throws -> OpenMusicEventSourceRepository

    public init(
        update: @escaping @Sendable (
            OpenMusicEventSourceRepository,
            SourceWorkspacePatchRequest
        ) async throws -> OpenMusicEventSourceRepository
    ) {
        self.update = update
    }
}

public extension SourcePatchGenerator where Request == SourceWorkspacePatchRequest {
    static var openMusicEvent: Self {
        .live(
            resolveLocation: { request in
                @Dependency(\.sourceWorkspaceStorage) var storage
                let location = try storage.location(request.workspace.id)
                return SourcePatchLocation(
                    repositoryURL: location.repositoryURL,
                    relativePath: nil,
                    remote: SourcePatchLocation.Remote(
                        kind: OME.SourceDatabaseInsertion.SourceKind.tangled.rawValue,
                        reference: request.workspace.repository,
                        ref: request.workspace.branch
                    )
                )
            },
            read: { sourceURL in
                try OpenMusicEventSourceRepositoryFileTree()
                    .read(from: sourceURL)
                    .output
                    .requiredValue
            },
            update: { sourceRepository, request in
                @Dependency(\.sourceWorkspacePatchConversion) var conversion
                return try await conversion.update(sourceRepository, request)
            },
            rewrite: { sourceRepository, workingURL in
                let materializedSourceRepository = try sourceRepository
                    .materializingLocalImageFiles(at: workingURL)
                _ = try OpenMusicEventSourceRepositoryFileTree()
                    .rewrite(materializedSourceRepository, at: workingURL)
            }
        )
    }
}

public extension DependencyValues {
    var sourceWorkspacePatchConversion: SourceWorkspacePatchConversion {
        get { self[SourceWorkspacePatchConversionKey.self] }
        set { self[SourceWorkspacePatchConversionKey.self] = newValue }
    }
}

private enum SourceWorkspacePatchConversionKey: DependencyKey {
    static var liveValue: SourceWorkspacePatchConversion { .live }
    static var testValue: SourceWorkspacePatchConversion { .live }
}

extension OpenMusicEventSourceEvent {
    static var emptyForNewSourcePatch: Self {
        OpenMusicEventSourceEvent(
            event: EventDTO(
                id: nil,
                name: "",
                description: nil,
                startDate: nil,
                endDate: nil,
                status: nil,
                mode: nil,
                locations: nil,
                uris: nil,
                timeZone: TimeZone(secondsFromGMT: 0)!,
                images: nil,
                contactNumbers: nil,
                categoryConfigs: nil
            )
        )
    }
}
