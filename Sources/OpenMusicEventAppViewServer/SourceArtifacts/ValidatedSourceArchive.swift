import Dependencies
import Foundation
import HTTPClient
import OpenMusicEventSource
import OpenMusicEventSourceClone

struct ValidatedSourceArchive: Equatable, Sendable {
    let data: Data
    let snapshot: TangledSourceSnapshot

    static func downloadAndValidate(
        update: TangledSourceUpdate,
        revision: String
    ) async throws -> Self {
        @Dependency(\.httpClient) var httpClient
        @Dependency(\.uuid) var uuid

        let repository = TangledRepositoryReference(
            host: update.repository.host,
            port: update.repository.port,
            owner: update.repositoryOwnerDID.description,
            repository: update.repository.repository
        )
        let archiveData: Data = try await withDependencies {
            $0.logBody = false
        } operation: {
            try await httpClient.get(
                repository.archiveURL(ref: revision),
                decodingTo: Data.self
            )
        }
        let outputURL = TangledSourceCloner.temporaryOutputURL(uuid: uuid())
        try TangledSourceArchiveExtractor.validateOutputDoesNotExist(outputURL)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try TangledSourceArchiveExtractor().extract(archiveData, to: outputURL)
        let validation = try await OpenMusicEventSourceValidator(
            OpenMusicEventSourceValidationRequest(
                source: outputURL.path(percentEncoded: false),
                organizerID: update.canonicalSource.organizerID,
                sourceProvenance: update.canonicalSource.provenance(ref: revision),
                ref: revision
            )
        )
        .validate()
        return Self(
            data: archiveData,
            snapshot: try TangledSourceSnapshot(
                validated: validation.insertion,
                revision: revision
            )
        )
    }
}
