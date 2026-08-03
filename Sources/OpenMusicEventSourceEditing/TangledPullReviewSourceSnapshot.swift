import Dependencies
import FileTree
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceClone

public struct TangledPullReviewSourceSnapshotRequest: Equatable, Sendable {
    public var organizerID: OME.Organizer.ID
    public var ref: String
    public var sourceProvenance: OME.SourceDatabaseInsertion.SourceProvenance

    public init(
        organizerID: OME.Organizer.ID,
        ref: String,
        sourceProvenance: OME.SourceDatabaseInsertion.SourceProvenance
    ) {
        self.organizerID = organizerID
        self.ref = ref
        self.sourceProvenance = sourceProvenance
    }
}

public enum TangledPullReviewSourceSnapshotError: Equatable, Error, Sendable {
    case missingSourceBranch(String)
    case unsupportedSourceKind(OME.SourceDatabaseInsertion.SourceKind)
}

public struct TangledPullReviewSourceSnapshotClient: Sendable {
    public var insertion: @Sendable (
        TangledPullReviewSourceSnapshotRequest
    ) async throws -> OME.SourceDatabaseInsertion

    public init(
        insertion: @escaping @Sendable (
            TangledPullReviewSourceSnapshotRequest
        ) async throws -> OME.SourceDatabaseInsertion
    ) {
        self.insertion = insertion
    }
}

public extension TangledPullReviewSourceSnapshotClient {
    static var openMusicEvent: Self {
        Self { request in
            guard request.sourceProvenance.kind == .tangled else {
                throw TangledPullReviewSourceSnapshotError.unsupportedSourceKind(
                    request.sourceProvenance.kind
                )
            }
            let ref = request.ref.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !ref.isEmpty else {
                throw TangledPullReviewSourceSnapshotError.missingSourceBranch(request.ref)
            }

            let repository = try TangledRepositoryReference(
                sourceReference: request.sourceProvenance.reference
            )
            @Dependency(\.tangledSourceCheckout) var tangledSourceCheckout
            let outputURL = FileManager.default.temporaryDirectory
                .appending(
                    path: "open-music-event-pull-review-\(UUID().uuidString)",
                    directoryHint: .isDirectory
                )
            do {
                _ = try await tangledSourceCheckout.checkout(
                    TangledSourceCheckoutRequest(
                        repository: repository,
                        ref: ref,
                        outputURL: outputURL
                    )
                )
                defer { try? FileManager.default.removeItem(at: outputURL) }

                let sourceResult = try OpenMusicEventSourceRepositoryFileTree()
                    .read(from: outputURL)
                let source = try sourceResult.output.requiredValue
                return try OME.SourceDatabaseInsertion(
                    OME.SourceDatabaseInsertion.Configuration(
                        source: source,
                        organizerID: request.organizerID,
                        sourceProvenance: request.sourceProvenance,
                        sourceRootURL: outputURL
                    )
                )
            } catch {
                try? FileManager.default.removeItem(at: outputURL)
                throw error
            }
        }
    }

    static var noop: Self {
        Self { _ in
            throw TangledPullReviewSourceSnapshotError.missingSourceBranch("noop")
        }
    }
}

public extension DependencyValues {
    var tangledPullReviewSourceSnapshot: TangledPullReviewSourceSnapshotClient {
        get { self[TangledPullReviewSourceSnapshotClientKey.self] }
        set { self[TangledPullReviewSourceSnapshotClientKey.self] = newValue }
    }
}

private enum TangledPullReviewSourceSnapshotClientKey: DependencyKey {
    static var liveValue: TangledPullReviewSourceSnapshotClient {
        .openMusicEvent
    }

    static var testValue: TangledPullReviewSourceSnapshotClient {
        .noop
    }
}
