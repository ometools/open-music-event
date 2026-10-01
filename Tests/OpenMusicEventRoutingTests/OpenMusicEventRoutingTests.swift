import CustomDump
import OpenMusicEventLexicon
import OpenMusicEventRouting
import Testing

struct OpenMusicEventRoutingTests {
    @Test func `parses appview paths into typed routes`() throws {
        expectNoDifference(
            openMusicEventPathRouter.parse("/"),
            OpenMusicEventRoute.site(.home)
        )
        expectNoDifference(
            openMusicEventPathRouter.parse("/index.html"),
            .site(.index)
        )
        expectNoDifference(
            openMusicEventPathRouter.parse("/styles.css"),
            .site(.stylesheet)
        )
        expectNoDifference(
            openMusicEventPathRouter.parse("/favicon.png"),
            .site(.favicon)
        )
        expectNoDifference(
            openMusicEventPathRouter.parse("/apple-touch-icon.png"),
            .site(.appleTouchIcon)
        )
        expectNoDifference(
            openMusicEventPathRouter.parse("/assets/ome-mark.jpg"),
            .site(.asset(OpenMusicEventSiteAsset(rawValue: "ome-mark.jpg")))
        )
        expectNoDifference(
            openMusicEventPathRouter.parse("/.well-known/atproto-did"),
            .wellKnown(.atprotoDID)
        )
        expectNoDifference(
            openMusicEventPathRouter.parse("/apple-app-site-association"),
            .appleAppSiteAssociation
        )
        expectNoDifference(
            openMusicEventPathRouter.parse("/healthz"),
            .health
        )
        expectNoDifference(
            openMusicEventPathRouter.parse("/readyz"),
            .ready
        )
    }

    @Test func `prints typed routes into canonical paths`() {
        let router = OpenMusicEventRouter()

        expectNoDifference(router.path(for: .site(.home)), "/")
        expectNoDifference(router.path(for: .site(.index)), "/index.html")
        expectNoDifference(router.path(for: .site(.stylesheet)), "/styles.css")
        expectNoDifference(router.path(for: .site(.favicon)), "/favicon.png")
        expectNoDifference(router.path(for: .site(.appleTouchIcon)), "/apple-touch-icon.png")
        expectNoDifference(
            router.path(for: .site(.asset(OpenMusicEventSiteAsset(rawValue: "ome-mark.jpg")))),
            "/assets/ome-mark.jpg"
        )
        expectNoDifference(router.path(for: .wellKnown(.atprotoDID)), "/.well-known/atproto-did")
        expectNoDifference(router.path(for: .wellKnown(.assetLinks)), "/.well-known/assetlinks.json")
        expectNoDifference(router.path(for: .appleAppSiteAssociation), "/apple-app-site-association")
        expectNoDifference(router.path(for: .health), "/healthz")
        expectNoDifference(router.path(for: .ready), "/readyz")
    }

    @Test func `normalizes incoming request paths before parsing`() {
        let router = OpenMusicEventRouter()

        expectNoDifference(
            router.route(
                OpenMusicEventIncomingRequest(
                    host: OpenMusicEventHost(rawValue: "localhost"),
                    path: OpenMusicEventPath(rawValue: "styles.css")
                )
            ),
            .site(.stylesheet)
        )
        expectNoDifference(
            router.route(
                OpenMusicEventIncomingRequest(
                    host: OpenMusicEventHost(rawValue: "localhost"),
                    path: OpenMusicEventPath(rawValue: "")
                )
            ),
            .site(.home)
        )
    }

