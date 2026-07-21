import ATProto
import Dependencies
import Foundation
import OpenMusicEventAppEventViewer
import OpenMusicEventLexicon
import OpenMusicEventSourceClone
import OpenMusicEventWhiteLabel
import XRPCClient

public enum WhiteLabelCanonicalSourceRegistryError: Equatable, LocalizedError, Sendable {
    case missingPDSHost(String)
    case unexpectedRecordURI(String)

    public var errorDescription: String? {
        switch self {
        case let .missingPDSHost(did):
            "No PDS host was available for \(did)."
        case let .unexpectedRecordURI(uri):
            "The canonical source record came from an unexpected URI: \(uri)."
        }
    }
}

public extension WhiteLabelSourceRegistryClient {
    static var canonicalSourceRecord: Self {
        Self { organizerID in
            @Dependency(Atmosphere.Account.Client.self) var accountClient
            @Dependency(XRPC.Client.self) var xrpcClient

            let (account, didDocument) = try await accountClient.resolveDID(organizerID)
            let did = account.id.rawValue
            guard let pdsHost = didDocument.pdsHost else {
                throw WhiteLabelCanonicalSourceRegistryError.missingPDSHost(did.description)
            }

            let record = try await xrpcClient.run(
                TangledGetRecordRequest<OME.SourceRecord>(
                    repo: did.description,
                    collection: OME.SourceRecord.nsid.rawValue,
                    rkey: OME.SourceRecord.canonicalRecordKey,
                    pdsHost: pdsHost
                )
            )
            let expectedURI = "at://\(did)/\(OME.SourceRecord.nsid.rawValue)/\(OME.SourceRecord.canonicalRecordKey)"
            guard record.uri.description == expectedURI else {
                throw WhiteLabelCanonicalSourceRegistryError.unexpectedRecordURI(record.uri.description)
            }

            return WhiteLabelSourceDescriptor(
                reference: .source(record.value.reference),
                version: record.value.ref
            )
        }
    }
}

public enum OpenMusicEvent {
    public enum WhiteLabel {

        public static func prepareDependencies(
            _ dependencies: inout DependencyValues
        ) throws {
            try OME.prepareDependencies(&dependencies)
            dependencies.authoringPolicy = .loginRequired
            dependencies.openMusicEventAutomaticallyRefreshesStoredAuthentication = false
            dependencies.whiteLabelSourceRegistry = .canonicalSourceRecord
            dependencies.whiteLabelSourceImport = .live
        }
    }
}
