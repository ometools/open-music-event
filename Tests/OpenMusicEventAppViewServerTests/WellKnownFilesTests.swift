import Foundation
import OpenMusicEventAppViewServer
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
}
