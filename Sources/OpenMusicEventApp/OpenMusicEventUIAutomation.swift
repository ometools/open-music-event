import ATProto
import ATProtoOAuth
import ComposableAtmosphere
import Dependencies
import Foundation
import OpenMusicEventAuthentication
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData
import SwiftUI

private enum OpenMusicEventUIAutomationKey: DependencyKey {
    static let liveValue = OpenMusicEventUIAutomation.normal
    static let testValue = OpenMusicEventUIAutomation.normal
}

extension DependencyValues {
    var openMusicEventUIAutomation: OpenMusicEventUIAutomation {
        get { self[OpenMusicEventUIAutomationKey.self] }
        set { self[OpenMusicEventUIAutomationKey.self] = newValue }
    }
}

enum OpenMusicEventUIAutomationFixture {
    /// Saturday, August 1, 2026 at 6:15 PM in Testival's America/Denver time zone.
    /// One frozen clock keeps Browse, Schedule, and performance indicators in agreement.
    static let now = Date(timeIntervalSince1970: 1_785_629_700)
    static let canonicalEventID = Event.ID(
        "at://did:web:example.com/events.openmusic.event/3mrdbziccpcah"
    )!
    static let canonicalMainProgramID = Program.ID(
        "at://did:web:example.com/events.openmusic.program/3mrdbziccpcai"
    )!
    static let canonicalWorkshopProgramID = Program.ID(
        "at://did:web:example.com/events.openmusic.program/3mrdbziccpcaj"
    )!
    static let canonicalSaturdayID = Schedule.ID(
        "at://did:web:example.com/events.openmusic.schedule/3mrdbziccpcak"
    )!
    static let canonicalSundayID = Schedule.ID(
        "at://did:web:example.com/events.openmusic.schedule/3mrdbziccpcal"
    )!
    static let canonicalMeadowID = EventPlace.ID(
        "at://did:web:example.com/events.openmusic.eventPlace/3mrdbziccpcam"
    )!
    static let canonicalCanopyID = EventPlace.ID(
        "at://did:web:example.com/events.openmusic.eventPlace/3mrdbziccpcan"
    )!
    static let canonicalWorkshopGroveID = EventPlace.ID(
        "at://did:web:example.com/events.openmusic.eventPlace/3mrdbziccpcao"
    )!
    static let canonicalArtistOneID = Contributor.ID(
        "at://did:web:example.com/events.openmusic.contributor/3mrdbziccpcap"
    )!
    static let canonicalArtistTwoID = Contributor.ID(
        "at://did:web:example.com/events.openmusic.contributor/3mrdbziccpcaq"
    )!
    static let canonicalArtistThreeID = Contributor.ID(
        "at://did:web:example.com/events.openmusic.contributor/3mrdbziccpcar"
    )!
    static let canonicalFacilitatorFourID = Contributor.ID(
        "at://did:web:example.com/events.openmusic.contributor/3mrdbziccpcas"
    )!
    static let canonicalOpeningSetID = ProgramItem.ID(
        "at://did:web:example.com/events.openmusic.programItem/3mrdbziccpcrt"
    )!
    static let canonicalSunsetSessionID = ProgramItem.ID(
        "at://did:web:example.com/events.openmusic.programItem/3mrdbziccpcru"
    )!
    static let canonicalCollaborativeSetID = ProgramItem.ID(
        "at://did:web:example.com/events.openmusic.programItem/3mrdbziccpcrv"
    )!
    static let canonicalLateNightSetID = ProgramItem.ID(
        "at://did:web:example.com/events.openmusic.programItem/3mrdbziccpcrw"
    )!
    static let canonicalMovementWorkshopID = ProgramItem.ID(
        "at://did:web:example.com/events.openmusic.programItem/3mrdbziccpcrx"
    )!
    static let canonicalMorningSetID = ProgramItem.ID(
        "at://did:web:example.com/events.openmusic.programItem/3mrdbziccpcry"
    )!
    static let canonicalClosingSetID = ProgramItem.ID(
        "at://did:web:example.com/events.openmusic.programItem/3mrdbziccpcrz"
    )!
    static let canonicalGeneralCategoryID = Social.Category.ID(
        "at://did:web:example.com/social.ome.category/3mrdbziccpcah"
    )!
    static let canonicalSafetyCategoryID = Social.Category.ID(
        "at://did:web:example.com/social.ome.category/3mrdbziccpcai"
    )!
    static let canonicalWelcomePostID = Social.Post.ID(
        "at://did:web:example.com/social.ome.post/3mrdbziccpcah"
    )!
    static let ownerID = DID("did:web:example.com")!