    @Test func `rejects unsafe single path components`() {
        let router = OpenMusicEventRouter()

        #expect(
            router.route(
                OpenMusicEventIncomingRequest(
                    host: OpenMusicEventHost(rawValue: "localhost"),
                    path: OpenMusicEventPath(rawValue: "/assets/../private.txt")
                )
            ) == nil
        )
        #expect(
            router.route(
                OpenMusicEventIncomingRequest(
                    host: OpenMusicEventHost(rawValue: "localhost"),
                    path: OpenMusicEventPath(rawValue: "/assets/icons/ome.png")
                )
            ) == nil
        )
        #expect(
            router.route(
                OpenMusicEventIncomingRequest(
                    host: OpenMusicEventHost(rawValue: "localhost"),
                    path: OpenMusicEventPath(rawValue: "/.well-known/../secret")
                )
            ) == nil
        )
    }

    @Test func `generates canonical urls`() {
        let router = OpenMusicEventRouter()

        expectNoDifference(
            router.url(for: .site(.home)).absoluteString,
            "https://openmusicevent.app/"
        )
        expectNoDifference(
            router.url(for: .wellKnown(.atprotoDID)).absoluteString,
            "https://openmusicevent.app/.well-known/atproto-did"
        )
        expectNoDifference(
            router.url(
                for: .site(.stylesheet),
                host: OpenMusicEventHost(rawValue: "preview.openmusicevent.app"),
                scheme: "http"
            )
            .absoluteString,
            "http://preview.openmusicevent.app/styles.css"
        )
    }

    @Test func `prints the canonical channel notification path`() throws {
        let eventID = try #require(Event.ID(
            "at://did:plc:example/events.openmusic.event/3mrdbziccpcah"
        ))
        let channelID = try #require(Social.Category.ID(
            "at://did:plc:example/social.ome.category/3mrdbziccpcaj"
        ))

        expectNoDifference(
            openMusicEventEventPathRouter.communicationChannelPath(
                eventID: eventID,
                channelID: channelID
            ),
            "/records/did%3Aplc%3Aexample/3mrdbziccpcah/communications/at%3A%2F%2Fdid%3Aplc%3Aexample%2Fsocial.ome.category%2F3mrdbziccpcaj"
        )
    }

    @Test func `routes an exact branded event claim by host`() {
        let claim = BrandedEventRouteClaim(
            host: "wickedwoods.openmusicevent.app",
            eventClaim: "2026",
            eventID: wickedWoodsEventID
        )
        let router = OpenMusicEventRouter(
            configuration: OpenMusicEventRoutingConfiguration(
                brandedEventRouteClaims: [claim]
            )
        )

        expectNoDifference(
            router.route(
                OpenMusicEventIncomingRequest(
                    host: OpenMusicEventHost(rawValue: "wickedwoods.openmusicevent.app"),
                    path: OpenMusicEventPath(rawValue: "/events/2026")
                )
            ),
            .brandedEvent(claim)
        )
        expectNoDifference(
            router.url(for: .brandedEvent(claim)).absoluteString,
            "https://wickedwoods.openmusicevent.app/events/2026"
        )
    }

    @Test func `rejects a branded event route on another host claim or nested path`() {
        let claim = BrandedEventRouteClaim(
            host: "wickedwoods.openmusicevent.app",
            eventClaim: "2026",
            eventID: wickedWoodsEventID
        )
        let router = OpenMusicEventRouter(
            configuration: OpenMusicEventRoutingConfiguration(
                brandedEventRouteClaims: [claim]
            )
        )

        #expect(router.route(.init(
            host: .init(rawValue: "openmusicevent.app"),
            path: .init(rawValue: "/events/2026")
        )) == nil)
        #expect(router.route(.init(
            host: .init(rawValue: "wickedwoods.openmusicevent.app"),
            path: .init(rawValue: "/events/2025")
        )) == nil)
        #expect(router.route(.init(
            host: .init(rawValue: "wickedwoods.openmusicevent.app"),
            path: .init(rawValue: "/events/2026/schedule")
        )) == nil)
    }
}

private let wickedWoodsEventID = Event.ID(
    "at://did:plc:5df2u7ief6m6tn77jznicxob/events.openmusic.event/3mrdbziccpcah"
)!
