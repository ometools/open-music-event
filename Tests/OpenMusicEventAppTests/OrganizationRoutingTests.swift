import Testing
@testable import OpenMusicEvent
import URLRouting
import Foundation

@Suite
@MainActor
struct OrganizationRoutingTests {



    @Test(
        arguments: [
            ("/orgs", AppRoute.organizationList),

            // Organization root
            ("/orgs/acme", AppRoute.organization("acme", .root)),
            ("/orgs/omega-inc", AppRoute.organization("omega-inc", .root)),

            // Event base (no nested event route)
            ("/orgs/acme/events/fest-2025", AppRoute.organization("acme", .event("fest-2025", nil))),

            // EventRoute: artists
            ("/orgs/acme/events/fest-2025/artists", AppRoute.organization("acme", .event("fest-2025", .artists))),

            // EventRoute: artist(id)
            ("/orgs/acme/events/fest-2025/artists/headliner", AppRoute.organization("acme", .event("fest-2025", .artist("headliner")))),

            // EventRoute: stages
            ("/orgs/acme/events/fest-2025/stages", AppRoute.organization("acme", .event("fest-2025", .stages))),

            // EventRoute: stage(id)
            ("/orgs/acme/events/fest-2025/stages/main-stage", AppRoute.organization("acme", .event("fest-2025", .stage("main-stage")))),

            // EventRoute: schedule
            ("/orgs/acme/events/fest-2025/schedule", AppRoute.organization("acme", .event("fest-2025", .schedule))),

            // EventRoute: communications
            ("/orgs/acme/events/fest-2025/communications", AppRoute.organization("acme", .event("fest-2025", .communications))),

            // EventRoute: channel(id)
            ("/orgs/acme/events/fest-2025/communications/announcements", AppRoute.organization("acme", .event("fest-2025", .channel("announcements")))),
        ]

    )
    func assertParsePrint(path: String, expected: AppRoute) async throws {
        try #require(!path.isEmpty)

        let request = try #require(URLRequestData(string: path))

        let parsed = try appRouter.parse(request)
        #expect(parsed == expected, "Parsed route did not match expected")

        let printed = appRouter.path(for: parsed)

        #expect(path == printed, "Printed path did not match expected")
    }


}