    static func prepareAccount(for profile: OpenMusicEventUIAutomation) {
        let sessionStore: OAuth.SessionStore
        let selectedAccountID: Atmosphere.Account.ID?
        if profile == .workspace {
            let session = OAuth.Session(
                accountID: Atmosphere.Account.ID(ownerID),
                pdsHost: "owner.ui.test",
                tokenEndpoint: OAuth.AuthorizationServer.TokenEndpoint(
                    URL(string: "https://owner.ui.test/oauth/token")!
                ),
                scope: OAuth.Scope(rawValue: OAuth.Permission.atproto.rawValue),
                accessToken: OAuth.AccessToken(rawValue: "workspace-ui-access-token"),
                refreshToken: OAuth.RefreshToken(rawValue: "workspace-ui-refresh-token"),
                dpopKey: OAuth.DPOP.Key()
            )
            selectedAccountID = session.accountID
            sessionStore = OAuth.SessionStore(
                selectedAccountID: session.accountID,
                sessions: [ownerID: session]
            )
        } else {
            selectedAccountID = nil
            sessionStore = OAuth.SessionStore()
        }
        OpenMusicEventOAuth.sessionStore.withLock { $0 = sessionStore }
        OpenMusicEventOAuth.selectedSessionID.withLock { $0 = selectedAccountID }
    }
    static func prepareCanonicalRecords(into database: any DatabaseWriter) async throws {
        guard let publicMapURL = Bundle.module.url(forResource: "public-map", withExtension: "png", subdirectory: "TestivalSource/events/testival-2026/maps"),
              let safetyMapURL = Bundle.module.url(forResource: "safety-map", withExtension: "png", subdirectory: "TestivalSource/events/testival-2026/maps")
        else {
            throw URLError(.fileDoesNotExist)
        }
        let publicMapBlob = try stageLocalImageBlob(
            Data(contentsOf: publicMapURL), mimeType: .png
        )
        let safetyMapBlob = try stageLocalImageBlob(
            Data(contentsOf: safetyMapURL), mimeType: .png
        )
        let event = try Event(
            id: canonicalEventID,
            name: "Testival 2026",
            createdAt: "2026-07-01T12:00:00Z",
            timeZone: TimeZone(identifier: "America/Denver")!,
            description: "A compact, deterministic festival that exercises the attendee experience without network content.",
            start: .known(.day(.init(value: LocalDate("2026-08-01")!))),
            end: .known(.day(.init(value: LocalDate("2026-08-02")!))),
            status: .known(.scheduled),
            mode: .known(.inPerson),
            locations: [
                .init(
                    name: "1 Fixture Road, Denver, CO 80202",
                    description: "Enter through the blue gate beside the community garden.",
                    locators: [
                        .known(.address(.init(
                            country: "US", postalCode: "80202", region: "CO",
                            locality: "Denver", street: "1 Fixture Road"
                        ))),
                        .known(.geo(.init(latitude: "39.7392", longitude: "-104.9903"))),
                    ]
                ),
            ],
            links: [
                .init(
                    url: URL(string: "https://example.com/testival")!,
                    title: "Testival Website",
                    role: .known(.website(.init()))
                ),
                .init(
                    url: URL(string: "tel:555-0100")!,
                    title: "Event Information",
                    description: "Attendee information and accessibility support.",
                    role: .known(.contact(.init()))
                ),
                .init(
                    url: URL(string: "https://example.com/testival/report")!,
                    title: "Report an Incident",
                    description: "Contact the Testival safety team.",
                    role: .known(.reporting(.init()))
                ),
            ],
            programs: [canonicalMainProgramID, canonicalWorkshopProgramID],
            schedules: [canonicalSaturdayID, canonicalSundayID],
            categories: [canonicalGeneralCategoryID, canonicalSafetyCategoryID],
            siteMap: .init(
                title: "Testival Grounds",
                styles: [
                    .init(
                        id: "public", title: "Public",
                        image: .init(
                            source: .known(.blob(publicMapBlob)),
                            role: .known(.siteMap)
                        )
                    ),
                    .init(
                        id: "safety", title: "Safety",
                        image: .init(
                            source: .known(.blob(safetyMapBlob)),
                            role: .known(.siteMap)
                        )
                    ),
                ],
                defaultStyleID: "public"
            )
        )
        let mainProgram = try Program(
            id: canonicalMainProgramID,
            event: canonicalEventID,
            title: "Schedule",
            createdAt: "2026-07-01T12:00:00Z",
            eventPlaces: [canonicalMeadowID, canonicalCanopyID]
        )
        var workshopProgram = try Program(
            id: canonicalWorkshopProgramID,
            event: canonicalEventID,
            title: "Workshops",
            createdAt: "2026-07-01T12:00:00Z",
            eventPlaces: [canonicalWorkshopGroveID]
        )
        workshopProgram.icon = .personDoingYoga
        let saturday = try Schedule(
            id: canonicalSaturdayID,
            event: canonicalEventID,
            date: LocalDate("2026-08-01")!,
            createdAt: "2026-07-01T12:00:00Z",
            title: "Saturday"
        )
        let sunday = try Schedule(
            id: canonicalSundayID,
            event: canonicalEventID,
            date: LocalDate("2026-08-02")!,
            createdAt: "2026-07-01T12:00:00Z",
            title: "Sunday"
        )
        var meadow = try EventPlace(
            id: canonicalMeadowID,
            event: canonicalEventID,
            name: "Meadow",
            createdAt: "2026-07-01T12:00:00Z"
        )
        var meadowStage = EventPlace.Kind.Stage()
        meadowStage.color = OME.Color(rawValue: 0x00aaee)
        meadowStage.sortIndex = 0
        meadowStage.lineup = [canonicalArtistOneID, canonicalArtistTwoID]
        meadow.kind = .known(.stage(meadowStage))

        var canopy = try EventPlace(
            id: canonicalCanopyID,
            event: canonicalEventID,
            name: "Canopy",
            createdAt: "2026-07-01T12:00:00Z"
        )
        var canopyStage = EventPlace.Kind.Stage()
        canopyStage.color = OME.Color(rawValue: 0x8b5cf6)
        canopyStage.sortIndex = 1
        canopyStage.lineup = [canonicalArtistTwoID, canonicalArtistThreeID]
        canopy.kind = .known(.stage(canopyStage))

        var workshopGrove = try EventPlace(
            id: canonicalWorkshopGroveID,
            event: canonicalEventID,
            name: "Workshop Grove",
            createdAt: "2026-07-01T12:00:00Z"
        )
        var workshopStage = EventPlace.Kind.Stage()
        workshopStage.color = OME.Color(rawValue: 0xf59e0b)
        workshopStage.category = "workshop"
        workshopStage.sortIndex = 2
        workshopStage.lineup = [canonicalFacilitatorFourID]
        workshopGrove.kind = .known(.stage(workshopStage))

        let artistOne = try Contributor(
            id: canonicalArtistOneID,
            event: canonicalEventID,
            name: "Artist One",
            createdAt: "2026-07-01T12:00:00Z",
            description: "Artist One opens Testival in the Meadow and returns for the closing collaboration.",
            roles: [.known(.performer)],
            links: [.init(
                url: URL(string: "https://example.com/artists/artist-one")!,
                platform: .known(.website)
            )]
        )
        let artistTwo = try Contributor(
            id: canonicalArtistTwoID,
            event: canonicalEventID,
            name: "Artist Two",
            createdAt: "2026-07-01T12:00:00Z",
            description: "Artist Two performs at both music stages and contributes visuals to the collaborative set.",
            roles: [.known(.performer)],
            links: [
                .init(
                    url: URL(string: "https://open.spotify.com/artist/testival-artist-two")!,
                    platform: .known(.spotify)
                ),
                .init(
                    url: URL(string: "https://example.com/artists/artist-two")!,
                    platform: .known(.website)
                ),
            ]
        )
        let artistThree = try Contributor(
            id: canonicalArtistThreeID,
            event: canonicalEventID,
            name: "Artist Three",
            createdAt: "2026-07-01T12:00:00Z",
            description: "Artist Three plays the late-night set and joins the Testival closing set.",
            roles: [.known(.performer)],
            links: [.init(
                url: URL(string: "https://example.com/artists/artist-three")!,
                platform: .known(.website)
            )]
        )
        let facilitatorFour = try Contributor(
            id: canonicalFacilitatorFourID,
            event: canonicalEventID,
            name: "Facilitator Four",
            createdAt: "2026-07-01T12:00:00Z",
            description: "Facilitator Four leads Testival's attendee workshop in Workshop Grove.",
            roles: [.known(.facilitator)],
            links: [.init(
                url: URL(string: "https://example.com/workshops/facilitator-four")!,
                platform: .known(.website)
            )]
        )

        let movementWorkshop = try ProgramItem(
            id: canonicalMovementWorkshopID,
            event: canonicalEventID,
            program: canonicalWorkshopProgramID,
            title: "Movement Workshop",
            createdAt: "2026-07-01T12:00:00Z",
            description: "A guided arrival practice for Testival attendees.",
            schedule: canonicalSaturdayID,
            eventPlace: canonicalWorkshopGroveID,
            startsAt: "2026-08-01T23:00:00Z",
            endsAt: "2026-08-02T00:30:00Z",
            credits: [.init(
                name: "Facilitator Four", contributor: canonicalFacilitatorFourID,
                role: "facilitator"
            )]
        )
        let openingSet = try ProgramItem(
            id: canonicalOpeningSetID,
            event: canonicalEventID,
            program: canonicalMainProgramID,
            title: "Opening Set",
            createdAt: "2026-07-01T12:00:00Z",
            schedule: canonicalSaturdayID,
            eventPlace: canonicalMeadowID,
            startsAt: "2026-08-02T00:00:00Z",
            endsAt: "2026-08-02T01:00:00Z",
            credits: [.init(
                name: "Artist One", contributor: canonicalArtistOneID,
                role: "musician"
            )]
        )
        let sunsetSession = try ProgramItem(
            id: canonicalSunsetSessionID,
            event: canonicalEventID,
            program: canonicalMainProgramID,
            title: "Sunset Session",
            createdAt: "2026-07-01T12:00:00Z",
            schedule: canonicalSaturdayID,
            eventPlace: canonicalCanopyID,
            startsAt: "2026-08-02T00:30:00Z",
            endsAt: "2026-08-02T02:00:00Z",
            credits: [.init(
                name: "Artist Two", contributor: canonicalArtistTwoID,
                role: "dj"
            )]
        )
        let collaborativeSet = try ProgramItem(
            id: canonicalCollaborativeSetID,
            event: canonicalEventID,
            program: canonicalMainProgramID,
            title: "Collaborative Set",
            createdAt: "2026-07-01T12:00:00Z",
            description: "Music and live visuals meet in the Meadow.",
            schedule: canonicalSaturdayID,
            eventPlace: canonicalMeadowID,
            startsAt: "2026-08-02T02:00:00Z",
            endsAt: "2026-08-02T03:30:00Z",
            credits: [
                .init(name: "Artist One", contributor: canonicalArtistOneID, role: "musician"),
                .init(
                    name: "Artist Two", contributor: canonicalArtistTwoID,
                    billing: .known(.supporting), role: "visual-artist"
                ),
            ]
        )
        let lateNightSet = try ProgramItem(
            id: canonicalLateNightSetID,
            event: canonicalEventID,
            program: canonicalMainProgramID,
            title: "Late Night Set",
            createdAt: "2026-07-01T12:00:00Z",
            description: "A cross-midnight performance under the Canopy.",
            schedule: canonicalSaturdayID,
            eventPlace: canonicalCanopyID,
            startsAt: "2026-08-02T05:30:00Z",
            endsAt: "2026-08-02T07:00:00Z",
            credits: [.init(
                name: "Artist Three", contributor: canonicalArtistThreeID,
                role: "musician"
            )]
        )
        let morningSet = try ProgramItem(
            id: canonicalMorningSetID,
            event: canonicalEventID,
            program: canonicalMainProgramID,
            title: "Morning Set",
            createdAt: "2026-07-01T12:00:00Z",
            schedule: canonicalSundayID,
            eventPlace: canonicalMeadowID,
            startsAt: "2026-08-02T16:00:00Z",
            endsAt: "2026-08-02T17:00:00Z",
            credits: [.init(
                name: "Artist Two", contributor: canonicalArtistTwoID,
                role: "dj"
            )]
        )
        let closingSet = try ProgramItem(
            id: canonicalClosingSetID,
            event: canonicalEventID,
            program: canonicalMainProgramID,
            title: "Closing Set",
            createdAt: "2026-07-01T12:00:00Z",
            schedule: canonicalSundayID,
            eventPlace: canonicalCanopyID,
            startsAt: "2026-08-03T01:00:00Z",
            endsAt: "2026-08-03T02:30:00Z",
            credits: [
                .init(name: "Artist Three", contributor: canonicalArtistThreeID, role: "musician"),
                .init(
                    name: "Artist One", contributor: canonicalArtistOneID,
                    billing: .known(.supporting), role: "musician"
                ),
            ]
        )
        let generalCategory = try Social.Category(
            id: canonicalGeneralCategoryID,
            event: canonicalEventID,
            name: "General",
            createdAt: "2026-07-01T12:00:00Z",
            description: "Official Testival announcements and attendee updates.",
            pinnedPosts: [canonicalWelcomePostID],
            defaultNotificationState: .known(.subscribed),
            notificationsRequired: false
        )
        let safetyCategory = try Social.Category(
            id: canonicalSafetyCategoryID,
            event: canonicalEventID,
            name: "Safety",
            createdAt: "2026-07-01T12:00:00Z",
            description: "Time-sensitive safety information for attendees.",
            defaultNotificationState: .known(.subscribed),
            notificationsRequired: true
        )
        var welcomePost = try Social.Post(
            id: canonicalWelcomePostID,
            title: "Welcome to Testival",
            text: "Testival is ready. Check the schedule, find your stage, and review safety information before the first set.",
            event: canonicalEventID,
            category: canonicalGeneralCategoryID,
            createdAt: "2026-07-01T12:00:00Z"
        )
        welcomePost.embed = Social.Post.Embed([
            "$type": "app.bsky.embed.external",
            "external": .object([
                "uri": "https://example.com/testival/guide",
                "title": "Testival guide",
                "description": "Plan your festival day.",
            ]),
        ])
        let welcomePostWithEmbed = welcomePost

        let graph = EventRecordGraph(
            event: event,
            programs: [mainProgram, workshopProgram],
            schedules: [saturday, sunday],
            places: [meadow, canopy, workshopGrove],
            contributors: [artistOne, artistTwo, artistThree, facilitatorFour],
            items: [
                movementWorkshop, openingSet, sunsetSession, collaborativeSet,
                lateNightSet, morningSet, closingSet,
            ],
            categories: [generalCategory, safetyCategory]
        )
        try welcomePostWithEmbed.validateGraph(event: event, category: generalCategory)
        try await database.write { db in
            guard try Event.find(canonicalEventID).fetchOne(db) == nil else { return }
            try graph.upsert(in: db)
            try Social.Post.upsert { welcomePostWithEmbed }.execute(db)
        }
    }
}

