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
                let request = OpenMusicEventSourceValidationRequest(
                    source: source,
                    organizerID: organizerID,
                    ref: descriptor.version ?? "HEAD"
                )
                let result = try await withDependencies {
                    $0.tangledSourceCheckout = .archive
                } operation: {
                    try await tangledSourceImport.importSource(request)
                }
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
