import Dependencies
import FileTree
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSource
import SQLiteData
import SourceEditing

public struct OpenMusicEventSourcePatchRequest: Equatable, Sendable {
    public var eventID: OME.Event.ID

    public init(eventID: OME.Event.ID) {
        self.eventID = eventID
    }
}

public enum OpenMusicEventSourcePatchGenerationError: Equatable, Error, Sendable {
    case notSourceBacked(OME.Event.ID)
}

public struct OpenMusicEventSourcePatchLocationResolver: Sendable {
    public var resolve: @Sendable (OpenMusicEventSourcePatchRequest) async throws -> SourcePatchLocation

    public init(
        resolve: @escaping @Sendable (OpenMusicEventSourcePatchRequest) async throws -> SourcePatchLocation
    ) {
        self.resolve = resolve
    }
}

public struct OpenMusicEventSourcePatchConversion: Sendable {
    public var update: @Sendable (
        OpenMusicEventSourceEvent,
        OpenMusicEventSourcePatchRequest
    ) async throws -> OpenMusicEventSourceEvent

    public init(
        update: @escaping @Sendable (
            OpenMusicEventSourceEvent,
            OpenMusicEventSourcePatchRequest
        ) async throws -> OpenMusicEventSourceEvent
    ) {
        self.update = update
    }
}

public extension OpenMusicEventSourcePatchConversion {
    static var identity: Self {
        Self { sourceEvent, _ in sourceEvent }
    }
}

public extension OpenMusicEventSourcePatchLocationResolver {
    static var openMusicEvent: Self {
        Self { request in
            @Dependency(\.defaultDatabase) var database
            @Dependency(\.sourceRepositoryStorage) var sourceRepositoryStorage

            let provenance = try await database.read { db in
                let provenance = try EventSourceProvenanceRecord
                    .where { $0.id.eq(request.eventID) }
                    .fetchOne(db)
                guard let provenance else {
                    throw OpenMusicEventSourcePatchGenerationError.notSourceBacked(request.eventID)
                }
                return provenance
            }
            return SourcePatchLocation(
                repositoryURL: try sourceRepositoryStorage.repositoryURL(provenance.sourceProvenance),
                relativePath: "events/\(provenance.sourceEventDirectory)"
            )
        }
    }
}

public extension SourcePatchGenerator where Request == OpenMusicEventSourcePatchRequest {
    static var openMusicEvent: Self {
        .live(
            resolveLocation: { request in
                @Dependency(\.openMusicEventSourcePatchLocationResolver) var resolver
                return try await resolver.resolve(request)
            },
            read: { sourceURL in
                try OpenMusicEventSourceEventFileTree()
                    .read(from: sourceURL)
                    .output
                    .requiredValue
            },
            update: { sourceEvent, request in
                @Dependency(\.openMusicEventSourcePatchConversion) var conversion
                return try await conversion.update(sourceEvent, request)
            },
            rewrite: { sourceEvent, workingURL in
                _ = try OpenMusicEventSourceEventFileTree()
                    .rewrite(sourceEvent, at: workingURL)
            }
        )
    }
}

public extension DependencyValues {
    var openMusicEventSourcePatchLocationResolver: OpenMusicEventSourcePatchLocationResolver {
        get { self[OpenMusicEventSourcePatchLocationResolverKey.self] }
        set { self[OpenMusicEventSourcePatchLocationResolverKey.self] = newValue }
    }

    var openMusicEventSourcePatchConversion: OpenMusicEventSourcePatchConversion {
        get { self[OpenMusicEventSourcePatchConversionKey.self] }
        set { self[OpenMusicEventSourcePatchConversionKey.self] = newValue }
    }
}

private enum OpenMusicEventSourcePatchLocationResolverKey: DependencyKey {
    static var liveValue: OpenMusicEventSourcePatchLocationResolver {
        .openMusicEvent
    }

    static var testValue: OpenMusicEventSourcePatchLocationResolver {
        .openMusicEvent
    }
}

private enum OpenMusicEventSourcePatchConversionKey: DependencyKey {
    static var liveValue: OpenMusicEventSourcePatchConversion {
        .live
    }

    static var testValue: OpenMusicEventSourcePatchConversion {
        .identity
    }
}

private extension EventSourceProvenanceRecord {
    var sourceProvenance: OME.SourceDatabaseInsertion.SourceProvenance {
        OME.SourceDatabaseInsertion.SourceProvenance(
            kind: sourceKind,
            reference: sourceReference,
            ref: ref
        )
    }
}
