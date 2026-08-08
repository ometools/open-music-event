import ATProto
import Foundation
import OpenMusicEventAppViewServer
import OpenMusicEventLexicon
import Testing

struct WellKnownFilesTests {
    @Test
    func mapsSupportedWellKnownPaths() {
        #expect(WellKnownFiles.fileName(for: "/.well-known/atproto-did") == "atproto-did")
        #expect(WellKnownFiles.fileName(for: "/.well-known/apple-app-site-association") == "apple-app-site-association")
        #expect(WellKnownFiles.fileName(for: "/apple-app-site-association") == "apple-app-site-association")
        #expect(WellKnownFiles.fileName(for: "/.well-known/assetlinks.json") == "assetlinks.json")
        #expect(WellKnownFiles.fileName(for: "/.well-known/did.json") == "did.json")
        #expect(WellKnownFiles.fileName(for: "/.well-known/oauth-client-metadata.json") == nil)
        #expect(WellKnownFiles.fileName(for: "/.well-known/unknown") == nil)
    }

    @Test
    func rejectsUnsafeHosts() {
        #expect(WellKnownFiles.isAllowedHost("openmusicevent.app"))
        #expect(WellKnownFiles.isAllowedHost("alice.ome.social"))
        #expect(!WellKnownFiles.isAllowedHost("../openmusicevent.app"))
        #expect(!WellKnownFiles.isAllowedHost("openmusicevent.app/../../private"))
    }

    @Test
    func readsRepoBackedWellKnownFile() throws {
        let root = Bundle.module.resourceURL!.appendingPathComponent("WellKnown")
        let files = WellKnownFiles(rootDirectory: root)
        let file = try #require(try files.file(
            host: "openmusicevent.app",
            requestPath: "/.well-known/atproto-did"
        ))

        #expect(file.contentType == "text/plain; charset=utf-8")
        #expect(String(decoding: file.data, as: UTF8.self).hasPrefix("did:"))
    }

    @Test
    func publishesAppViewServiceInProductionDIDDocument() throws {
        let configuration = AppViewConfiguration()
        let files = WellKnownFiles(rootDirectory: configuration.wellKnownRoot)
        let file = try #require(try files.file(
            host: "openmusicevent.app",
            requestPath: "/.well-known/did.json"
        ))
        let document = try JSONDecoder().decode(PublishedDIDDocument.self, from: file.data)
        let service = try #require(document.service.first { $0.type == .openMusicEventAppView })

        #expect(document.id == OME.Comms.SubmitPost.serviceReference.did)
        #expect(service.id.fragment == OME.Comms.SubmitPost.serviceReference.service)
        #expect(service.serviceEndpoint == URL(string: "https://openmusicevent.app"))
    }
}

private struct PublishedDIDDocument: Decodable {
    let id: DID
    let service: [Service]

    struct Service: Decodable {
        let id: Identifier
        let type: Kind
        let serviceEndpoint: URL

        enum Kind: String, Decodable {
            case atprotoPDS = "AtprotoPersonalDataServer"
            case openMusicEventAppView = "OpenMusicEventAppView"
        }

        struct Identifier: Decodable {
            let fragment: DID.URL.Fragment

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                let value = try container.decode(String.self)
                guard value.first == "#", let fragment = DID.URL.Fragment(String(value.dropFirst())) else {
                    throw DecodingError.dataCorruptedError(
                        in: container,
                        debugDescription: "DID service identifiers must be fragments."
                    )
                }
                self.fragment = fragment
            }
        }
    }
}