enum OpenMusicEventApplicationPreparation: Equatable {
    case preparing
    case ready
    case failed(String)
}

/// The platform entry view keeps ordinary launches immediate while giving UI automation one
/// deterministic preparation gate. The existing application root is unchanged after canonical
/// records have been inserted into its isolated automation database.
/* SKIP @bridge */@MainActor public struct OpenMusicEventApplicationEntryView: View {
    let uiAutomation: OpenMusicEventUIAutomation
    @State var preparation: OpenMusicEventApplicationPreparation

    /* SKIP @bridge */public init() {
        @Dependency(\.openMusicEventUIAutomation) var uiAutomation
        self.uiAutomation = uiAutomation
        self._preparation = State(
            initialValue: uiAutomation == .attendee || uiAutomation == .workspace
                ? .preparing : .ready
        )
    }

    public var body: some View {
        Group {
            switch preparation {
            case .preparing:
                VStack(spacing: 12.0) {
                    ProgressView()
                    Text("Preparing Testival")
                }
                .accessibilityIdentifier("view.ui-automation-preparing")

            case .ready:
                OpenMusicEventApplicationRootView()

            case let .failed(message):
                VStack(alignment: .leading, spacing: 12.0) {
                    Text("Unable to Prepare Testival")
                        .font(.headline)
                    Text(message)
                        .font(.body)
                }
                .padding()
                .accessibilityIdentifier("view.ui-automation-failed")
            }
        }
        .task {
            await prepareFixtureIfNeeded()
        }
    }

    func prepareFixtureIfNeeded() async {
        guard uiAutomation == .attendee || uiAutomation == .workspace,
              preparation == .preparing
        else { return }
        @Dependency(\.defaultDatabase) var database
        do {
            try await OpenMusicEventUIAutomationFixture.prepareCanonicalRecords(into: database)
            OpenMusicEventUIAutomationFixture.prepareAccount(for: uiAutomation)
            preparation = .ready
        } catch {
            preparation = .failed(String(describing: error))
        }
    }
}
