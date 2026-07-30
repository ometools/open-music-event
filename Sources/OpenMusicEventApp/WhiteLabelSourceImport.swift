import Dependencies
import Foundation
import HTTPClient
import OpenMusicEventDatabase
import OpenMusicEventSource
import OpenMusicEventSourceClone
import OpenMusicEventSourceEditing
import OpenMusicEventWhiteLabel

public extension WhiteLabelSourceImportClient {
    static var live: Self {
        Self { organizerID, descriptor in
            @Dependency(\.defaultDatabase) var database
            @Dependency(\.httpClient) var httpClient
            @Dependency(\.tangledSourceArchiveExtractor) var archiveExtractor
            @Dependency(\.tangledSourceImport) var tangledSourceImport
            @Dependency(\.uuid) var uuid

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
                        organizerID: organizerID,
                        ref: descriptor.version ?? "HEAD"
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
}
