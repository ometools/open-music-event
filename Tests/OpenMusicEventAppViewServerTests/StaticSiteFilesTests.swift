import Foundation
import OpenMusicEventAppViewServer
import Testing

struct StaticSiteFilesTests {
    @Test
    func mapsSupportedStaticSitePaths() {
        #expect(StaticSiteFiles.relativePath(for: "/") == "index.html")
        #expect(StaticSiteFiles.relativePath(for: "/index.html") == "index.html")
        #expect(StaticSiteFiles.relativePath(for: "/about") == "about.html")
        #expect(StaticSiteFiles.relativePath(for: "/about.html") == "about.html")
        #expect(StaticSiteFiles.relativePath(for: "/styles.css") == "styles.css")
        #expect(StaticSiteFiles.relativePath(for: "/favicon.png") == "favicon.png")
        #expect(StaticSiteFiles.relativePath(for: "/apple-touch-icon.png") == "apple-touch-icon.png")
        #expect(StaticSiteFiles.relativePath(for: "/.well-known/oauth-client-metadata.json") == ".well-known/oauth-client-metadata.json")
        #expect(StaticSiteFiles.relativePath(for: "/assets/ome-mark.jpg") == "assets/ome-mark.jpg")
    }

    @Test
    func rejectsUnsupportedStaticSitePaths() {
        #expect(StaticSiteFiles.relativePath(for: "/.well-known/atproto-did") == nil)
        #expect(StaticSiteFiles.relativePath(for: "/assets/../private.txt") == nil)
        #expect(StaticSiteFiles.relativePath(for: "/assets/icons/ome.png") == nil)
    }

    @Test
    func readsRepoBackedStaticSiteFile() throws {
        let root = Bundle.module.resourceURL!.appendingPathComponent("Site")
        let files = StaticSiteFiles(rootDirectory: root)
        let file = try #require(try files.file(requestPath: "/"))

        #expect(file.path == "index.html")
        #expect(file.contentType == "text/html; charset=utf-8")
        #expect(String(decoding: file.data, as: UTF8.self).contains("OpenMusicEvent"))
    }

    @Test
    func globeRequestsServerClusteredViewportItems() throws {
        let files = StaticSiteFiles(rootDirectory: AppViewConfiguration().siteRoot)
        let file = try #require(try files.file(requestPath: "/assets/app.js"))
        let javaScript = String(decoding: file.data, as: UTF8.self)

        #expect(javaScript.contains("app.openmusicevent.calendar.getMapItems"))
        #expect(javaScript.contains("url.searchParams.set(\"zoom\""))
        #expect(!javaScript.contains("cluster: true"))
        #expect(!javaScript.contains("getClusterLeaves"))
        #expect(!javaScript.contains("getClusterExpansionZoom"))
    }
}
