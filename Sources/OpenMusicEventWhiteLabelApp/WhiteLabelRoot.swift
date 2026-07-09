import Dependencies
import Foundation
import HTTPClient
@_exported import OpenMusicEventApp
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceClone
import OpenMusicEventSourceEditing
import OpenMusicEventWhiteLabel
import SQLiteData

public extension WhiteLabelSourceImportClient {
    static var live: Self {
        Self { organizerID, descriptor in
            @Dependency(\.defaultDatabase) var database
            @Dependency(\.httpClient) var httpClient
            @Dependency(\.tangledSourceArchiveExtractor) var archiveExtractor
            @Dependency(\.tangledSourceImport) var tangledSourceImport
            @Dependency(\.uuid) var uuid

            let cachedEventIDs = try await events(for: organizerID, in: database)
            guard cachedEventIDs.isEmpty else { return cachedEventIDs }

            let request: OpenMusicEventSourceValidationRequest
            let cleanupURL: URL?

            switch descriptor.reference {
            case let .archiveURL(url):
                let outputURL = SourceRepositoryStorageClient
                    .temporaryDownloadURL(uuid: uuid())
                let archiveData: Data = try await withDependencies {
                    $0.logBody = false
                } operation: {
                    try await httpClient.get(url, decodingTo: Data.self)
                }
                try await archiveExtractor.extract(archiveData, outputURL)
                request = OpenMusicEventSourceValidationRequest(
                    source: outputURL.path(),
                    organizerID: organizerID
                )
                cleanupURL = outputURL

            case let .source(source):
                let result = try await tangledSourceImport.importSource(
                    OpenMusicEventSourceValidationRequest(
                        source: source,
                        organizerID: organizerID
                    )
                )
                return result.insertedEventIDs
            }

            defer {
                if let cleanupURL {
                    try? FileManager.default.removeItem(at: cleanupURL)
                }
            }

            let result = try await OpenMusicEventSourceValidator(request)
                .validateAndInsertIntoDefaultDatabase()
            return result.insertedEventIDs
        }
    }

    private static func events(
        for organizerID: OMERecord.Organizer.ID,
        in database: any DatabaseReader
    ) async throws -> [OMERecord.Event.ID] {
        try await database.read { db in
            try OMERecord.Event
                .where { $0.id.organizerID.eq(organizerID) }
                .fetchAll(db)
                .map(\.id)
        }
    }
}
