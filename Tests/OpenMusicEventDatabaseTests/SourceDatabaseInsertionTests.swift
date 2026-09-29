import ATProto
import ComposableWorkspace
import CustomDump
import Dependencies
import FileTree
import Foundation
import GRDB
@testable import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceClone
@testable import OpenMusicEventSourceEditing
import SQLiteData
import SourceControlClient
import SourceEditing
import Synchronization
import Testing

@Suite(.serialized)
struct SourceDatabaseInsertionTests {
    @Test
    func buildsInsertionRowsFromSourceRepository() throws {
        let source = try makeSourceRepository()
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let sourceProvenance = tangledSourceProvenance("testival-source")
        let resolvedEventID = "testival-source-testival-2026"
        let insertion = try OME.SourceDatabaseInsertion(
            .init(
                source: source,
                organizerID: organizerID,
                sourceProvenance: sourceProvenance
            )
        )
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let scheduleDate = try #require(LocalDate("2026-08-01"))

        expectNoDifference(
            insertion.organizers,
            [
                OME.Organizer.Draft(id: organizerID)
            ]
        )
        expectNoDifference(
            insertion.calendars,
            [
                OME.Calendar.Draft(
                    id: calendarID(organizerID: organizerID),
                    name: "Events",
                    description: nil,
                    images: nil
                )
            ]
        )
        expectNoDifference(
            insertion.calendarEntries,
            [
                OME.CalendarEntry.Draft(
                    id: calendarEntryID(resolvedEventID, organizerID: organizerID),
                    event: OME.Event.reference(
                        id: eventID(resolvedEventID, organizerID: organizerID)
                    ),
                    createdAt: .distantPast,
                    note: nil,
                    pinned: false
                )
            ]
        )
        expectNoDifference(
            insertion.events.map(\.id),
            [
                eventID(resolvedEventID, organizerID: organizerID)
            ]
        )
        expectNoDifference(
            insertion.eventSourceProvenances,
            [
                OME.SourceDatabaseInsertion.EventSourceProvenance(
                    eventID: eventID(resolvedEventID, organizerID: organizerID),
                    eventIDOrigin: .inferred,
                    source: sourceProvenance,
                    sourceEventDirectory: "testival-2026"
                )
            ]
        )
        expectNoDifference(
            insertion.eventOrganizers,
            [
                OME.EventOrganizer.Draft(
                    id: .init(
                        organizerID: organizerID,
                        eventID: id(resolvedEventID),
                        eventOrganizerID: organizerID
                    )
                )
            ]
        )
        expectNoDifference(
            insertion.stages.map(\.id),
            [stageID("meadow", eventID: resolvedEventID, organizerID: organizerID)]
        )
        expectNoDifference(
            insertion.contributors.map(\.id),
            [contributorID("artist-one", eventID: resolvedEventID, organizerID: organizerID)]
        )
        expectNoDifference(
            insertion.channels.map(\.id),
            [channelID("general", eventID: resolvedEventID, organizerID: organizerID)]
        )
        expectNoDifference(
            insertion.posters.map(\.id),
            [posterID("lineup", eventID: resolvedEventID, organizerID: organizerID)]
        )
        expectNoDifference(
            insertion.schedules,
            [
                OME.Schedule.Draft(
                    id: scheduleID("saturday", eventID: resolvedEventID, organizerID: organizerID),
                    date: scheduleDate,
                    startsAt: try localDate(scheduleDate, atHour: 18, in: timeZone),
                    endsAt: try localDate(scheduleDate, atHour: 22, minute: 30, in: timeZone),
                    customTitle: "Saturday"
                )
            ]
        )
        expectNoDifference(
            insertion.scheduleItems,
            [
                OME.ScheduleItem.Draft(
                    id: scheduleItemID("opening-set", eventID: resolvedEventID, organizerID: organizerID),
                    stageID: id("meadow"),
                    scheduleID: id("saturday"),
                    kind: .known(.performance),
                    startTime: try localDate(scheduleDate, atHour: 18, in: timeZone),
                    endTime: try localDate(scheduleDate, atHour: 19, in: timeZone),
                    title: "Opening Set",
                    description: nil
                ),
                OME.ScheduleItem.Draft(
                    id: scheduleItemID("saturday-meadow-2", eventID: resolvedEventID, organizerID: organizerID),
                    stageID: id("meadow"),
                    scheduleID: id("saturday"),
                    kind: .known(.performance),
                    startTime: try localDate(scheduleDate, atHour: 20, in: timeZone),
                    endTime: try localDate(scheduleDate, atHour: 21, in: timeZone),
                    title: "Late Set",
                    description: nil
                ),
                OME.ScheduleItem.Draft(
                    id: scheduleItemID("closing-set", eventID: resolvedEventID, organizerID: organizerID),
                    stageID: id("meadow"),
                    scheduleID: id("saturday"),
                    kind: .known(.performance),
                    startTime: try localDate(scheduleDate, atHour: 21, in: timeZone),
                    endTime: try localDate(scheduleDate, atHour: 22, in: timeZone),
                    title: "Closing Set",
                    description: nil
                ),
            ]
        )
        expectNoDifference(
            insertion.scheduleItemPerformanceDetails.map(\.recordings),
            [[], [], []]
        )
        expectNoDifference(
            insertion.scheduleItemContributors,
            [
                OME.ScheduleItem.Contributor.Draft(
                    id: .init(
                        scheduleItemID: scheduleItemID("opening-set", eventID: resolvedEventID, organizerID: organizerID),
                        sortIndex: 0
                    ),
                    contributorID: id("artist-one"),
                    anonymousName: nil
                ),
                OME.ScheduleItem.Contributor.Draft(
                    id: .init(
                        scheduleItemID: scheduleItemID("saturday-meadow-2", eventID: resolvedEventID, organizerID: organizerID),
                        sortIndex: 0
                    ),
                    contributorID: nil,
                    anonymousName: "Guest Artist"
                ),
            ]
        )
        expectNoDifference(
            insertion.relationships,
            [
                OME.Relationship(
                    subject: .identity(did: organizerID),
                    role: .organizer,
                    object: .record(.init(eventID: eventID(resolvedEventID, organizerID: organizerID))),
                    createdAt: pendingRelationshipCreatedAt
                ),
                OME.Relationship(
                    subject: .record(.init(contributorID: contributorID("artist-one", eventID: resolvedEventID, organizerID: organizerID))),
                    role: .contributor,
                    object: .record(.init(eventID: eventID(resolvedEventID, organizerID: organizerID))),
                    createdAt: pendingRelationshipCreatedAt
                ),
                OME.Relationship(
                    subject: .record(.init(contributorID: contributorID("artist-one", eventID: resolvedEventID, organizerID: organizerID))),
                    role: .performer,
                    object: .record(.init(performanceID: performanceID("opening-set", eventID: resolvedEventID, organizerID: organizerID))),
                    createdAt: pendingRelationshipCreatedAt
                ),
            ]
        )
    }

    @Test
    func sourceInsertionPersistsNamedSiteMapStylesWithStableAssetKeys() async throws {
        var source = try makeSourceRepository()
        source.events[0].components.siteMap = SiteMapDTO(
            title: "Festival Map",
            defaultStyleID: id("festival"),
            styles: [
                SiteMapDTO.Style(
                    id: id("festival"),
                    title: "Festival",
                    image: SiteMapDTO.Style.Image(
                        source: .url(URL(string: "https://example.com/maps/festival.png")!)
                    )
                ),
                SiteMapDTO.Style(
                    id: id("camping"),
                    title: "Camping",
                    image: SiteMapDTO.Style.Image(
                        source: .url(URL(string: "https://example.com/maps/camping.png")!)
                    )
                ),
            ]
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let insertion = try OME.SourceDatabaseInsertion(
            .init(source: source, organizerID: organizerID)
        )
        let siteMap = try #require(insertion.siteMaps.first)
        let database = try makeCoreDatabase()

        // Importing source installs the named styles beside their owning event record.
        try await insertion.insert(into: database)

        let persistedSiteMap = try await database.read { db in
            try OME.Event.SiteMap.find(siteMap.id).fetchOne(db)
        }
        expectNoDifference(persistedSiteMap, siteMap)
        #expect(siteMap.defaultStyle?.title == "Festival")
        #expect(siteMap.styles[0].image.assetKey != siteMap.styles[1].image.assetKey)
        #expect(siteMap.styles[0].image.assetKey?.contains("site-map|festival") == true)
        #expect(siteMap.styles[1].image.assetKey?.contains("site-map|camping") == true)

        // Replacing or removing the owning event cannot leave stale map configuration behind.
        try await database.write { db in
            try OME.Event.find(
                OME.Event.ID(
                    organizerID: siteMap.id.organizerID,
                    eventID: siteMap.id.eventID
                )
            )
            .delete()
            .execute(db)
        }
        let removedSiteMap = try await database.read { db in
            try OME.Event.SiteMap.find(siteMap.id).fetchOne(db)
        }
        #expect(removedSiteMap == nil)
    }

    @Test
    func unknownScheduleItemKindRoundTripsThroughCanonicalSQLiteRows() async throws {
        let unknownKind = "app.example.scheduleItem#future"
        let source = try makeSourceRepository(
            scheduleItems: [
                "meadow": [
                    .init(
                        kind: .unknown(.string(unknownKind)),
                        id: id("future-item"),
                        title: "Future Item",
                        description: "Defined by another scheduler.",
                        startTime: "18:00",
                        endTime: "19:00"
                    )
                ]
            ]
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let insertion = try OME.SourceDatabaseInsertion(
            .init(source: source, organizerID: organizerID)
        )

        expectNoDifference(
            insertion.scheduleItems.map(\.kind),
            [.unknown(.string(unknownKind))]
        )
        expectNoDifference(insertion.scheduleItemPerformanceDetails, [])

        let database = try makeCoreDatabase()
        try await insertion.insert(into: database)
        let persisted = try await database.read { db in
            try OME.ScheduleItem.fetchAll(db)
        }
        expectNoDifference(
            persisted.map(\.kind),
            [.unknown(.string(unknownKind))]
        )
    }

    @Test
    func importsSingletonStageWhenSourceEventHasNoStages() throws {
        var source = try makeSourceRepository()
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        source.events[0].components.stages = nil
        source.events[0].components.schedules = nil

        let insertion = try OME.SourceDatabaseInsertion(
            .init(source: source, organizerID: organizerID)
        )

        expectNoDifference(
            insertion.stages,
            [
                OME.Stage.Draft(
                    id: stageID("stage", eventID: "testival-2026", organizerID: organizerID),
                    name: "Stage",
                    color: 0x336699,
                    category: nil,
                    sortIndex: nil,
                    images: nil,
                    systemIconName: nil,
                    iconShortCode: nil,
                    lineup: nil
                )
            ]
        )
    }

    @Test
    func importsReferencedSingletonStageWhenSourceEventHasNoStageFiles() throws {
        var source = try makeSourceRepository()
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        source.events[0].components.stages = nil

        let insertion = try OME.SourceDatabaseInsertion(
            .init(source: source, organizerID: organizerID)
        )

        expectNoDifference(
            insertion.stages,
            [
                OME.Stage.Draft(
                    id: stageID("meadow", eventID: "testival-2026", organizerID: organizerID),
                    name: "Meadow",
                    color: 0x336699,
                    category: nil,
                    sortIndex: nil,
                    images: nil,
                    systemIconName: nil,
                    iconShortCode: nil,
                    lineup: nil
                )
            ]
        )
    }

    @Test
    func importsInlineSingletonScheduleFromEventSource() throws {
        let source = try makeInlineScheduleSourceRepository()
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let insertion = try OME.SourceDatabaseInsertion(
            .init(source: source, organizerID: organizerID)
        )
        let scheduleDate = try #require(LocalDate("2026-08-01"))

        expectNoDifference(
            insertion.schedules,
            [
                OME.Schedule.Draft(
                    id: scheduleID("schedule", eventID: "testival-2026", organizerID: organizerID),
                    date: scheduleDate,
                    startsAt: nil,
                    endsAt: nil,
                    customTitle: nil
                )
            ]
        )
        expectNoDifference(
            insertion.scheduleItems.map(\.id?.scheduleItemID.rawValue.rawValue),
            [
                "opening-set",
                "schedule-meadow-2",
                "closing-set",
            ]
        )
        expectNoDifference(
            insertion.scheduleItems.map(\.scheduleID?.rawValue.rawValue),
            [
                "schedule",
                "schedule",
                "schedule",
            ]
        )
    }

    @Test
    func throwsWhenInlineSingletonScheduleHasNoDateSource() throws {
        var source = try makeInlineScheduleSourceRepository()
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        source.events[0].components.event.startDate = nil

        do {
            _ = try OME.SourceDatabaseInsertion(
                .init(source: source, organizerID: organizerID)
            )
            Issue.record("Expected inline schedule without event date to throw.")
        } catch let error as OME.SourceDatabaseInsertion.Error {
            expectNoDifference(
                error,
                .missingInlineScheduleDate(
                    OME.Event.ID(
                        organizerID: organizerID,
                        eventID: id("testival-2026")
                    )
                )
            )
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func throwsWhenInlineSingletonScheduleDuplicatesFileScheduleID() throws {
        var source = try makeInlineScheduleSourceRepository()
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let scheduleDate = try #require(LocalDate("2026-08-01"))
        source.events[0].components.schedules = [
            try FileContent(
                fileName: "schedule",
                fileType: nil,
                data: ScheduleDTO(
                    id: nil,
                    eventID: nil,
                    date: scheduleDate,
                    startsAt: nil,
                    endsAt: nil,
                    customTitle: nil,
                    scheduleItems: [:]
                )
            )
        ]

        do {
            _ = try OME.SourceDatabaseInsertion(
                .init(source: source, organizerID: organizerID)
            )
            Issue.record("Expected duplicate inline and file schedule IDs to throw.")
        } catch let error as OME.SourceDatabaseInsertion.Error {
            expectNoDifference(
                error,
                .duplicateScheduleID(
                    scheduleID("schedule", eventID: "testival-2026", organizerID: organizerID)
                )
            )
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func sourceCommunicationPostsPersistAndDeleteOnReimport() async throws {
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let sourceProvenance = tangledSourceProvenance("post-source")
        let resolvedEventID = "post-source-postival-2026"
        let source = try sourceRepositoryWithCommunicationPosts(includePosts: true)
        let insertion = try OME.SourceDatabaseInsertion(
            .init(
                source: source,
                organizerID: organizerID,
                sourceProvenance: sourceProvenance
            )
        )

        expectNoDifference(
            insertion.communicationPosts.map(\.id),
            [
                OME.SourceDatabaseInsertion.CommunicationPost.ID(
                    organizerID: organizerID,
                    eventID: id(resolvedEventID),
                    channelID: id("general"),
                    postID: id("arrival")
                ),
                OME.SourceDatabaseInsertion.CommunicationPost.ID(
                    organizerID: organizerID,
                    eventID: id(resolvedEventID),
                    channelID: id("general"),
                    postID: id("welcome")
                ),
            ]
        )
        expectNoDifference(
            insertion.communicationPosts.map(\.sortIndex),
            [0, 1]
        )

        let database = try SQLiteData.defaultDatabase()
        try await insertion.migrateAndInsert(into: database)

        let posts = try await database.read { db in
            try CommsPost
                .order { $0.sortIndex }
                .fetchAll(db)
        }
        expectNoDifference(
            posts,
            [
                CommsPost(
                    id: CommsPost.ID(
                        organizerID: organizerID,
                        eventID: id(resolvedEventID),
                        channelID: id("general"),
                        postID: CommsPost.PostID("arrival")
                    ),
                    title: "Arrival Info",
                    contents: "Use the north gate.",
                    timestamp: nil,
                    isPinned: false,
                    sortIndex: 0
                ),
                CommsPost(
                    id: CommsPost.ID(
                        organizerID: organizerID,
                        eventID: id(resolvedEventID),
                        channelID: id("general"),
                        postID: CommsPost.PostID("welcome")
                    ),
                    title: "Welcome",
                    contents: "Welcome to Postival.",
                    headerImageURL: URL(string: "https://example.com/welcome.png")!,
                    images: [
                        OME.ImageAsset(
                            assetKey: "\(organizerID)|\(resolvedEventID)|communicationPost|general|welcome|photo|default",
                            source: .url(URL(string: "https://example.com/welcome-gallery.png")!),
                            role: .photo,
                            renderKind: .fullImage,
                            materializationPolicy: .lazy
                        )
                    ],
                    timestamp: nil,
                    isPinned: true,
                    sortIndex: 1
                ),
            ]
        )

        let reimport = try OME.SourceDatabaseInsertion(
            .init(
                source: sourceRepositoryWithCommunicationPosts(includePosts: false),
                organizerID: organizerID,
                sourceProvenance: sourceProvenance
            )
        )
        try await reimport.migrateAndInsert(into: database)

        let postCount = try await database.read { db in
            try CommsPost.fetchCount(db)
        }
        expectNoDifference(postCount, 0)
    }

    @Test
    func sourceContributorDIDImportsIntoContributorRecord() throws {
        let did = try #require(DID("did:plc:artist123"))
        let source = try makeSourceRepository(contributorDID: did)
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))

        let insertion = try OME.SourceDatabaseInsertion(
            .init(
                source: source,
                organizerID: organizerID,
                sourceProvenance: tangledSourceProvenance("testival-source")
            )
        )

        let contributor = try #require(insertion.contributors.first)
        #expect(contributor.did == did)
    }

    @Test
    func sourceRepositoryReportingLinksPersistToEventRowInOrder() async throws {
        let reportingLinks = [
            OME.Event.ReportingLink(
                name: "Report an Incident",
                url: URL(string: "https://example.org/report")!,
                description: "Use this form to report an event safety concern."
            ),
            OME.Event.ReportingLink(
                name: "Accessibility Help",
                url: URL(string: "https://example.org/accessibility")!,
                description: nil
            ),
        ]
        let source = try makeSourceRepository(reportingLinks: reportingLinks)
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let insertion = try OME.SourceDatabaseInsertion(
            .init(
                source: source,
                organizerID: organizerID,
                sourceProvenance: tangledSourceProvenance("testival-source")
            )
        )
        let eventID = try #require(insertion.events.first?.id)

        expectNoDifference(
            insertion.events.first?.reportingLinks,
            reportingLinks
        )

        let database = try makeCoreDatabase()
        try await insertion.insert(into: database)

        let insertedEvent = try await database.read { db in
            try OME.Event.where { $0.id.eq(eventID) }
                .fetchOne(db)
        }
        expectNoDifference(
            try #require(insertedEvent?.reportingLinks),
            reportingLinks
        )
    }

    @Test
    func buildsDefaultCalendarFromSourceMetadata() throws {
        let source = try makeSourceRepository(
            calendar: CalendarDTO(
                name: "Testival Calendar",
                description: "Organizer default calendar."
            )
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))

        let insertion = try OME.SourceDatabaseInsertion(
            .init(
                source: source,
                organizerID: organizerID,
                sourceProvenance: tangledSourceProvenance("testival-source")
            )
        )

        expectNoDifference(
            insertion.calendars,
            [
                OME.Calendar.Draft(
                    id: calendarID(organizerID: organizerID),
                    name: "Testival Calendar",
                    description: "Organizer default calendar.",
                    images: nil
                )
            ]
        )
    }

    @Test
    func buildsDefaultCalendarImagesFromSourceMetadata() throws {
        let source = try makeSourceRepository(
            calendar: CalendarDTO(
                name: "Testival Calendar",
                description: "Organizer default calendar.",
                images: [
                    SourceImageAsset(
                        source: .url(URL(string: "https://example.com/calendar-hero.jpg")!),
                        role: .hero,
                        renderKind: .fullImage,
                        materializationPolicy: .lazy
                    ),
                    SourceImageAsset(
                        source: .url(URL(string: "https://example.com/calendar-logo.png")!),
                        role: .logo,
                        renderKind: .transparent,
                        materializationPolicy: .lazy
                    ),
                ]
            )
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))

        let insertion = try OME.SourceDatabaseInsertion(
            .init(
                source: source,
                organizerID: organizerID,
                sourceProvenance: tangledSourceProvenance("testival-source")
            )
        )

        let calendar = try #require(insertion.calendars.first)
        #expect(calendar.images?.imageAsset(role: .hero)?.url?.absoluteString == "https://example.com/calendar-hero.jpg")
        #expect(calendar.images?.imageAsset(role: .logo)?.url?.absoluteString == "https://example.com/calendar-logo.png")
    }

    @Test
    func actorOnlyPerformancesCreatePerformanceContributorRowsWithoutContributors() throws {
        let actor = try #require(OME.Contributor.Actor("ARTIST.BSKY.SOCIAL"))
        var source = try makeSourceRepository(
            scheduleItems: [
                "meadow": [
                    .init(
                        id: id("actor-set"),
                        title: "Actor Set",
                        startTime: "18:00",
                        endTime: "19:00",
                        contributors: [
                            .init(subject: .actor(actor))
                        ]
                    )
                ]
            ]
        )
        source.events[0].components.contributors = nil
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))

        let insertion = try OME.SourceDatabaseInsertion(
            .init(
                source: source,
                organizerID: organizerID,
                sourceProvenance: tangledSourceProvenance("testival-source")
            )
        )

        expectNoDifference(insertion.contributors, [])
        expectNoDifference(
            insertion.scheduleItemContributors,
            [
                OME.ScheduleItem.Contributor.Draft(
                    id: .init(
                        scheduleItemID: scheduleItemID("actor-set", eventID: "testival-source-testival-2026", organizerID: organizerID),
                        sortIndex: 0
                    ),
                    contributorID: nil,
                    anonymousName: nil,
                    contributorActor: OME.Contributor.Actor("artist.bsky.social")
                )
            ]
        )
    }

    @Test
    func didOnlyPerformanceContributorsCreateIdentityRelationships() throws {
        let artistID = try #require(DID("did:plc:artist123"))
        let actor = try #require(OME.Contributor.Actor("did:plc:artist123"))
        var source = try makeSourceRepository(
            scheduleItems: [
                "meadow": [
                    .init(
                        id: id("did-set"),
                        title: "DID Set",
                        startTime: "18:00",
                        endTime: "19:00",
                        contributors: [
                            .init(subject: .actor(actor))
                        ]
                    )
                ]
            ]
        )
        source.events[0].components.contributors = nil
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let resolvedEventID = "testival-source-testival-2026"

        let insertion = try OME.SourceDatabaseInsertion(
            .init(
                source: source,
                organizerID: organizerID,
                sourceProvenance: tangledSourceProvenance("testival-source")
            )
        )

        expectNoDifference(insertion.contributors, [OME.Contributor.Draft]())
        expectNoDifference(
            insertion.relationships,
            [
                OME.Relationship(
                    subject: .identity(did: organizerID),
                    role: .organizer,
                    object: .record(.init(eventID: eventID(resolvedEventID, organizerID: organizerID))),
                    createdAt: pendingRelationshipCreatedAt
                ),
                OME.Relationship(
                    subject: .identity(did: artistID),
                    role: .performer,
                    object: .record(.init(performanceID: performanceID("did-set", eventID: resolvedEventID, organizerID: organizerID))),
                    createdAt: pendingRelationshipCreatedAt
                ),
            ]
        )
    }

    @Test
    func performanceContributorCreditsPreserveBillingRoleAndOrder() throws {
        let source = try makeSourceRepository(
            scheduleItems: [
                "meadow": [
                    .init(
                        id: id("credited-set"),
                        title: "Credited Set",
                        startTime: "18:00",
                        endTime: "19:00",
                        contributors: [
                            .init(
                                subject: .id(id("artist-one")),
                                role: "dj"
                            ),
                            .init(
                                subject: .name("Dance Crew"),
                                billing: .supporting,
                                role: "dancer"
                            ),
                        ]
                    )
                ]
            ]
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))

        let insertion = try OME.SourceDatabaseInsertion(
            .init(
                source: source,
                organizerID: organizerID,
                sourceProvenance: tangledSourceProvenance("testival-source")
            )
        )

        expectNoDifference(
            insertion.scheduleItemContributors,
            [
                OME.ScheduleItem.Contributor.Draft(
                    id: .init(
                        scheduleItemID: scheduleItemID("credited-set", eventID: "testival-source-testival-2026", organizerID: organizerID),
                        sortIndex: 0
                    ),
                    contributorID: id("artist-one"),
                    anonymousName: nil,
                    billing: .primary,
                    role: "dj"
                ),
                OME.ScheduleItem.Contributor.Draft(
                    id: .init(
                        scheduleItemID: scheduleItemID("credited-set", eventID: "testival-source-testival-2026", organizerID: organizerID),
                        sortIndex: 1
                    ),
                    contributorID: nil,
                    anonymousName: "Dance Crew",
                    billing: .supporting,
                    role: "dancer"
                ),
            ]
        )
        expectNoDifference(
            insertion.relationships,
            [
                OME.Relationship(
                    subject: .identity(did: organizerID),
                    role: .organizer,
                    object: .record(.init(eventID: eventID("testival-source-testival-2026", organizerID: organizerID))),
                    createdAt: pendingRelationshipCreatedAt
                ),
                OME.Relationship(
                    subject: .record(.init(contributorID: contributorID("artist-one", eventID: "testival-source-testival-2026", organizerID: organizerID))),
                    role: .contributor,
                    object: .record(.init(eventID: eventID("testival-source-testival-2026", organizerID: organizerID))),
                    createdAt: pendingRelationshipCreatedAt
                ),
                OME.Relationship(
                    subject: .record(.init(contributorID: contributorID("artist-one", eventID: "testival-source-testival-2026", organizerID: organizerID))),
                    role: .dj,
                    object: .record(.init(performanceID: performanceID("credited-set", eventID: "testival-source-testival-2026", organizerID: organizerID))),
                    createdAt: pendingRelationshipCreatedAt
                ),
            ]
        )
    }

    @Test
    func scheduleContributorListingCreatesContributorsFromNames() throws {
        let source = try makeSourceRepository(
            eventPolicies: scheduleContributorListingPolicy(),
            includeDefaultContributor: false,
            scheduleItems: [
                "meadow": [
                    .init(
                        id: id("guest-set"),
                        title: "Guest Set",
                        startTime: "18:00",
                        endTime: "19:00",
                        contributors: [
                            .init(subject: .name("Guest Artist"))
                        ]
                    )
                ]
            ]
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))

        let insertion = try OME.SourceDatabaseInsertion(
            .init(
                source: source,
                organizerID: organizerID,
                sourceProvenance: tangledSourceProvenance("testival-source")
            )
        )

        expectNoDifference(
            insertion.contributors,
            [
                OME.Contributor.Draft(
                    id: contributorID(
                        "schedule-name-Guest%20Artist",
                        eventID: "testival-source-testival-2026",
                        organizerID: organizerID
                    ),
                    name: "Guest Artist",
                    bio: nil,
                    images: nil,
                    links: nil
                )
            ]
        )
        expectNoDifference(
            insertion.scheduleItemContributors,
            [
                OME.ScheduleItem.Contributor.Draft(
                    id: .init(
                        scheduleItemID: scheduleItemID("guest-set", eventID: "testival-source-testival-2026", organizerID: organizerID),
                        sortIndex: 0
                    ),
                    contributorID: id("schedule-name-Guest%20Artist"),
                    anonymousName: "Guest Artist"
                )
            ]
        )
        expectNoDifference(
            insertion.relationships,
            [
                OME.Relationship(
                    subject: .identity(did: organizerID),
                    role: .organizer,
                    object: .record(.init(eventID: eventID("testival-source-testival-2026", organizerID: organizerID))),
                    createdAt: pendingRelationshipCreatedAt
                ),
                OME.Relationship(
                    subject: .record(.init(contributorID: contributorID("schedule-name-Guest%20Artist", eventID: "testival-source-testival-2026", organizerID: organizerID))),
                    role: .contributor,
                    object: .record(.init(eventID: eventID("testival-source-testival-2026", organizerID: organizerID))),
                    createdAt: pendingRelationshipCreatedAt
                ),
                OME.Relationship(
                    subject: .record(.init(contributorID: contributorID("schedule-name-Guest%20Artist", eventID: "testival-source-testival-2026", organizerID: organizerID))),
                    role: .performer,
                    object: .record(.init(performanceID: performanceID("guest-set", eventID: "testival-source-testival-2026", organizerID: organizerID))),
                    createdAt: pendingRelationshipCreatedAt
                ),
            ]
        )
    }

    @Test
    func throwsWhenScheduleReferencesMissingContributorID() throws {
        let source = try makeSourceRepository(
            includeDefaultContributor: false,
            scheduleItems: [
                "meadow": [
                    .init(
                        id: id("missing-contributor-set"),
                        title: "Missing Contributor Set",
                        startTime: "18:00",
                        endTime: "19:00",
                        contributors: [
                            .init(subject: .id(id("missing-artist")))
                        ]
                    )
                ]
            ]
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))

        do {
            _ = try OME.SourceDatabaseInsertion(
                .init(
                    source: source,
                    organizerID: organizerID,
                    sourceProvenance: tangledSourceProvenance("testival-source")
                )
            )
            Issue.record("Expected missing schedule contributor ID to throw.")
        } catch let error as OME.SourceDatabaseInsertion.Error {
            expectNoDifference(
                error,
                .missingScheduleContributorID(
                    scheduleID: scheduleID(
                        "saturday",
                        eventID: "testival-source-testival-2026",
                        organizerID: organizerID
                    ),
                    stageID: id("meadow"),
                    scheduleItemIndex: 1,
                    contributorID: id("missing-artist")
                )
            )
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func scheduleContributorListingCreatesContributorsFromActors() throws {
        let actor = try #require(OME.Contributor.Actor("ARTIST.BSKY.SOCIAL"))
        let source = try makeSourceRepository(
            eventPolicies: scheduleContributorListingPolicy(),
            includeDefaultContributor: false,
            scheduleItems: [
                "meadow": [
                    .init(
                        id: id("actor-set"),
                        title: "Actor Set",
                        startTime: "18:00",
                        endTime: "19:00",
                        contributors: [
                            .init(subject: .actor(actor))
                        ]
                    )
                ]
            ]
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))

        let insertion = try OME.SourceDatabaseInsertion(
            .init(
                source: source,
                organizerID: organizerID,
                sourceProvenance: tangledSourceProvenance("testival-source")
            )
        )

        expectNoDifference(
            insertion.contributors,
            [
                OME.Contributor.Draft(
                    id: contributorID(
                        "schedule-actor-artist.bsky.social",
                        eventID: "testival-source-testival-2026",
                        organizerID: organizerID
                    ),
                    name: "artist.bsky.social",
                    bio: nil,
                    images: nil,
                    links: nil
                )
            ]
        )
        expectNoDifference(
            insertion.scheduleItemContributors,
            [
                OME.ScheduleItem.Contributor.Draft(
                    id: .init(
                        scheduleItemID: scheduleItemID("actor-set", eventID: "testival-source-testival-2026", organizerID: organizerID),
                        sortIndex: 0
                    ),
                    contributorID: id("schedule-actor-artist.bsky.social"),
                    anonymousName: nil,
                    contributorActor: actor
                )
            ]
        )
    }

    @Test
    func explicitContributorsWinOverScheduleContributorListing() throws {
        let source = try makeSourceRepository(
            eventPolicies: scheduleContributorListingPolicy(),
            scheduleItems: [
                "meadow": [
                    .init(
                        id: id("artist-set"),
                        title: "Artist Set",
                        startTime: "18:00",
                        endTime: "19:00",
                        contributors: [
                            .init(subject: .name("Artist One"))
                        ]
                    )
                ]
            ]
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))

        let insertion = try OME.SourceDatabaseInsertion(
            .init(
                source: source,
                organizerID: organizerID,
                sourceProvenance: tangledSourceProvenance("testival-source")
            )
        )

        expectNoDifference(
            insertion.contributors.map(\.id),
            [
                contributorID(
                    "artist-one",
                    eventID: "testival-source-testival-2026",
                    organizerID: organizerID
                )
            ]
        )
        expectNoDifference(
            insertion.scheduleItemContributors,
            [
                OME.ScheduleItem.Contributor.Draft(
                    id: .init(
                        scheduleItemID: scheduleItemID("artist-set", eventID: "testival-source-testival-2026", organizerID: organizerID),
                        sortIndex: 0
                    ),
                    contributorID: id("artist-one"),
                    anonymousName: "Artist One"
                )
            ]
        )
    }

    @Test
    func sourceInsertionReplacesGeneratedDefaultCalendarEntries() async throws {
        let firstSource = try makeSourceRepository(
            eventDirectoryName: "first-event",
            eventName: "First Event"
        )
        let secondSource = try makeSourceRepository(
            eventDirectoryName: "second-event",
            eventName: "Second Event"
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let sourceProvenance = tangledSourceProvenance("testival-source", ref: "main")
        let firstInsertion = try OME.SourceDatabaseInsertion(
            .init(
                source: firstSource,
                organizerID: organizerID,
                sourceProvenance: sourceProvenance
            )
        )
        let secondInsertion = try OME.SourceDatabaseInsertion(
            .init(
                source: secondSource,
                organizerID: organizerID,
                sourceProvenance: sourceProvenance
            )
        )
        let database = try makeCoreDatabase()
        let beforeImport = Date()
        try await firstInsertion.insert(into: database)
        try await secondInsertion.insert(into: database)
        let afterImport = Date()

        let calendar = try await database.read { db in
            try OME.Calendar.fetchOne(db)
        }
        let entries = try await database.read { db in
            try OME.CalendarEntry.fetchAll(db)
        }

        expectNoDifference(
            calendar,
            OME.Calendar(
                id: calendarID(organizerID: organizerID),
                name: "Events",
                description: nil,
                images: nil
            )
        )
        expectNoDifference(
            entries,
            [
                OME.CalendarEntry(
                    id: calendarEntryID("testival-source-second-event", organizerID: organizerID),
                    event: OME.Event.reference(
                        id: eventID("testival-source-second-event", organizerID: organizerID)
                    ),
                    createdAt: entries.first?.createdAt ?? .distantPast,
                    note: nil,
                    pinned: false
                )
            ]
        )
        let createdAt = try #require(entries.first?.createdAt)
        #expect(createdAt >= beforeImport)
        #expect(createdAt <= afterImport)
    }

    @Test
    func sourceEditingListsSourceRecordTypes() {
        struct SourceProjectionAssertion: Equatable {
            var tableID: String
            var fileFamily: OpenMusicEventSourceProjection.FileFamily
        }

        expectNoDifference(
            OME.sourceEventProjections.map { ObjectIdentifier($0.tableType) },
            [
                ObjectIdentifier(OME.Event.self),
                ObjectIdentifier(OME.Stage.self),
                ObjectIdentifier(OME.Contributor.self),
                ObjectIdentifier(OME.Schedule.self),
                ObjectIdentifier(OME.ScheduleItem.self),
                ObjectIdentifier(OME.ScheduleItem.PerformanceDetails.self),
                ObjectIdentifier(OME.ScheduleItem.Contributor.self),
                ObjectIdentifier(OME.Channel.self),
                ObjectIdentifier(CommsPost.self),
                ObjectIdentifier(OME.Poster.self),
            ]
        )
        expectNoDifference(
            OME.sourceRecordTableTypes.map(ObjectIdentifier.init),
            OME.sourceEventProjections.map { ObjectIdentifier($0.tableType) }
        )
        expectNoDifference(
            OME.sourceRecordTypes.map(\.descriptor.id),
            OME.sourceEventProjections.map(\.recordType.descriptor.id)
        )
        expectNoDifference(
            OME.sourceTableDescriptors.map(\.id),
            OME.sourceEventProjections.map(\.recordType.descriptor.id)
        )
        expectNoDifference(
            OME.sourceProjections.map {
                SourceProjectionAssertion(
                    tableID: $0.recordType.descriptor.id,
                    fileFamily: $0.fileFamily
                )
            },
            [
                SourceProjectionAssertion(tableID: OME.Calendar.tableName, fileFamily: .calendar),
                SourceProjectionAssertion(
                    tableID: WorkspaceRelationshipRecord.tableName,
                    fileFamily: .collaborator
                ),
                SourceProjectionAssertion(tableID: OME.Event.tableName, fileFamily: .event),
                SourceProjectionAssertion(tableID: OME.Stage.tableName, fileFamily: .stage),
                SourceProjectionAssertion(tableID: OME.Contributor.tableName, fileFamily: .contributor),
                SourceProjectionAssertion(tableID: OME.Schedule.tableName, fileFamily: .schedule),
                SourceProjectionAssertion(tableID: OME.ScheduleItem.tableName, fileFamily: .schedule),
                SourceProjectionAssertion(tableID: OME.ScheduleItem.PerformanceDetails.tableName, fileFamily: .schedule),
                SourceProjectionAssertion(tableID: OME.ScheduleItem.Contributor.tableName, fileFamily: .schedule),
                SourceProjectionAssertion(tableID: OME.Channel.tableName, fileFamily: .channel),
                SourceProjectionAssertion(tableID: CommsPost.tableName, fileFamily: .communicationPost),
                SourceProjectionAssertion(tableID: OME.Poster.tableName, fileFamily: .poster),
            ]
        )
    }

    @Test
    func sourceChangeGroupCountsTotals() {
        let group = SourceChangeGroup(
            id: "stages",
            displayName: "Stage",
            added: 1,
            modified: 2,
            deleted: 3
        )

        #expect(group.displayName == "Stage")
        #expect(group.totalCount == 6)
    }

    @Test
    func eventWorkspaceSummaryReportsSourceBaselineAvailability() async throws {
        let source = try makeSourceRepository()
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let openedEventID = eventID("testival-source-testival-2026", organizerID: organizerID)
        let sourceProvenance = tangledSourceProvenance("testival-source", ref: "main")
        let insertion = try OME.SourceDatabaseInsertion(
            .init(
                source: source,
                organizerID: organizerID,
                sourceProvenance: sourceProvenance
            )
        )
        let database = try makeCoreDatabase()

        let notInWorkspace = try EventWorkspaceSummary.query(
            eventID: openedEventID,
            using: database
        )

        expectNoDifference(
            notInWorkspace,
            EventWorkspaceSummary(
                eventID: openedEventID,
                availability: .notInWorkspace,
                groups: []
            )
        )

        try await insertion.insert(into: database)

        let workspaceNeedsPreparation = try EventWorkspaceSummary.query(
            eventID: openedEventID,
            using: database
        )

        expectNoDifference(
            workspaceNeedsPreparation,
            EventWorkspaceSummary(
                eventID: openedEventID,
                availability: .workspaceNeedsPreparation,
                groups: []
            )
        )

        let baselineDatabase = try defaultBaselineDatabase()
        defer { try? FileManager.default.removeItem(atPath: baselineDatabase.path) }
        try await insertion.migrateAndInsert(into: baselineDatabase.database)
        let sourceProvenanceRecord = try await database.read { db in
            try EventSourceProvenanceRecord
                .where { $0.id.eq(openedEventID) }
                .fetchOne(db)
        }
        #expect(sourceProvenanceRecord?.workspace?.repository == sourceProvenance.reference)
        #expect(sourceProvenanceRecord?.ref == sourceProvenance.ref)

        let baselineStage = try baselineDatabase.read { db in
            try OME.Stage
                .where { $0.id.eq(stageID("meadow", eventID: "testival-source-testival-2026", organizerID: organizerID)) }
                .fetchOne(db)
        }
        #expect(baselineStage?.name == "Meadow")

        let prepared = try EventWorkspaceSummary.query(
            eventID: openedEventID,
            using: database,
            referenceDatabase: baselineDatabase
        )
        #expect(prepared.availability == .available)

        try await database.write { db in
            try OME.Stage
                .find(stageID("meadow", eventID: "testival-source-testival-2026", organizerID: organizerID))
                .update { $0.name = "Updated Meadow" }
                .execute(db)
        }

        let available = try await eventWorkspaceSummary(
            eventID: openedEventID,
            database: database,
            baselineDatabase: baselineDatabase
        )

        #expect(available.eventID == openedEventID)
        #expect(available.availability == .available)
        #expect(available.totalCount == 1)
        #expect(available.badgeCount == 1)
        let stageGroup = try #require(
            available.groups.first { $0.id == OME.Stage.tableName }
        )
        #expect(stageGroup.displayName == "Stage")
        #expect(stageGroup.added == 0)
        #expect(stageGroup.modified == 1)
        #expect(stageGroup.deleted == 0)
        let stageRecord = try #require(stageGroup.records.first)
        #expect(stageRecord.kind == .modified)
        #expect(stageRecord.recordDiff?.contains("Updated Meadow") == true)
        expectNoDifference(
            stageRecord.fieldChanges,
            [
                SourceFieldChange(
                    columnName: "name",
                    baselineValue: "Meadow".databaseValue,
                    workingValue: "Updated Meadow".databaseValue
                )
            ]
        )

        try await database.write { db in
            try OME.Contributor
                .find(contributorID("artist-one", eventID: "testival-source-testival-2026", organizerID: organizerID))
                .update { $0.name = "Updated Artist One" }
                .execute(db)
        }

        let withContributorChange = try await eventWorkspaceSummary(
            eventID: openedEventID,
            database: database,
            baselineDatabase: baselineDatabase
        )

        #expect(withContributorChange.eventID == openedEventID)
        #expect(withContributorChange.availability == .available)
        #expect(withContributorChange.totalCount == 2)
        #expect(withContributorChange.badgeCount == 2)
        let contributorGroup = try #require(
            withContributorChange.groups.first { $0.id == OME.Contributor.tableName }
        )
        #expect(contributorGroup.displayName == "Contributor")
        #expect(contributorGroup.added == 0)
        #expect(contributorGroup.modified == 1)
        #expect(contributorGroup.deleted == 0)
        let contributorRecord = try #require(contributorGroup.records.first)
        #expect(contributorRecord.kind == .modified)
        #expect(contributorRecord.recordDiff?.contains("Updated Artist One") == true)
        let contributorComparison = try #require(
            withContributorChange.recordComparisons[contributorRecord]?.as(OME.Contributor.self)
        )
        #expect(contributorComparison.left?.name == "Artist One")
        #expect(contributorComparison.right?.name == "Updated Artist One")
        expectNoDifference(
            contributorRecord.fieldChanges,
            [
                SourceFieldChange(
                    columnName: "name",
                    baselineValue: "Artist One".databaseValue,
                    workingValue: "Updated Artist One".databaseValue
                )
            ]
        )
    }

    @Test
    func sourceWorkspaceSummaryIncludesEveryEventChangeForItsOrganizer() async throws {
        let source = try makeSourceRepository()
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let sourceProvenance = tangledSourceProvenance("testival-source", ref: "main")
        let insertion = try OME.SourceDatabaseInsertion(
            .init(
                source: source,
                organizerID: organizerID,
                sourceProvenance: sourceProvenance
            )
        )
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let workingDatabasePath = directoryURL.appendingPathComponent("working.sqlite").path
        let baselineDatabasePath = directoryURL.appendingPathComponent("baseline.sqlite").path
        let baselineDatabase = try defaultBaselineDatabase(path: baselineDatabasePath)
        let database = try makeCoreDatabase(path: workingDatabasePath)

        try await insertion.migrateAndInsert(into: baselineDatabase.database)
        try await insertion.insert(into: database)
        try await database.write { db in
            try OME.Stage
                .find(stageID("meadow", eventID: "testival-source-testival-2026", organizerID: organizerID))
                .update { $0.name = "Updated Meadow" }
                .execute(db)
        }

        let summary = try await database.read { db in
            try SourceWorkspaceEditSummary.query(
                workspace: try #require(
                    EventSourceProvenanceRecord.find(
                        eventID(
                            "testival-source-testival-2026",
                            organizerID: organizerID
                        )
                    )
                    .fetchOne(db)?
                    .workspace
                ),
                in: db,
                referenceDatabase: baselineDatabase
            )
        }

        #expect(summary.availability == .available)
        #expect(summary.totalCount == 1)
        #expect(summary.badgeCount == 1)
        let stageGroup = try #require(
            summary.groups.first { $0.id == OME.Stage.tableName }
        )
        #expect(stageGroup.displayName == "Stage")
        #expect(stageGroup.added == 0)
        #expect(stageGroup.modified == 1)
        #expect(stageGroup.deleted == 0)
        let stageRecord = try #require(stageGroup.records.first)
        #expect(stageRecord.kind == .modified)
        #expect(stageRecord.recordDiff?.contains("Updated Meadow") == true)
        expectNoDifference(
            stageRecord.fieldChanges,
            [
                SourceFieldChange(
                    columnName: "name",
                    baselineValue: "Meadow".databaseValue,
                    workingValue: "Updated Meadow".databaseValue
                )
            ]
        )
    }

    @Test
    func sourceInsertionStoresSourceProvenanceSeparatelyFromEventIDOrigin() async throws {
        let source = try makeSourceRepository()
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let sourceProvenance = tangledSourceProvenance("testival-source", ref: "HEAD")
        let insertion = try OME.SourceDatabaseInsertion(
            .init(
                source: source,
                organizerID: organizerID,
                sourceProvenance: sourceProvenance
            )
        )
        let database = try makeCoreDatabase()
        let baselineDatabase = try defaultBaselineDatabase()
        defer { try? FileManager.default.removeItem(atPath: baselineDatabase.path) }

        try await insertion.migrateAndInsert(into: baselineDatabase.database)
        try await insertion.insert(into: database)

        let appProvenanceRow = try database.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                SELECT "sourceKind", "eventIDOrigin"
                FROM "eventSourceProvenances"
                LIMIT 1
                """
            )
            return try #require(row)
        }
        #expect(appProvenanceRow["sourceKind"] as String == "tangled")
        #expect(appProvenanceRow["eventIDOrigin"] as String == "inferred")

        let referenceProvenanceRow = try baselineDatabase.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                SELECT "sourceKind", "eventIDOrigin"
                FROM "eventSourceProvenances"
                LIMIT 1
                """
            )
            return try #require(row)
        }
        #expect(referenceProvenanceRow["sourceKind"] as String == "tangled")
        #expect(referenceProvenanceRow["eventIDOrigin"] as String == "inferred")
    }

    @Test
    func editSummariesUseDefaultDatabaseAndExplicitReference() async throws {
        let source = try makeSourceRepository()
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let openedEventID = eventID("testival-source-testival-2026", organizerID: organizerID)
        let sourceProvenance = tangledSourceProvenance("testival-source", ref: "main")
        let insertion = try OME.SourceDatabaseInsertion(
            .init(
                source: source,
                organizerID: organizerID,
                sourceProvenance: sourceProvenance
            )
        )
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let workingDatabasePath = directoryURL.appendingPathComponent("working.sqlite").path
        let baselineDatabasePath = directoryURL.appendingPathComponent("baseline.sqlite").path
        let baselineDatabase = try defaultBaselineDatabase(path: baselineDatabasePath)
        let database = try makeCoreDatabase(path: workingDatabasePath)

        try await insertion.migrateAndInsert(into: baselineDatabase.database)
        try await insertion.insert(into: database)
        try await database.write { db in
            try OME.Stage
                .find(stageID("meadow", eventID: "testival-source-testival-2026", organizerID: organizerID))
                .update { $0.name = "Updated Meadow" }
                .execute(db)
        }

        let summaries = try await database.read { db in
            (
                event: try EventWorkspaceSummary.query(
                    eventID: openedEventID,
                    in: db,
                    referenceDatabase: baselineDatabase
                ),
                source: try SourceWorkspaceEditSummary.query(
                    workspace: try #require(
                        EventSourceProvenanceRecord.find(openedEventID).fetchOne(db)?.workspace
                    ),
                    in: db,
                    referenceDatabase: baselineDatabase
                )
            )
        }

        #expect(summaries.event.availability == .available)
        #expect(summaries.event.totalCount == 1)
        #expect(summaries.source.availability == .available)
        #expect(summaries.source.totalCount == 1)
    }

    @Test
    func eventWorkspaceSummaryReportsWholeSourceTypedDiff() async throws {
        var source = try makeSourceRepository()
        source.events.append(
            try makeSourceRepository(
                eventDirectoryName: "afterparty-2026",
                eventName: "Afterparty 2026"
            )
            .events[0]
        )

        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let openedEventID = eventID("testival-source-testival-2026", organizerID: organizerID)
        let otherEventID = eventID("testival-source-afterparty-2026", organizerID: organizerID)
        let sourceProvenance = tangledSourceProvenance("testival-source", ref: "main")
        let insertion = try OME.SourceDatabaseInsertion(
            .init(
                source: source,
                organizerID: organizerID,
                sourceProvenance: sourceProvenance
            )
        )
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let workingDatabasePath = directoryURL.appendingPathComponent("working.sqlite").path
        let baselineDatabase = try defaultBaselineDatabase(
            path: directoryURL.appendingPathComponent("baseline.sqlite").path
        )
        let database = try makeCoreDatabase(path: workingDatabasePath)

        try await insert(
            insertion,
            into: database,
            and: baselineDatabase
        )
        // The user is viewing one event, but the source diff is the whole source database.
        try await database.write { db in
            try OME.Stage
                .find(stageID("meadow", eventID: "testival-source-testival-2026", organizerID: organizerID))
                .update { $0.name = "Updated Meadow" }
                .execute(db)
            try OME.Stage
                .find(stageID("meadow", eventID: "testival-source-afterparty-2026", organizerID: organizerID))
                .update { $0.name = "Updated Afterparty Meadow" }
                .execute(db)
        }

        let summary = try await database.read { db in
            try SourceWorkspaceEditSummary.query(
                workspace: try #require(
                    EventSourceProvenanceRecord.find(openedEventID).fetchOne(db)?.workspace
                ),
                in: db,
                referenceDatabase: baselineDatabase
            )
        }

        #expect(summary.availability == .available)
        #expect(summary.totalCount == 2)
        #expect(summary.badgeCount == 2)
        let stageGroup = try #require(
            summary.groups.first { $0.id == OME.Stage.tableName }
        )
        #expect(stageGroup.modified == 2)
        let focusedStageRecord = try #require(
            stageGroup.records.first { $0.hasEventID(openedEventID) }
        )
        let otherStageRecord = try #require(
            stageGroup.records.first { $0.hasEventID(otherEventID) }
        )

        let focusedStageComparison = try #require(
            summary.recordComparisons[focusedStageRecord]?.as(OME.Stage.self)
        )
        #expect(focusedStageComparison.change.tableID == OME.Stage.tableName)
        #expect(focusedStageComparison.left?.name == "Meadow")
        #expect(focusedStageComparison.right?.name == "Updated Meadow")

        let otherStageComparison = try #require(
            summary.recordComparisons[otherStageRecord]?.as(OME.Stage.self)
        )
        #expect(otherStageComparison.change.tableID == OME.Stage.tableName)
        #expect(otherStageComparison.left?.name == "Meadow")
        #expect(otherStageComparison.right?.name == "Updated Afterparty Meadow")
    }

    @Test
    func workspaceSummarySuppliesTypedContributorAndDetailedStageComparisons() async throws {
        let stageHeroURL = try #require(URL(string: "https://example.com/meadow-hero.jpg"))
        let source = try makeSourceRepository(
            stageImages: [
                SourceImageAsset(
                    source: .url(stageHeroURL),
                    role: .hero,
                    renderKind: .fullImage,
                    materializationPolicy: .lazy
                )
            ],
            contributorName: "Abstrakt Sonance"
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let workspace = SourceWorkspace(
            organizerID: organizerID,
            repository: "tangled.org/woody.fm/testival-source",
            branch: "main"
        )
        let insertion = try OME.SourceDatabaseInsertion(
            .init(
                source: source,
                organizerID: organizerID
            )
        )
        let insertedContributorID = try #require(insertion.contributors.first?.id)
        let insertedStageID = try #require(insertion.stages.first?.id)
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let database = try makeCoreDatabase(
            path: directoryURL.appendingPathComponent("working.sqlite").path
        )
        let baselineDatabase = try defaultBaselineDatabase(
            path: directoryURL.appendingPathComponent("baseline.sqlite").path
        )

        try await insertion.migrateAndInsert(into: database)
        try await insertion.migrateAndInsert(into: baselineDatabase.database)

        let changedFocalPoint = OME.ImageAsset.FocalPoint(x: 0.25, y: 0.75)
        try await database.write { db in
            var contributor = try #require(
                try OME.Contributor
                    .find(insertedContributorID)
                    .fetchOne(db)
            )
            contributor.name = "Abstrakt Sona"
            try OME.Contributor.update(contributor).execute(db)

            var stage = try #require(
                try OME.Stage
                    .find(insertedStageID)
                    .fetchOne(db)
            )
            var images = try #require(stage.images)
            images[0].focalPoint = changedFocalPoint
            stage.images = images
            try OME.Stage.update(stage).execute(db)
        }

        let summary = try await database.read { db in
            try SourceWorkspaceEditSummary.query(
                workspace: workspace,
                in: db,
                referenceDatabase: baselineDatabase
            )
        }

        let contributorGroup = try #require(
            summary.groups.first { $0.id == OME.Contributor.tableName }
        )
        let contributorRecord = try #require(contributorGroup.records.first)
        let contributorComparison = try #require(
            summary.recordComparisons[contributorRecord]?.as(OME.Contributor.self)
        )
        expectNoDifference(contributorComparison.left?.name, "Abstrakt Sonance")
        expectNoDifference(contributorComparison.right?.name, "Abstrakt Sona")

        let stageGroup = try #require(
            summary.groups.first { $0.id == OME.Stage.tableName }
        )
        let stageRecord = try #require(stageGroup.records.first)
        let stageComparison = try #require(
            summary.recordComparisons[stageRecord]?.as(OME.Stage.self)
        )
        expectNoDifference(stageComparison.left?.images?.first?.focalPoint, nil)
        expectNoDifference(stageComparison.right?.images?.first?.focalPoint, changedFocalPoint)

        let imageChange = try #require(
            stageRecord.fieldChanges.first { $0.columnName == "images" }
        )
        let imageComparison = try #require(
            summary.fieldComparisons[stageRecord, imageChange]
        )
        let imageDifference = try #require(imageComparison.difference)
        #expect(imageDifference.contains("focalPoint"))
        #expect(imageDifference.contains("0.25"))
        #expect(imageDifference.contains("0.75"))
    }

    @Test
    func eventWorkspaceSummaryUsesDefaultDatabaseAgainstSourceReference() async throws {
        let source = try makeSourceRepository()
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let openedEventID = eventID("testival-source-testival-2026", organizerID: organizerID)
        let sourceProvenance = tangledSourceProvenance("testival-source", ref: "main")
        let insertion = try OME.SourceDatabaseInsertion(
            .init(
                source: source,
                organizerID: organizerID,
                sourceProvenance: sourceProvenance
            )
        )
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let workingDatabasePath = directoryURL.appendingPathComponent("working.sqlite").path
        let baselineDatabase = try defaultBaselineDatabase(
            path: directoryURL.appendingPathComponent("baseline.sqlite").path
        )
        let database = try makeCoreDatabase(path: workingDatabasePath)

        try await insert(
            insertion,
            into: database,
            and: baselineDatabase
        )
        try await database.write { db in
            try OME.Stage
                .find(stageID("meadow", eventID: "testival-source-testival-2026", organizerID: organizerID))
                .update { $0.name = "Changed through default database" }
                .execute(db)
        }

        let summary = try EventWorkspaceSummary.query(
            eventID: openedEventID,
            using: database,
            referenceDatabase: baselineDatabase
        )

        #expect(summary.availability == .available)
        #expect(summary.totalCount == 1)
        #expect(summary.badgeCount == 1)
        let stageGroup = try #require(
            summary.groups.first { $0.id == OME.Stage.tableName }
        )
        #expect(stageGroup.displayName == "Stage")
        #expect(stageGroup.added == 0)
        #expect(stageGroup.modified == 1)
        #expect(stageGroup.deleted == 0)
        let stageRecord = try #require(stageGroup.records.first)
        #expect(stageRecord.kind == .modified)
        #expect(stageRecord.recordDiff?.contains("Changed through default database") == true)
        expectNoDifference(
            stageRecord.fieldChanges,
            [
                SourceFieldChange(
                    columnName: "name",
                    baselineValue: "Meadow".databaseValue,
                    workingValue: "Changed through default database".databaseValue
                )
            ]
        )
    }

    @Test
    func eventWorkspaceSummaryCountsAddedCanonicalPerformanceRows() async throws {
        let source = try makeSourceRepository()
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let openedEventID = eventID("testival-source-testival-2026", organizerID: organizerID)
        let sourceProvenance = tangledSourceProvenance("testival-source", ref: "main")
        let insertion = try OME.SourceDatabaseInsertion(
            .init(
                source: source,
                organizerID: organizerID,
                sourceProvenance: sourceProvenance
            )
        )
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let workingDatabasePath = directoryURL.appendingPathComponent("working.sqlite").path
        let baselineDatabase = try defaultBaselineDatabase(
            path: directoryURL.appendingPathComponent("baseline.sqlite").path
        )
        let database = try makeCoreDatabase(path: workingDatabasePath)
        let scheduleDate = try #require(LocalDate("2026-08-01"))
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))

        try await insert(
            insertion,
            into: database,
            and: baselineDatabase
        )

        let startTime = try localDate(scheduleDate, atHour: 21, in: timeZone)
        let endTime = try localDate(scheduleDate, atHour: 22, in: timeZone)
        try await database.write { db in
            try OME.Performance.insert {
                OME.Performance.Draft(
                    id: performanceID(
                        "late-addition",
                        eventID: "testival-source-testival-2026",
                        organizerID: organizerID
                    ),
                    stageID: id("meadow"),
                    scheduleID: id("saturday"),
                    startTime: startTime,
                    endTime: endTime,
                    title: "Late Addition",
                    description: "Added from the schedule editor.",
                    recordings: []
                )
            }
            .execute(db)
        }

        let summary = try await eventWorkspaceSummary(
            eventID: openedEventID,
            database: database,
            baselineDatabase: baselineDatabase
        )

        #expect(summary.availability == .available)
        #expect(summary.totalCount == 2)
        #expect(summary.badgeCount == 2)
        let scheduleItemGroup = try #require(
            summary.groups.first { $0.id == OME.ScheduleItem.tableName }
        )
        #expect(scheduleItemGroup.displayName == "ScheduleItem")
        #expect(scheduleItemGroup.added == 1)
        #expect(scheduleItemGroup.modified == 0)
        #expect(scheduleItemGroup.deleted == 0)
        let scheduleItemRecord = try #require(scheduleItemGroup.records.first)
        #expect(scheduleItemRecord.kind == .added)
        #expect(scheduleItemRecord.recordDiff?.contains("Late Addition") == true)
        let scheduleItemComparison = try #require(
            summary.recordComparisons[scheduleItemRecord]?.as(OME.ScheduleItem.self)
        )
        #expect(scheduleItemComparison.left == nil)
        #expect(scheduleItemComparison.right?.title == "Late Addition")
        let performanceDetailsGroup = try #require(
            summary.groups.first { $0.id == OME.ScheduleItem.PerformanceDetails.tableName }
        )
        #expect(performanceDetailsGroup.added == 1)
        let titleChange = try #require(
            scheduleItemRecord.fieldChanges.first { $0.columnName == "title" }
        )
        expectNoDifference(
            titleChange,
            SourceFieldChange(
                columnName: "title",
                baselineValue: nil,
                workingValue: "Late Addition".databaseValue
            )
        )
    }

    @Test
    func eventWorkspaceResetterRestoresRealSchemaRows() async throws {
        let source = try makeSourceRepository()
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let calendarID = calendarID(organizerID: organizerID)
        let openedEventID = eventID("testival-source-testival-2026", organizerID: organizerID)
        let sourceProvenance = tangledSourceProvenance("testival-source", ref: "main")
        let insertion = try OME.SourceDatabaseInsertion(
            .init(
                source: source,
                organizerID: organizerID,
                sourceProvenance: sourceProvenance
            )
        )
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let workingDatabasePath = directoryURL.appendingPathComponent("working.sqlite").path
        let baselineDatabase = try defaultBaselineDatabase(
            path: directoryURL.appendingPathComponent("baseline.sqlite").path
        )
        let database = try makeCoreDatabase(path: workingDatabasePath)

        try await insert(
            insertion,
            into: database,
            and: baselineDatabase
        )
        let workspace = try await database.read { db in
            try #require(
                EventSourceProvenanceRecord.find(openedEventID).fetchOne(db)?.workspace
            )
        }

        try await database.write { db in
            try OME.Calendar
                .find(calendarID)
                .update { $0.name = "Changed Calendar" }
                .execute(db)
            try OME.Event
                .find(openedEventID)
                .update { $0.name = "Changed Event" }
                .execute(db)
            try OME.Stage
                .find(stageID("meadow", eventID: "testival-source-testival-2026", organizerID: organizerID))
                .update { $0.name = "Changed Stage" }
                .execute(db)
        }

        let changedSummary = try await database.read { db in
            try SourceWorkspaceEditSummary.query(
                workspace: workspace,
                in: db,
                referenceDatabase: baselineDatabase
            )
        }
        #expect(changedSummary.availability == .available)
        #expect(changedSummary.totalCount == 3)

        try withDependencies {
            $0.defaultDatabase = database
            $0.eventWorkspaceResetter = .openMusicEvent
        } operation: {
            @Dependency(\.eventWorkspaceResetter) var resetter
            try resetter.resetWorkspace(workspace, baselineDatabase)
        }

        let resetSummary = try await database.read { db in
            try SourceWorkspaceEditSummary.query(
                workspace: workspace,
                in: db,
                referenceDatabase: baselineDatabase
            )
        }
        #expect(resetSummary.availability == .available)
        #expect(resetSummary.totalCount == 0)

        let restoredRows = try await database.read { db in
            let calendar = try #require(try OME.Calendar.find(calendarID).fetchOne(db))
            let event = try #require(try OME.Event.find(openedEventID).fetchOne(db))
            let stage = try #require(
                try OME.Stage
                    .find(stageID("meadow", eventID: "testival-source-testival-2026", organizerID: organizerID))
                    .fetchOne(db)
            )
            return (calendar, event, stage)
        }
        #expect(restoredRows.0.name == "Events")
        #expect(restoredRows.1.name == "Testival 2026")
        #expect(restoredRows.2.name == "Meadow")
    }

    @Test
    func eventWorkspaceSummaryUsesWorkspaceOwnedReferenceDatabase() async throws {
        let source = try makeSourceRepository()
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let openedEventID = eventID(
            "testival-source-testival-2026",
            organizerID: organizerID
        )
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let sourceProvenance = tangledSourceProvenance("testival-source", ref: "main")
        let workspace = SourceWorkspace(
            organizerID: organizerID,
            repository: sourceProvenance.reference,
            branch: try #require(sourceProvenance.ref)
        )
        let insertion = try OME.SourceDatabaseInsertion(
            .init(
                source: source,
                organizerID: organizerID,
                sourceProvenance: sourceProvenance
            )
        )
        let database = try makeCoreDatabase(
            path: directoryURL.appendingPathComponent("working.sqlite").path
        )
        let storage = SourceWorkspaceStorage.fileBacked(
            rootURL: directoryURL.appending(path: "workspaces")
        )
        let location = try storage.location(workspace.id)
        try FileManager.default.createDirectory(
            at: location.directoryURL,
            withIntermediateDirectories: true
        )
        let referenceDatabase = try defaultBaselineDatabase(
            path: location.referenceDatabaseURL.path
        )
        try await insert(insertion, into: database, and: referenceDatabase)

        #expect(FileManager.default.fileExists(atPath: location.referenceDatabaseURL.path))
        #expect(!location.referenceDatabaseURL.path.hasPrefix(location.repositoryURL.path + "/"))

        try await database.write { db in
            try OME.Stage
                .find(
                    stageID(
                        "meadow",
                        eventID: "testival-source-testival-2026",
                        organizerID: organizerID
                    )
                )
                .update { $0.name = "Changed through default database" }
                .execute(db)
        }

        let summary = try EventWorkspaceSummary.query(
            eventID: openedEventID,
            using: database,
            referenceDatabase: referenceDatabase
        )

        #expect(summary.availability == .available)
        #expect(summary.totalCount == 1)
        let stageGroup = try #require(
            summary.groups.first { $0.id == OME.Stage.tableName }
        )
        let stageRecord = try #require(stageGroup.records.first)
        #expect(stageRecord.recordDiff?.contains("Changed through default database") == true)
    }

    @Test
    func eventWorkspaceSummaryComparesJSONObjectKeyOrderSemantically() async throws {
        let source = try makeSourceRepository(
            eventLocations: [
                OME.Event.Location(
                    address: "Meadow",
                    coordinates: .init(latitude: 50, longitude: -115)
                )
            ],
            eventContactNumbers: [
                OME.Event.ContactNumber(
                    phoneNumber: "555-0100",
                    title: "Info",
                    description: "Help"
                )
            ],
            contributorLinks: [
                ExternalPlatform.Link(
                    url: try #require(URL(string: "https://instagram.com/artist-one")),
                    platform: .instagram
                )
            ]
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let openedEventID = eventID("testival-source-testival-2026", organizerID: organizerID)
        let insertion = try OME.SourceDatabaseInsertion(
            .init(
                source: source,
                organizerID: organizerID,
                sourceProvenance: tangledSourceProvenance("testival-source", ref: "main")
            )
        )
        let database = try makeCoreDatabase()
        let baselineDatabase = try defaultBaselineDatabase()
        defer { try? FileManager.default.removeItem(atPath: baselineDatabase.path) }

        try await insert(
            insertion,
            into: database,
            and: baselineDatabase
        )

        // These pairs decode to identical values, but their JSON object keys are ordered differently.
        try baselineDatabase.write { db in
            try db.execute(
                sql: #"UPDATE "app.openmusicevent.event" SET locations = '[{"address":"Meadow","coordinates":{"latitude":50,"longitude":-115}}]', contactNumbers = '[{"phoneNumber":"555-0100","title":"Info","description":"Help"}]'"#
            )
            try db.execute(
                sql: #"UPDATE "app.openmusicevent.contributor" SET links = '[{"url":"https://instagram.com/artist-one","platform":"instagram"}]'"#
            )
        }
        try await database.write { db in
            try db.execute(
                sql: #"UPDATE "app.openmusicevent.event" SET locations = '[{"coordinates":{"longitude":-115,"latitude":50},"address":"Meadow"}]', contactNumbers = '[{"description":"Help","title":"Info","phoneNumber":"555-0100"}]'"#
            )
            try db.execute(
                sql: #"UPDATE "app.openmusicevent.contributor" SET links = '[{"platform":"instagram","url":"https://instagram.com/artist-one"}]'"#
            )
        }

        let unchangedSummary = try await eventWorkspaceSummary(
            eventID: openedEventID,
            database: database,
            baselineDatabase: baselineDatabase
        )

        expectNoDifference(unchangedSummary.totalCount, 0)
        #expect(unchangedSummary.badgeCount == nil)

        try await database.write { db in
            try OME.Event
                .find(openedEventID)
                .update { $0.name = "A real edit." }
                .execute(db)
        }
        let changedSummary = try await eventWorkspaceSummary(
            eventID: openedEventID,
            database: database,
            baselineDatabase: baselineDatabase
        )

        expectNoDifference(changedSummary.totalCount, 1)
        let eventGroup = try #require(
            changedSummary.groups.first { $0.id == OME.Event.tableName }
        )
        let eventRecord = try #require(eventGroup.records.first)
        #expect(eventRecord.fieldChanges.contains { $0.columnName == "name" })
    }

    @Test
    func eventWorkspaceSummaryIgnoresImageFileURLBaseChangesWhenAssetKeyMatches() async throws {
        let repositoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        let eventDirectoryURL = repositoryURL
            .appending(path: "events", directoryHint: .isDirectory)
            .appending(path: "testival-2026", directoryHint: .isDirectory)
        let imagesDirectoryURL = eventDirectoryURL.appending(path: "images", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: imagesDirectoryURL, withIntermediateDirectories: true)
        try Data("stage-logo".utf8).write(to: imagesDirectoryURL.appending(path: "meadow-logo.png"))
        try Data("artist-photo".utf8).write(to: imagesDirectoryURL.appending(path: "artist-one.png"))

        let source = try makeSourceRepository(
            stageImages: [
                SourceImageAsset(
                    source: .file("images/meadow-logo.png"),
                    role: .logo,
                    renderKind: .transparent,
                    materializationPolicy: .prefetchOnOpen
                )
            ],
            contributorImages: [
                SourceImageAsset(
                    source: .file("images/artist-one.png"),
                    role: .photo,
                    renderKind: .fullImage,
                    materializationPolicy: .lazy
                )
            ]
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let openedEventID = eventID("testival-source-testival-2026", organizerID: organizerID)
        let insertion = try OME.SourceDatabaseInsertion(
            .init(
                source: source,
                organizerID: organizerID,
                sourceProvenance: tangledSourceProvenance("testival-source", ref: "main"),
                sourceRootURL: repositoryURL
            )
        )
        let database = try makeCoreDatabase()
        let baselineDatabase = try defaultBaselineDatabase()
        defer { try? FileManager.default.removeItem(atPath: baselineDatabase.path) }
        let cacheDirectoryURL = try temporaryDirectoryURL()
        let movedCacheDirectoryURL = try temporaryDirectoryURL()

        try await withDependencies {
            $0.localImageFileStore = testLocalImageFileStore(directory: cacheDirectoryURL)
        } operation: {
            try await insert(
                insertion,
                into: database,
                and: baselineDatabase
            )
        }

        try await database.write { db in
            var stage = try #require(
                try OME.Stage
                    .find(stageID("meadow", eventID: "testival-source-testival-2026", organizerID: organizerID))
                    .fetchOne(db)
            )
            var stageImages = try #require(stage.images)
            var stageImage = try #require(stageImages.first)
            let stageURL = try #require(stageImage.url)
            stageImage.source = .url(movedCacheDirectoryURL.appending(path: stageURL.lastPathComponent))
            stageImages[0] = stageImage
            stage.images = stageImages
            try OME.Stage.update(stage).execute(db)

            var contributor = try #require(
                try OME.Contributor
                    .find(contributorID("artist-one", eventID: "testival-source-testival-2026", organizerID: organizerID))
                    .fetchOne(db)
            )
            var contributorImages = try #require(contributor.images)
            var contributorImage = try #require(contributorImages.first)
            let contributorURL = try #require(contributorImage.url)
            contributorImage.source = .url(movedCacheDirectoryURL.appending(path: contributorURL.lastPathComponent))
            contributorImages[0] = contributorImage
            contributor.images = contributorImages
            try OME.Contributor.update(contributor).execute(db)
        }

        let summary = try await eventWorkspaceSummary(
            eventID: openedEventID,
            database: database,
            baselineDatabase: baselineDatabase
        )

        #expect(summary.availability == .available)
        #expect(summary.totalCount == 0)
        #expect(summary.badgeCount == nil)
    }

    @Test
    func eventWorkspaceSummaryIgnoresMaterializedRemoteImageWhenAssetKeyMatches() async throws {
        let remoteLogoURL = try #require(URL(string: "https://example.com/meadow-logo.png"))
        let source = try makeSourceRepository(
            stageImages: [
                SourceImageAsset(
                    source: .url(remoteLogoURL),
                    role: .logo,
                    renderKind: .transparent,
                    materializationPolicy: .prefetchOnOpen
                )
            ]
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let openedEventID = eventID("testival-source-testival-2026", organizerID: organizerID)
        let insertion = try OME.SourceDatabaseInsertion(
            .init(
                source: source,
                organizerID: organizerID,
                sourceProvenance: tangledSourceProvenance("testival-source", ref: "main")
            )
        )
        let database = try makeCoreDatabase()
        let baselineDatabase = try defaultBaselineDatabase()
        defer { try? FileManager.default.removeItem(atPath: baselineDatabase.path) }

        try await insert(
            insertion,
            into: database,
            and: baselineDatabase
        )

        try await database.write { db in
            var stage = try #require(
                try OME.Stage
                    .find(stageID("meadow", eventID: "testival-source-testival-2026", organizerID: organizerID))
                    .fetchOne(db)
            )
            var images = try #require(stage.images)
            var image = try #require(images.first)
            image.source = .url(
                URL(filePath: "/tmp/materialized-\(try #require(image.assetKey)).png")
            )
            images[0] = image
            stage.images = images
            try OME.Stage.update(stage).execute(db)
        }

        let summary = try await eventWorkspaceSummary(
            eventID: openedEventID,
            database: database,
            baselineDatabase: baselineDatabase
        )

        #expect(summary.availability == .available)
        #expect(summary.totalCount == 0)
        #expect(summary.badgeCount == nil)
    }

    @Test
    func eventWorkspaceSummaryIgnoresRemoteImagePrefetchCache() async throws {
        let remoteLogoURL = try #require(URL(string: "https://example.com/meadow-logo.png"))
        let source = try makeSourceRepository(
            stageImages: [
                SourceImageAsset(
                    source: .url(remoteLogoURL),
                    role: .logo,
                    renderKind: .transparent,
                    materializationPolicy: .prefetchOnOpen
                )
            ]
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let openedEventID = eventID("testival-source-testival-2026", organizerID: organizerID)
        let insertion = try OME.SourceDatabaseInsertion(
            .init(
                source: source,
                organizerID: organizerID,
                sourceProvenance: tangledSourceProvenance("testival-source", ref: "main")
            )
        )
        let database = try makeCoreDatabase()
        let baselineDatabase = try defaultBaselineDatabase()
        defer { try? FileManager.default.removeItem(atPath: baselineDatabase.path) }

        try await insert(
            insertion,
            into: database,
            and: baselineDatabase
        )

        let cacheDirectoryURL = try temporaryDirectoryURL()
        try await withDependencies {
            $0.defaultDatabase = database
            $0.eventImagePrefetch = .live
            $0.localImageFileStore = testLocalImageFileStore(directory: cacheDirectoryURL)
            $0.httpClient = .testClient { _, _, _ in Data("remote-stage-logo".utf8) }
        } operation: {
            @Dependency(\.eventImagePrefetch) var eventImagePrefetch
            try await eventImagePrefetch.prefetchAssetsOnOpen(openedEventID)
        }

        let summary = try await eventWorkspaceSummary(
            eventID: openedEventID,
            database: database,
            baselineDatabase: baselineDatabase
        )

        #expect(summary.availability == .available)
        #expect(summary.totalCount == 0)
        #expect(summary.badgeCount == nil)
    }

    @Test
    func eventWorkspaceSummaryCountsRemoteImageURLChanges() async throws {
        let baselinePhotoURL = try #require(URL(string: "https://example.com/artist-one.jpg"))
        let workingPhotoURL = try #require(URL(string: "https://example.com/artist-two.jpg"))
        let source = try makeSourceRepository(
            contributorImages: [
                SourceImageAsset(
                    source: .url(baselinePhotoURL),
                    role: .photo,
                    renderKind: .fullImage,
                    materializationPolicy: .lazy
                )
            ]
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let openedEventID = eventID("testival-source-testival-2026", organizerID: organizerID)
        let insertion = try OME.SourceDatabaseInsertion(
            .init(
                source: source,
                organizerID: organizerID,
                sourceProvenance: tangledSourceProvenance("testival-source", ref: "main")
            )
        )
        let database = try makeCoreDatabase()
        let baselineDatabase = try defaultBaselineDatabase()
        defer { try? FileManager.default.removeItem(atPath: baselineDatabase.path) }

        try await insert(
            insertion,
            into: database,
            and: baselineDatabase
        )

        try await database.write { db in
            var contributor = try #require(
                try OME.Contributor
                    .find(contributorID("artist-one", eventID: "testival-source-testival-2026", organizerID: organizerID))
                    .fetchOne(db)
            )
            var images = try #require(contributor.images)
            var image = try #require(images.first)
            image.source = .url(workingPhotoURL)
            images[0] = image
            contributor.images = images
            try OME.Contributor.update(contributor).execute(db)
        }

        let summary = try await eventWorkspaceSummary(
            eventID: openedEventID,
            database: database,
            baselineDatabase: baselineDatabase
        )

        #expect(summary.availability == .available)
        #expect(summary.totalCount == 1)
        #expect(summary.badgeCount == 1)
        let contributorGroup = try #require(
            summary.groups.first { $0.id == OME.Contributor.tableName }
        )
        #expect(contributorGroup.modified == 1)
        let record = try #require(contributorGroup.records.first)
        #expect(record.fieldChanges.map(\.columnName) == ["images"])
        #expect(record.recordDiff?.contains(workingPhotoURL.absoluteString) == true)
    }

    @Test
    func eventWorkspaceSummaryCountsImageFocusChanges() async throws {
        let photoURL = try #require(URL(string: "https://example.com/artist-one.jpg"))
        let source = try makeSourceRepository(
            contributorImages: [
                SourceImageAsset(
                    source: .url(photoURL),
                    role: .photo,
                    renderKind: .fullImage,
                    materializationPolicy: .lazy
                )
            ]
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let openedEventID = eventID("testival-source-testival-2026", organizerID: organizerID)
        let insertion = try OME.SourceDatabaseInsertion(
            .init(
                source: source,
                organizerID: organizerID,
                sourceProvenance: tangledSourceProvenance("testival-source", ref: "main")
            )
        )
        let database = try makeCoreDatabase()
        let baselineDatabase = try defaultBaselineDatabase()
        defer { try? FileManager.default.removeItem(atPath: baselineDatabase.path) }

        try await insert(
            insertion,
            into: database,
            and: baselineDatabase
        )

        try await database.write { db in
            var contributor = try #require(
                try OME.Contributor
                    .find(contributorID("artist-one", eventID: "testival-source-testival-2026", organizerID: organizerID))
                    .fetchOne(db)
            )
            var images = try #require(contributor.images)
            var image = try #require(images.first)
            image.focalPoint = OME.ImageAsset.FocalPoint(x: 0.25, y: 0.75)
            images[0] = image
            contributor.images = images
            try OME.Contributor.update(contributor).execute(db)
        }

        let summary = try await eventWorkspaceSummary(
            eventID: openedEventID,
            database: database,
            baselineDatabase: baselineDatabase
        )

        #expect(summary.availability == .available)
        #expect(summary.totalCount == 1)
        let contributorGroup = try #require(
            summary.groups.first { $0.id == OME.Contributor.tableName }
        )
        #expect(contributorGroup.modified == 1)
        let record = try #require(contributorGroup.records.first)
        #expect(record.fieldChanges.map(\.columnName) == ["images"])
        let fieldChange = try #require(record.fieldChanges.first)
        let fieldComparison = try #require(
            summary.fieldComparisons[record, fieldChange]
        )
        let fieldDifference = try #require(fieldComparison.difference)
        #expect(record.recordDiff?.contains("dimensions") == false)
        #expect(record.recordDiff?.contains("focalPoint") == true)
        #expect(fieldDifference.contains("focalPoint"))
        #expect(fieldDifference.contains("0.25"))
        #expect(fieldDifference.contains("0.75"))
    }

    @Test
    func importsSameLocalEventIDForDifferentOrganizers() async throws {
        let source = try makeSourceRepository(eventDirectoryName: "2025")
        let firstOrganizerID = try #require(OME.Organizer.ID("did:plc:firstorg"))
        let secondOrganizerID = try #require(OME.Organizer.ID("did:plc:secondorg"))
        let firstInsertion = try OME.SourceDatabaseInsertion(
            .init(source: source, organizerID: firstOrganizerID)
        )
        let secondInsertion = try OME.SourceDatabaseInsertion(
            .init(source: source, organizerID: secondOrganizerID)
        )
        let database = try makeCoreDatabase()

        try await firstInsertion.insert(into: database)
        try await secondInsertion.insert(into: database)

        let events = try await database.read { db in
            try OME.Event.fetchAll(db)
        }
        let stages = try await database.read { db in
            try OME.Stage.fetchAll(db)
        }

        expectNoDifference(
            Set(events.map(\.id)),
            Set([
                eventID("2025", organizerID: firstOrganizerID),
                eventID("2025", organizerID: secondOrganizerID),
            ])
        )
        expectNoDifference(
            Set(stages.map(\.id)),
            Set([
                stageID("meadow", eventID: "2025", organizerID: firstOrganizerID),
                stageID("meadow", eventID: "2025", organizerID: secondOrganizerID),
            ])
        )
    }

    @Test
    func importsMultipleSourcesForSameOrganizer() async throws {
        let firstSource = try makeSourceRepository(eventDirectoryName: "2025")
        let secondSource = try makeSourceRepository(eventDirectoryName: "2026")
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let firstInsertion = try OME.SourceDatabaseInsertion(
            .init(
                source: firstSource,
                organizerID: organizerID,
                sourceProvenance: tangledSourceProvenance("first-source")
            )
        )
        let secondInsertion = try OME.SourceDatabaseInsertion(
            .init(
                source: secondSource,
                organizerID: organizerID,
                sourceProvenance: tangledSourceProvenance("second-source")
            )
        )
        let database = try makeCoreDatabase()

        try await firstInsertion.insert(into: database)
        try await secondInsertion.insert(into: database)

        let organizers = try await database.read { db in
            try OME.Organizer.fetchAll(db)
        }
        let events = try await database.read { db in
            try OME.Event.fetchAll(db)
        }
        let eventOrganizers = try await database.read { db in
            try OME.EventOrganizer.fetchAll(db)
        }
        let sourceProvenances = try await database.read { db in
            try EventSourceProvenanceRecord.fetchAll(db)
        }

        expectNoDifference(organizers.map(\.id), [organizerID])
        expectNoDifference(
            Set(events.map(\.id)),
            Set([
                eventID("first-source-2025", organizerID: organizerID),
                eventID("second-source-2026", organizerID: organizerID),
            ])
        )
        expectNoDifference(
            Set(eventOrganizers.map(\.id.eventID)),
            Set([
                id("first-source-2025"),
                id("second-source-2026"),
            ])
        )
        expectNoDifference(
            Set(sourceProvenances.map(\.sourceReference)),
            Set([
                "tangled.org/woody.fm/first-source",
                "tangled.org/woody.fm/second-source",
            ])
        )
    }

    @Test
    func infersBareEventIDWithoutSourceProvenance() throws {
        let source = try makeSourceRepository(eventDirectoryName: "2026")
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let insertion = try OME.SourceDatabaseInsertion(
            .init(source: source, organizerID: organizerID)
        )

        expectNoDifference(
            insertion.events.map(\.id),
            [
                eventID("2026", organizerID: organizerID)
            ]
        )
    }

    @Test
    func importsMatchingInferredEventDirectoriesFromDifferentSources() async throws {
        let firstSource = try makeSourceRepository(eventDirectoryName: "2026")
        let secondSource = try makeSourceRepository(eventDirectoryName: "2026")
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let firstInsertion = try OME.SourceDatabaseInsertion(
            .init(
                source: firstSource,
                organizerID: organizerID,
                sourceProvenance: tangledSourceProvenance("first-source")
            )
        )
        let secondInsertion = try OME.SourceDatabaseInsertion(
            .init(
                source: secondSource,
                organizerID: organizerID,
                sourceProvenance: tangledSourceProvenance("second-source")
            )
        )
        let database = try makeCoreDatabase()

        try await firstInsertion.insert(into: database)
        try await secondInsertion.insert(into: database)

        let events = try await database.read { db in
            try OME.Event.fetchAll(db)
        }
        let sourceProvenances = try await database.read { db in
            try EventSourceProvenanceRecord.fetchAll(db)
        }

        expectNoDifference(
            Set(events.map(\.id)),
            Set([
                eventID("first-source-2026", organizerID: organizerID),
                eventID("second-source-2026", organizerID: organizerID),
            ])
        )
        expectNoDifference(
            Set(sourceProvenances.map(\.id)),
            Set([
                eventID("first-source-2026", organizerID: organizerID),
                eventID("second-source-2026", organizerID: organizerID),
            ])
        )
        expectNoDifference(
            Set(sourceProvenances.map(\.sourceEventDirectory)),
            Set(["2026"])
        )
    }

    @Test
    func reimportsInferredEventIDFromSameSource() async throws {
        let firstSource = try makeSourceRepository(
            eventDirectoryName: "2026",
            eventName: "Wicked Woods"
        )
        let secondSource = try makeSourceRepository(
            eventDirectoryName: "2026",
            eventName: "Wicked Woods Updated"
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let firstInsertion = try OME.SourceDatabaseInsertion(
            .init(
                source: firstSource,
                organizerID: organizerID,
                sourceProvenance: tangledSourceProvenance("wicked-woods", ref: "main")
            )
        )
        let secondInsertion = try OME.SourceDatabaseInsertion(
            .init(
                source: secondSource,
                organizerID: organizerID,
                sourceProvenance: tangledSourceProvenance("wicked-woods", ref: "release")
            )
        )
        let database = try makeCoreDatabase()

        try await firstInsertion.insert(into: database)
        try await secondInsertion.insert(into: database)

        let event = try await database.read { db in
            try OME.Event.where { $0.id.eq(eventID("wicked-woods-2026", organizerID: organizerID)) }
                .fetchOne(db)
        }
        let sourceProvenance = try await database.read { db in
            try EventSourceProvenanceRecord
                .where { $0.id.eq(eventID("wicked-woods-2026", organizerID: organizerID)) }
                .fetchOne(db)
        }

        #expect(event?.name == "Wicked Woods Updated")
        #expect(sourceProvenance?.sourceReference == "tangled.org/woody.fm/wicked-woods")
        #expect(sourceProvenance?.ref == "release")
        #expect(sourceProvenance?.eventIDOrigin == .inferred)
    }

    @Test
    func explicitEventIDUpdatesAcrossSources() async throws {
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let firstSource = try makeSourceRepository(
            eventDirectoryName: "repo-one-event",
            eventName: "Original",
            explicitLocalEventID: id("canonical-event")
        )
        let secondSource = try makeSourceRepository(
            eventDirectoryName: "repo-two-event",
            eventName: "Updated",
            explicitLocalEventID: id("canonical-event")
        )
        let firstInsertion = try OME.SourceDatabaseInsertion(
            .init(
                source: firstSource,
                organizerID: organizerID,
                sourceProvenance: tangledSourceProvenance("first-source")
            )
        )
        let secondInsertion = try OME.SourceDatabaseInsertion(
            .init(
                source: secondSource,
                organizerID: organizerID,
                sourceProvenance: tangledSourceProvenance("second-source")
            )
        )
        let database = try makeCoreDatabase()

        try await firstInsertion.insert(into: database)
        try await secondInsertion.insert(into: database)

        let eventID = eventID("canonical-event", organizerID: organizerID)
        let event = try await database.read { db in
            try OME.Event.where { $0.id.eq(eventID) }.fetchOne(db)
        }
        let sourceProvenance = try await database.read { db in
            try EventSourceProvenanceRecord
                .where { $0.id.eq(eventID) }
                .fetchOne(db)
        }

        #expect(event?.name == "Updated")
        #expect(sourceProvenance?.sourceReference == "tangled.org/woody.fm/second-source")
        #expect(sourceProvenance?.eventIDOrigin == .explicit)
        #expect(sourceProvenance?.sourceEventDirectory == "repo-two-event")
    }

    @Test
    func rejectsDuplicateResolvedEventIDsWithinSource() throws {
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let firstSource = try makeSourceRepository(
            eventDirectoryName: "first-event",
            explicitLocalEventID: id("canonical-event")
        )
        let secondSource = try makeSourceRepository(
            eventDirectoryName: "second-event",
            explicitLocalEventID: id("canonical-event")
        )
        let source = OpenMusicEventSourceRepository(
            events: firstSource.events + secondSource.events
        )

        do {
            _ = try OME.SourceDatabaseInsertion(
                .init(
                    source: source,
                    organizerID: organizerID,
                    sourceProvenance: tangledSourceProvenance("duplicate-source")
                )
            )
            Issue.record("Expected duplicate event IDs to fail.")
        } catch let error as OME.SourceDatabaseInsertion.Error {
            expectNoDifference(
                error,
                .duplicateEventID(eventID("canonical-event", organizerID: organizerID))
            )
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func sourceValidationSummaryUsesResolvedEventID() throws {
        let source = try makeSourceRepository(
            eventDirectoryName: "repo-directory",
            explicitLocalEventID: id("canonical-event")
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let insertion = try OME.SourceDatabaseInsertion(
            .init(source: source, organizerID: organizerID)
        )

        let summary = SourceValidationSummary(source: source, insertion: insertion)

        expectNoDifference(
            summary.events.map(\.eventID),
            ["canonical-event"]
        )
    }

    @Test
    func resolvesAfterMidnightPerformanceTimes() throws {
        let source = try makeSourceRepository(
            eventDirectoryName: "2025",
            scheduleItems: [
                "meadow": [
                    .init(
                        id: id("late-night"),
                        title: "Late Night",
                        startTime: "23:30"
                    ),
                    .init(
                        id: id("after-midnight"),
                        title: "After Midnight",
                        startTime: "00:15",
                        endTime: "01:00"
                    ),
                ]
            ]
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let insertion = try OME.SourceDatabaseInsertion(
            .init(source: source, organizerID: organizerID)
        )
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let scheduleDate = try #require(LocalDate("2026-08-01"))

        expectNoDifference(
            insertion.scheduleItems,
            [
                OME.ScheduleItem.Draft(
                    id: scheduleItemID("late-night", eventID: "2025", organizerID: organizerID),
                    stageID: id("meadow"),
                    scheduleID: id("saturday"),
                    kind: .known(.performance),
                    startTime: try localDate(scheduleDate, atHour: 23, minute: 30, in: timeZone),
                    endTime: try localDate(
                        scheduleDate,
                        atHour: 0,
                        minute: 15,
                        dayOffset: 1,
                        in: timeZone
                    ),
                    title: "Late Night",
                    description: nil
                ),
                OME.ScheduleItem.Draft(
                    id: scheduleItemID("after-midnight", eventID: "2025", organizerID: organizerID),
                    stageID: id("meadow"),
                    scheduleID: id("saturday"),
                    kind: .known(.performance),
                    startTime: try localDate(
                        scheduleDate,
                        atHour: 0,
                        minute: 15,
                        dayOffset: 1,
                        in: timeZone
                    ),
                    endTime: try localDate(
                        scheduleDate,
                        atHour: 1,
                        dayOffset: 1,
                        in: timeZone
                    ),
                    title: "After Midnight",
                    description: nil
                ),
            ]
        )
    }

    @Test
    func preservesRecordingAssets() throws {
        let externalRecording = ExternalPlatform.Asset(
            url: URL(string: "https://soundcloud.com/example/recording")!
        )
        let atprotoRecording = ExternalPlatform.Asset(
            record: .init(
                uri: ATProto.URI("at://did:plc:streamer/place.stream.livestream/3k5nobkf2w72g")!,
                cid: "bafyreibvlzqnyqbyq2xlxzyelbnzczd3i2cppmx7xghg42yyjz7dss6xju"
            )
        )
        let source = try makeSourceRepository(
            scheduleItems: [
                "meadow": [
                    .init(
                        id: id("recorded-set"),
                        title: "Recorded Set",
                        startTime: "18:00",
                        endTime: "19:00",
                        recordings: [
                            externalRecording,
                            atprotoRecording,
                        ]
                    )
                ]
            ]
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let insertion = try OME.SourceDatabaseInsertion(
            .init(source: source, organizerID: organizerID)
        )

        expectNoDifference(
            insertion.scheduleItemPerformanceDetails.map(\.recordings),
            [
                [
                    externalRecording,
                    atprotoRecording,
                ]
            ]
        )
    }

    @Test
    func throwsWhenFinalPerformanceHasNoEndTime() throws {
        let source = try makeSourceRepository(
            scheduleItems: [
                "meadow": [
                    .init(title: "No End", startTime: "18:00")
                ]
            ]
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))

        do {
            _ = try OME.SourceDatabaseInsertion(
                .init(source: source, organizerID: organizerID)
            )
            Issue.record("Expected missing final performance end time to throw.")
        } catch let error as OME.SourceDatabaseInsertion.Error {
            expectNoDifference(
                error,
                .missingScheduleItemEndTime(
                    scheduleID: scheduleID("saturday", eventID: "testival-2026", organizerID: organizerID),
                    stageID: id("meadow"),
                    scheduleItemIndex: 1
                )
            )
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func coreMigrationAcceptsInsertionRows() async throws {
        let source = try makeSourceRepository()
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let insertion = try OME.SourceDatabaseInsertion(
            .init(source: source, organizerID: organizerID)
        )
        let database = try makeCoreDatabase()

        try await insertion.insert(into: database)

        let organizerCount = try await database.read { db in
            try OME.Organizer.fetchCount(db)
        }
        let eventCount = try await database.read { db in
            try OME.Event.fetchCount(db)
        }
        let eventOrganizerCount = try await database.read { db in
            try OME.EventOrganizer.fetchCount(db)
        }
        let performanceCount = try await database.read { db in
            try OME.Performance.fetchCount(db)
        }
        let performanceContributorCount = try await database.read { db in
            try OME.Performance.Contributors.fetchCount(db)
        }
        let relationships = try await database.read { db in
            try OME.Relationship.fetchAll(db)
        }

        #expect(organizerCount == 1)
        #expect(eventCount == 1)
        #expect(eventOrganizerCount == 1)
        #expect(performanceCount == 3)
        #expect(performanceContributorCount == 2)
        #expect(relationships.count == 3)
        #expect(relationships.allSatisfy { $0.createdAt != pendingRelationshipCreatedAt })
    }

    @Test
    func `published event replacement cannot cross a repository boundary`() async throws {
        let organizerID = try #require(OME.Organizer.ID("did:plc:published-replacement"))
        let installedEventID = eventID("attendee-event", organizerID: organizerID)
        let installedSource = tangledSourceProvenance("installed-source", ref: "old-revision")
        let installedWorkspace = SourceWorkspace(
            organizerID: organizerID,
            repository: installedSource.reference,
            branch: "main"
        )
        let installedInsertion = try OME.SourceDatabaseInsertion(
            .init(
                source: try makeSourceRepository(
                    eventDirectoryName: "attendee-event",
                    eventName: "Installed content",
                    explicitLocalEventID: id("attendee-event")
                ),
                organizerID: organizerID,
                sourceProvenance: installedSource
            )
        )
        let foreignSource = tangledSourceProvenance("foreign-source", ref: "new-revision")
        let foreignWorkspace = SourceWorkspace(
            organizerID: organizerID,
            repository: foreignSource.reference,
            branch: "main"
        )
        let foreignInsertion = try OME.SourceDatabaseInsertion(
            .init(
                source: try makeSourceRepository(
                    eventDirectoryName: "attendee-event",
                    eventName: "Foreign content",
                    explicitLocalEventID: id("attendee-event")
                ),
                organizerID: organizerID,
                sourceProvenance: foreignSource
            )
        )
        let database = try makeCoreDatabase()

        try await installedInsertion.installPublishedEvent(
            installedEventID,
            from: installedWorkspace,
            in: database
        )

        await #expect(throws: (any Error).self) {
            try await foreignInsertion.replacePublishedEvent(
                installedEventID,
                from: foreignWorkspace,
                in: database
            )
        }

        try await database.read { db in
            expectNoDifference(
                try OME.Event.find(installedEventID).fetchOne(db)?.name,
                "Installed content"
            )
            expectNoDifference(
                try EventSourceProvenanceRecord.find(installedEventID).fetchOne(db)?.ref,
                "old-revision"
            )
            expectNoDifference(
                try InstalledEventRecord.find(installedEventID).fetchOne(db)?.ref,
                "main"
            )
        }
    }

    @Test
    func `confirmed authoring exit restores a deleted attendee event and discards workspace state atomically`() async throws {
        let organizerID = try #require(OME.Organizer.ID("did:plc:authoring-exit"))
        let attendeeEventID = eventID("attendee-event", organizerID: organizerID)
        let authoringOnlyEventID = eventID("authoring-only", organizerID: organizerID)
        let installedRevision = "installed-revision"
        let publishedRevision = "published-revision"
        let installedSource = tangledSourceProvenance(
            "authoring-exit",
            ref: installedRevision
        )
        let publishedSource = tangledSourceProvenance(
            "authoring-exit",
            ref: publishedRevision
        )
        let workspace = SourceWorkspace(
            organizerID: organizerID,
            repository: installedSource.reference,
            branch: "main"
        )
        let attendeeSource = try makeSourceRepository(
            eventDirectoryName: "attendee-event",
            eventName: "Published before authoring",
            explicitLocalEventID: id("attendee-event")
        )
        let authoringOnlySource = try makeSourceRepository(
            eventDirectoryName: "authoring-only",
            eventName: "Materialized only for authoring",
            explicitLocalEventID: id("authoring-only")
        )
        let preparedWorkspaceInsertion = try OME.SourceDatabaseInsertion(
            .init(
                source: OpenMusicEventSourceRepository(
                    events: attendeeSource.events + authoringOnlySource.events
                ),
                organizerID: organizerID,
                sourceProvenance: installedSource
            )
        )
        let publishedInsertion = try OME.SourceDatabaseInsertion(
            .init(
                source: try makeSourceRepository(
                    eventDirectoryName: "attendee-event",
                    eventName: "Current published attendee content",
                    explicitLocalEventID: id("attendee-event")
                ),
                organizerID: organizerID,
                sourceProvenance: publishedSource
            )
        )
        let unrelatedOrganizerID = try #require(OME.Organizer.ID("did:plc:unrelated"))
        let unrelatedEventID = eventID("unrelated", organizerID: unrelatedOrganizerID)
        let unrelatedInsertion = try OME.SourceDatabaseInsertion(
            .init(
                source: try makeSourceRepository(
                    eventDirectoryName: "unrelated",
                    eventName: "Unrelated event",
                    explicitLocalEventID: id("unrelated")
                ),
                organizerID: unrelatedOrganizerID
            )
        )
        let database = try makeCoreDatabase()

        try await preparedWorkspaceInsertion.replaceSourceWorkspace(
            workspace,
            branch: workspace.defaultBranch,
            revision: "prepared-revision",
            in: database
        )
        try await unrelatedInsertion.insert(into: database)
        try await database.write { db in
            try InstalledEventRecord.insert {
                InstalledEventRecord(
                    id: attendeeEventID,
                    sourceProvenance: workspace.sourceProvenance
                )
            }
            .execute(db)
            // Deleting the event also deletes its mutable provenance row. Recovery must therefore
            // be driven by the source retained with explicit installation intent.
            try OME.Event.find(attendeeEventID).delete().execute(db)
            try db.execute(
                sql: """
                    INSERT INTO "sourceWorkspaceAuthoringActivations"
                      ("id", "principal", "role", "activatedAt")
                    VALUES (?, '{}', 'owner', '2026-08-10T00:00:00Z');
                    INSERT INTO "sourceWorkspacePublications" ("id") VALUES (?);
                    INSERT INTO "sourceWorkspaceRelationships"
                      ("workspaceID", "actorID", "recordKey", "relationship")
                    VALUES (?, 'did:plc:owner', 'owner', '{}');
                    """,
                arguments: [workspace.id.rawValue, workspace.id.rawValue, workspace.id.rawValue]
            )
        }

        try await OME.SourceDatabaseInsertion.restorePublishedEvents(
            [publishedInsertion],
            from: workspace,
            in: database
        )

        try await database.read { db in
            let events = try OME.Event.fetchAll(db)
            expectNoDifference(
                Set(events.map(\.id)),
                Set([attendeeEventID, unrelatedEventID])
            )
            expectNoDifference(
                try OME.Event.find(attendeeEventID).fetchOne(db)?.name,
                "Current published attendee content"
            )
            #expect(try OME.Event.find(authoringOnlyEventID).fetchOne(db) == nil)
            expectNoDifference(
                try InstalledEventRecord.fetchAll(db).map(\.id),
                [attendeeEventID]
            )
            expectNoDifference(
                try EventSourceProvenanceRecord.find(attendeeEventID).fetchOne(db)?.ref,
                publishedRevision
            )
            expectNoDifference(
                try InstalledEventRecord.find(attendeeEventID).fetchOne(db)?.ref,
                workspace.defaultBranch
            )
            #expect(
                try SourceWorkspaceInstallationRecord.find(workspace.id).fetchOne(db) == nil
            )
            #expect(
                try WorkspaceAuthoringActivationRecord.find(workspace.id).fetchOne(db) == nil
            )
            #expect(
                try WorkspaceRelationshipRecord
                    .where { $0.id.workspaceID.eq(workspace.id) }
                    .fetchCount(db) == 0
            )
            // Publication receipts remain durable after the editing session closes.
            #expect(
                try Int.fetchOne(
                    db,
                    sql: #"SELECT COUNT(*) FROM "sourceWorkspacePublications" WHERE "id" = ?"#,
                    arguments: [workspace.id.rawValue]
                ) == 1
            )
            expectNoDifference(
                try SourceWorkspaceSelectionRecord.find(workspace.id).fetchOne(db),
                SourceWorkspaceSelectionRecord(
                    id: workspace.id,
                    branch: workspace.defaultBranch,
                    revision: "prepared-revision"
                )
            )
        }
    }

    @Test
    func `failed authoring exit leaves edits installation and workspace state intact`() async throws {
        let organizerID = try #require(OME.Organizer.ID("did:plc:authoring-exit-failure"))
        let attendeeEventID = eventID("attendee-event", organizerID: organizerID)
        let sourceProvenance = tangledSourceProvenance("authoring-exit-failure", ref: "main")
        let workspace = SourceWorkspace(
            organizerID: organizerID,
            repository: sourceProvenance.reference,
            branch: "main"
        )
        let preparedWorkspaceInsertion = try OME.SourceDatabaseInsertion(
            .init(
                source: try makeSourceRepository(
                    eventDirectoryName: "attendee-event",
                    eventName: "Published before authoring",
                    explicitLocalEventID: id("attendee-event")
                ),
                organizerID: organizerID,
                sourceProvenance: sourceProvenance
            )
        )
        let database = try makeCoreDatabase()
        try await preparedWorkspaceInsertion.replaceSourceWorkspace(
            workspace,
            branch: workspace.defaultBranch,
            revision: "prepared-revision",
            in: database
        )
        try await database.write { db in
            try InstalledEventRecord.insert {
                InstalledEventRecord(
                    id: attendeeEventID,
                    sourceProvenance: workspace.sourceProvenance
                )
            }
            .execute(db)
            try OME.Event.find(attendeeEventID).update {
                $0.name = "Unpublished local edit"
            }
            .execute(db)
            try db.execute(
                sql: #"INSERT INTO "sourceWorkspacePublications" ("id") VALUES (?)"#,
                arguments: [workspace.id.rawValue]
            )
        }

        // The confirmed exit prepared no published replacement for an explicitly installed event.
        // The guard runs inside the same transaction as deletion and must roll back everything.
        await #expect(throws: (any Error).self) {
            try await OME.SourceDatabaseInsertion.restorePublishedEvents(
                [],
                from: workspace,
                in: database
            )
        }

        try await database.read { db in
            expectNoDifference(
                try OME.Event.find(attendeeEventID).fetchOne(db)?.name,
                "Unpublished local edit"
            )
            expectNoDifference(
                try InstalledEventRecord.fetchAll(db).map(\.id),
                [attendeeEventID]
            )
            expectNoDifference(
                try SourceWorkspaceInstallationRecord.find(workspace.id).fetchOne(db)?.revision,
                "prepared-revision"
            )
            #expect(
                try Int.fetchOne(
                    db,
                    sql: #"SELECT COUNT(*) FROM "sourceWorkspacePublications" WHERE "id" = ?"#,
                    arguments: [workspace.id.rawValue]
                ) == 1
            )
            expectNoDifference(
                try SourceWorkspaceSelectionRecord.find(workspace.id).fetchOne(db),
                SourceWorkspaceSelectionRecord(
                    id: workspace.id,
                    branch: workspace.defaultBranch,
                    revision: "prepared-revision"
                )
            )
        }
    }

    @Test
    func `an exact default branch archive becomes the local patch base`() async throws {
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let workspace = SourceWorkspace(
            organizerID: try #require(OME.Organizer.ID("did:plc:organizer")),
            repository: "tangled.org/example/testival-source",
            branch: "stored-branch"
        )
        let outputURL = directoryURL.appending(path: "repository")
        let upstreamReference = WorkspaceBranchReference(
            branch: WorkspaceBranch(rawValue: "main"),
            revision: WorkspaceRevision(rawValue: "upstream-revision")
        )
        let resolvedRepositories = Mutex<[TangledRepositoryReference]>([])
        let archiveRequests = Mutex<[TangledSourceCheckoutRequest]>([])
        let initializedURLs = Mutex<[URL]>([])
        let stageRequests = Mutex<[StageRequest]>([])
        let commitRequests = Mutex<[CommitRequest]>([])

        var sourceControl = SourceControlClient.unimplemented
        sourceControl.initialize = { url in
            initializedURLs.withLock { $0.append(url) }
            return Repository(url: url)
        }
        sourceControl.stage = { request in
            stageRequests.withLock { $0.append(request) }
        }
        sourceControl.commit = { request in
            commitRequests.withLock { $0.append(request) }
            return Commit(id: CommitID(rawValue: "local-base-revision"))
        }

        let checkout = try await withDependencies {
            $0.sourceControl = sourceControl
            $0.tangledDefaultBranch = TangledDefaultBranchClient { repository in
                resolvedRepositories.withLock { $0.append(repository) }
                return upstreamReference
            }
            $0.tangledSourceCheckout = TangledSourceCheckoutClient { request in
                archiveRequests.withLock { $0.append(request) }
                let eventURL = request.outputURL.appending(
                    path: "events/testival-2026/event.yml"
                )
                try FileManager.default.createDirectory(
                    at: eventURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data("name: Testival".utf8).write(to: eventURL)
                try Data("archive marker".utf8).write(
                    to: request.outputURL.appending(path: ".source-marker")
                )
                return TangledSourceCheckout(repositoryURL: request.outputURL)
            }
        } operation: {
            try await SourceWorkspaceCheckoutClient.liveValue.checkout(
                workspace,
                nil,
                outputURL
            )
        }

        let tangledRepository = try TangledRepositoryReference(
            sourceReference: workspace.repository
        )
        expectNoDifference(resolvedRepositories.withLock { $0 }, [tangledRepository])
        let archiveRequest = try #require(archiveRequests.withLock { $0.first })
        expectNoDifference(archiveRequest.repository, tangledRepository)
        expectNoDifference(archiveRequest.ref, "upstream-revision")
        expectNoDifference(archiveRequest.outputURL.path, outputURL.path)
        expectNoDifference(
            initializedURLs.withLock { $0.map(\.path) },
            [outputURL.path]
        )
        let stageRequest = try #require(stageRequests.withLock { $0.first })
        expectNoDifference(stageRequest.repository.url.path, outputURL.path)
        expectNoDifference(
            stageRequest.paths,
            [
                RepositoryPath(rawValue: ".source-marker"),
                RepositoryPath(rawValue: "events/testival-2026/event.yml"),
            ]
        )
        let commitRequest = try #require(commitRequests.withLock { $0.first })
        expectNoDifference(commitRequest.repository.url.path, outputURL.path)
        expectNoDifference(
            commitRequest.message,
            CommitMessage(rawValue: "Import source at upstream-revision")
        )
        expectNoDifference(
            commitRequest.author,
            Author(
                name: PersonName(rawValue: "Open Music Event"),
                email: EmailAddress(rawValue: "noreply@openmusicevent.app")
            )
        )
        expectNoDifference(checkout.repository.url.path, outputURL.path)
        expectNoDifference(
            checkout.reference,
            upstreamReference
        )
    }

    @Test
    func `unsupported archive properties preserve a preexisting workspace path`() async throws {
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let workspace = SourceWorkspace(
            organizerID: try #require(OME.Organizer.ID("did:plc:organizer")),
            repository: "tangled.org/example/testival-source",
            branch: "main"
        )
        let outputURL = directoryURL.appending(path: "repository")
        try FileManager.default.createDirectory(
            at: outputURL,
            withIntermediateDirectories: true
        )
        let sentinelURL = outputURL.appending(path: "keep-me.txt")
        try Data("preexisting".utf8).write(to: sentinelURL)
        let linkURL = outputURL.appending(path: "linked-source.yml")

        await #expect(throws: (any Error).self) {
            try await withDependencies {
                $0.sourceControl = .unimplemented
                $0.tangledDefaultBranch = TangledDefaultBranchClient { _ in
                    WorkspaceBranchReference(
                        branch: WorkspaceBranch(rawValue: "main"),
                        revision: WorkspaceRevision(rawValue: "upstream-revision")
                    )
                }
                $0.tangledSourceCheckout = TangledSourceCheckoutClient { request in
                    try FileManager.default.createSymbolicLink(
                        at: linkURL,
                        withDestinationURL: sentinelURL
                    )
                    return TangledSourceCheckout(repositoryURL: request.outputURL)
                }
            } operation: {
                try await SourceWorkspaceCheckoutClient.liveValue.checkout(
                    workspace,
                    nil,
                    outputURL
                )
            }
        }

        #expect(FileManager.default.fileExists(atPath: outputURL.path))
        expectNoDifference(try Data(contentsOf: sentinelURL), Data("preexisting".utf8))
        #expect(FileManager.default.fileExists(atPath: linkURL.path))
    }

    @Test
    func `a failed fresh archive checkout removes only its owned output`() async throws {
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let workspace = SourceWorkspace(
            organizerID: try #require(OME.Organizer.ID("did:plc:organizer")),
            repository: "tangled.org/example/testival-source",
            branch: "main"
        )
        let outputURL = directoryURL.appending(path: "repository")

        await #expect(throws: (any Error).self) {
            try await withDependencies {
                $0.sourceControl = .unimplemented
                $0.tangledDefaultBranch = TangledDefaultBranchClient { _ in
                    WorkspaceBranchReference(
                        branch: WorkspaceBranch(rawValue: "main"),
                        revision: WorkspaceRevision(rawValue: "upstream-revision")
                    )
                }
                $0.tangledSourceCheckout = TangledSourceCheckoutClient { request in
                    try FileManager.default.createDirectory(
                        at: request.outputURL,
                        withIntermediateDirectories: true
                    )
                    let sentinelURL = request.outputURL.appending(path: "sentinel.txt")
                    try Data("temporary".utf8).write(to: sentinelURL)
                    try FileManager.default.createSymbolicLink(
                        at: request.outputURL.appending(path: "linked-source.yml"),
                        withDestinationURL: sentinelURL
                    )
                    return TangledSourceCheckout(repositoryURL: request.outputURL)
                }
            } operation: {
                try await SourceWorkspaceCheckoutClient.liveValue.checkout(
                    workspace,
                    nil,
                    outputURL
                )
            }
        }

        #expect(!FileManager.default.fileExists(atPath: outputURL.path))
    }

    @Test
    func `a published revision starts source authoring on main`() async throws {
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let database = try makeCoreDatabase(
            path: directoryURL.appending(path: "application.sqlite").path
        )
        let storage = SourceWorkspaceStorage.fileBacked(
            rootURL: directoryURL.appending(path: "workspaces")
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let publishedRevision = "3cc283a5d07218f4dfc55652513e9191d2040a06"
        let sourceReference = "tangled.org/example/testival-source"
        let eventID = eventID(
            "testival-source-testival-2026",
            organizerID: organizerID
        )
        let provenance = EventSourceProvenanceRecord(
            id: eventID,
            sourceKind: .tangled,
            sourceReference: sourceReference,
            ref: publishedRevision,
            eventIDOrigin: .inferred,
            sourceEventDirectory: "testival-2026"
        )
        let workspace = try #require(provenance.workspace)
        let recordWorkspace = SourceWorkspace(
            organizerID: organizerID,
            sourceRecord: OME.SourceRecord(
                kind: .tangled,
                reference: sourceReference,
                ref: publishedRevision
            )
        )
        let installedWorkspace = try #require(
            InstalledEventRecord(
                id: eventID,
                sourceProvenance: provenance.sourceProvenance
            )
            .workspace
        )
        expectNoDifference(provenance.ref, publishedRevision)
        expectNoDifference(workspace.defaultBranch, "main")
        expectNoDifference(recordWorkspace, workspace)
        expectNoDifference(installedWorkspace, workspace)

        let source = try makeSourceRepository()
        let checkoutRefs = Mutex<[String]>([])
        var sourceControl = SourceControlClient.unimplemented
        sourceControl.open = { Repository(url: $0) }

        let prepared = try await withDependencies {
            $0.defaultDatabase = database
            $0.sourceControl = sourceControl
            $0.sourceWorkspaceReferenceMigrator = .openMusicEvent
            $0.sourceWorkspaceStorage = storage
            $0[SourceWorkspaceCheckoutClient.self] = SourceWorkspaceCheckoutClient {
                checkedOutWorkspace, _, outputURL in
                checkoutRefs.withLock { $0.append(checkedOutWorkspace.defaultBranch) }
                try FileManager.default.createDirectory(
                    at: outputURL,
                    withIntermediateDirectories: true
                )
                _ = try OpenMusicEventSourceRepositoryFileTree().write(
                    source,
                    to: outputURL
                )
                return SourceWorkspaceCheckout(
                    repository: Repository(url: outputURL),
                    reference: WorkspaceBranchReference(
                        branch: WorkspaceBranch(rawValue: "main"),
                        revision: WorkspaceRevision(rawValue: "main-revision")
                    )
                )
            }
        } operation: {
            try await SourceWorkspacePreparationClient
                .openMusicEvent { _, _ in CommitID(rawValue: "local-base-revision") }
                .prepare(workspace)
        }

        expectNoDifference(checkoutRefs.withLock { $0 }, ["main"])
        expectNoDifference(
            prepared.baseline,
            WorkspaceBranchReference(
                branch: WorkspaceBranch(rawValue: "main"),
                revision: WorkspaceRevision(rawValue: "main-revision")
            )
        )
    }

    @Test
    func `a published workspace refreshes from the exact default branch archive`() async throws {
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let database = try makeCoreDatabase(
            path: directoryURL.appending(path: "application.sqlite").path
        )
        let storage = SourceWorkspaceStorage.fileBacked(
            rootURL: directoryURL.appending(path: "workspaces")
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let workspace = SourceWorkspace(
            organizerID: organizerID,
            repository: "tangled.org/example/testival-source",
            branch: "main"
        )
        let oldReference = WorkspaceBranchReference(
            branch: WorkspaceBranch(rawValue: "main"),
            revision: WorkspaceRevision(rawValue: "old-upstream-revision")
        )
        let newReference = WorkspaceBranchReference(
            branch: WorkspaceBranch(rawValue: "main"),
            revision: WorkspaceRevision(rawValue: "new-upstream-revision")
        )
        let checkoutCount = Mutex(0)
        let patchBaseURLs = Mutex<[URL?]>([])
        let patchDatabaseIDs = Mutex<[ObjectIdentifier]>([])
        var sourceControl = SourceControlClient.unimplemented
        sourceControl.open = { Repository(url: $0) }
        let resolveRevision: SourceWorkspaceRevisionResolver = { _, _ in
            CommitID(rawValue: "synthetic-local-base")
        }

        try await withDependencies {
            $0.defaultDatabase = database
            $0.sourceControl = sourceControl
            $0.sourceWorkspaceReferenceMigrator = .openMusicEvent
            $0.sourceWorkspaceStorage = storage
            $0[SourcePatchGeneratorKey<SourceWorkspacePatchRequest>.self] =
                SourcePatchGenerator { request in
                    @Dependency(\.defaultDatabase) var activeDatabase
                    patchBaseURLs.withLock { $0.append(request.baseRepositoryURL) }
                    patchDatabaseIDs.withLock { $0.append(ObjectIdentifier(activeDatabase)) }
                    return SourcePatch()
                }
            $0[SourceWorkspaceCheckoutClient.self] = SourceWorkspaceCheckoutClient {
                _, _, outputURL in
                let index = checkoutCount.withLock {
                    $0 += 1
                    return $0
                }
                try FileManager.default.createDirectory(
                    at: outputURL.appending(path: ".git"),
                    withIntermediateDirectories: true
                )
                _ = try OpenMusicEventSourceRepositoryFileTree().write(
                    makeSourceRepository(
                        eventName: index == 1 ? "Before publish" : "After publish"
                    ),
                    to: outputURL
                )
                return SourceWorkspaceCheckout(
                    repository: Repository(url: outputURL),
                    reference: index == 1 ? oldReference : newReference
                )
            }
        } operation: {
            let prepared = try await SourceWorkspacePreparationClient
                .openMusicEvent(resolveRevision: resolveRevision)
                .prepare(workspace)
            expectNoDifference(prepared.baseline, oldReference)

            let result = try await WorkspaceReferenceUpdateClient
                .openMusicEvent(resolveRevision: resolveRevision)
                .reconcile(
                    prepared.source,
                    workspace.id,
                    prepared.baseline
                )
            guard case let .current(refreshed) = result else {
                Issue.record("Expected the advanced baseline to reconcile without conflicts")
                return
            }

            expectNoDifference(refreshed.baseline, newReference)
            expectNoDifference(checkoutCount.withLock { $0 }, 2)
            let recordedPatchBaseURLs = patchBaseURLs.withLock { $0 }
            expectNoDifference(recordedPatchBaseURLs, [nil])
            expectNoDifference(
                patchDatabaseIDs.withLock { $0 },
                [ObjectIdentifier(database)]
            )
            let event = try await database.read { db in
                try #require(
                    try OME.Event.find(
                        eventID(
                            "testival-source-testival-2026",
                            organizerID: organizerID
                        )
                    )
                    .fetchOne(db)
                )
            }
            expectNoDifference(event.name, "After publish")
            let persisted = try await (
                prepared.source.referenceDatabase.read { db in
                    try SourceWorkspaceReferenceRecord.find(workspace.id).fetchOne(db)?.revision
                },
                database.read { db in
                    (
                        installation: try SourceWorkspaceInstallationRecord
                            .find(workspace.id)
                            .fetchOne(db)?.revision,
                        selection: try SourceWorkspaceSelectionRecord
                            .find(workspace.id)
                            .fetchOne(db)
                    )
                }
            )
            expectNoDifference(persisted.0, Optional(newReference.revision.rawValue))
            expectNoDifference(persisted.1.installation, Optional(newReference.revision.rawValue))
            expectNoDifference(
                persisted.1.selection,
                SourceWorkspaceSelectionRecord(
                    id: workspace.id,
                    branch: newReference.branch.rawValue,
                    revision: newReference.revision.rawValue
                )
            )
            let installedSource = try OpenMusicEventSourceRepositoryFileTree()
                .read(from: prepared.source.repositoryURL)
                .output
                .requiredValue
            expectNoDifference(
                installedSource.events.first?.components.event.name,
                "After publish"
            )
            let temporaryRepositories = try FileManager.default.contentsOfDirectory(
                at: prepared.source.repositoryURL.deletingLastPathComponent(),
                includingPropertiesForKeys: nil
            )
            .filter {
                $0.lastPathComponent.hasPrefix("repository-refresh-")
                    || $0.lastPathComponent.hasPrefix("repository-backup-")
            }
            expectNoDifference(temporaryRepositories, [])
        }
    }

    @Test
    func `a newer published source preserves two locally added communication posts`() async throws {
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let database = try makeCoreDatabase(
            path: directoryURL.appending(path: "application.sqlite").path
        )
        let storage = SourceWorkspaceStorage.fileBacked(
            rootURL: directoryURL.appending(path: "workspaces")
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let workspace = SourceWorkspace(
            organizerID: organizerID,
            repository: "tangled.org/example/postival-source",
            branch: "main"
        )
        let oldReference = WorkspaceBranchReference(
            branch: WorkspaceBranch(rawValue: "main"),
            revision: WorkspaceRevision(
                rawValue: "b39b6a451ba364df9158f9654248c199bfd92787"
            )
        )
        let newReference = WorkspaceBranchReference(
            branch: WorkspaceBranch(rawValue: "main"),
            revision: WorkspaceRevision(
                rawValue: "5367c67e6444019c1ee111cc93e43a4ece11fcd6"
            )
        )
        let checkoutCount = Mutex(0)
        var sourceControl = SourceControlClient.unimplemented
        sourceControl.open = { Repository(url: $0) }
        sourceControl.mergeFile = deterministicWorkspaceFileMerge
        let resolveRevision: SourceWorkspaceRevisionResolver = { _, _ in
            CommitID(rawValue: "synthetic-local-base")
        }

        try await withDependencies {
            $0.defaultDatabase = database
            $0.sourceControl = sourceControl
            $0.sourceWorkspaceReferenceMigrator = .openMusicEvent
            $0.sourceWorkspaceStorage = storage
            $0[SourcePatchGeneratorKey<SourceWorkspacePatchRequest>.self] = .openMusicEvent
            $0.sourceWorkspacePatchConversion = .live
            $0[SourceWorkspaceCheckoutClient.self] = SourceWorkspaceCheckoutClient {
                _, _, outputURL in
                let index = checkoutCount.withLock {
                    $0 += 1
                    return $0
                }
                try FileManager.default.createDirectory(
                    at: outputURL.appending(path: ".git"),
                    withIntermediateDirectories: true
                )
                var source = try sourceRepositoryWithCommunicationPosts(includePosts: false)
                if index > 1 {
                    source.events[0].components.event.description =
                        "The published schedule now includes Thursday arrival."
                }
                _ = try OpenMusicEventSourceRepositoryFileTree().write(
                    source,
                    to: outputURL
                )
                return SourceWorkspaceCheckout(
                    repository: Repository(url: outputURL),
                    reference: index == 1 ? oldReference : newReference
                )
            }
        } operation: {
            let prepared = try await SourceWorkspacePreparationClient
                .openMusicEvent(resolveRevision: resolveRevision)
                .prepare(workspace)
            let localEventID = id("postival-source-postival-2026") as OME.ID<OME.Event>
            try await database.write { db in
                for (index, postID) in ["gates-open", "weather-update"].enumerated() {
                    try CommsPost.insert {
                        CommsPost(
                            id: CommsPost.ID(
                                organizerID: organizerID,
                                eventID: localEventID,
                                channelID: id("general"),
                                postID: CommsPost.PostID(postID)
                            ),
                            title: postID == "gates-open" ? "Gates are open" : "Weather update",
                            contents: postID == "gates-open"
                                ? "Welcome to the festival."
                                : "Bring a warm layer.",
                            sortIndex: index
                        )
                    }
                    .execute(db)
                }
            }

            let localPatchBefore = try await SourcePatchGenerator<SourceWorkspacePatchRequest>
                .openMusicEvent
                .generate(SourceWorkspacePatchRequest(workspace: workspace))
            expectNoDifference(
                localPatchBefore.fileChanges.map(\.path),
                [
                    "events/postival-2026/communications/general/gates-open.md",
                    "events/postival-2026/communications/general/weather-update.md",
                ]
            )

            let result = try await WorkspaceReferenceUpdateClient
                .openMusicEvent(resolveRevision: resolveRevision)
                .reconcile(
                    prepared.source,
                    workspace.id,
                    prepared.baseline
                )
            guard case let .current(reconciled) = result else {
                Issue.record("Expected independent communication additions to reconcile")
                return
            }
            expectNoDifference(reconciled.baseline, newReference)

            let working = try await database.read { db in
                (
                    event: try OME.Event
                        .find(eventID("postival-source-postival-2026", organizerID: organizerID))
                        .fetchOne(db),
                    posts: try CommsPost.order { $0.sortIndex }.fetchAll(db),
                    installation: try SourceWorkspaceInstallationRecord
                        .find(workspace.id)
                        .fetchOne(db),
                    selection: try SourceWorkspaceSelectionRecord
                        .find(workspace.id)
                        .fetchOne(db)
                )
            }
            expectNoDifference(
                working.event?.description,
                "The published schedule now includes Thursday arrival."
            )
            expectNoDifference(
                working.posts.map(\.id.postID.rawValue),
                ["gates-open", "weather-update"]
            )
            expectNoDifference(working.installation?.revision, newReference.revision.rawValue)
            expectNoDifference(
                working.selection,
                SourceWorkspaceSelectionRecord(
                    id: workspace.id,
                    branch: newReference.branch.rawValue,
                    revision: newReference.revision.rawValue
                )
            )

            let reference = try prepared.source.referenceDatabase.read { db in
                (
                    revision: try SourceWorkspaceReferenceRecord
                        .find(workspace.id)
                        .fetchOne(db)?.revision,
                    postCount: try CommsPost.fetchCount(db)
                )
            }
            expectNoDifference(reference.revision, Optional(newReference.revision.rawValue))
            expectNoDifference(reference.postCount, 0)

            let installedSource = try OpenMusicEventSourceRepositoryFileTree()
                .read(from: prepared.source.repositoryURL)
                .output
                .requiredValue
            expectNoDifference(
                installedSource.events.first?.components.event.description,
                "The published schedule now includes Thursday arrival."
            )
            #expect(installedSource.events.first?.components.communicationPosts == nil)

            let localPatchAfter = try await SourcePatchGenerator<SourceWorkspacePatchRequest>
                .openMusicEvent
                .generate(SourceWorkspacePatchRequest(workspace: workspace))
            expectNoDifference(localPatchAfter, localPatchBefore)
        }
    }

    @Test
    func `independent edits in one event file reconcile into working and reference sources`() async throws {
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let database = try makeCoreDatabase(
            path: directoryURL.appending(path: "application.sqlite").path
        )
        let storage = SourceWorkspaceStorage.fileBacked(
            rootURL: directoryURL.appending(path: "workspaces")
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let workspace = SourceWorkspace(
            organizerID: organizerID,
            repository: "tangled.org/example/testival-source",
            branch: "main"
        )
        let oldReference = WorkspaceBranchReference(
            branch: WorkspaceBranch(rawValue: "main"),
            revision: WorkspaceRevision(rawValue: "old-upstream-revision")
        )
        let newReference = WorkspaceBranchReference(
            branch: WorkspaceBranch(rawValue: "main"),
            revision: WorkspaceRevision(rawValue: "new-upstream-revision")
        )
        let checkoutCount = Mutex(0)
        let mergeCount = Mutex(0)
        var sourceControl = SourceControlClient.unimplemented
        sourceControl.open = { Repository(url: $0) }
        sourceControl.mergeFile = { request in
            mergeCount.withLock { $0 += 1 }
            let base = String(decoding: try #require(request.baseContents), as: UTF8.self)
            let local = String(decoding: try #require(request.localContents), as: UTF8.self)
            let upstream = String(
                decoding: try #require(request.upstreamContents),
                as: UTF8.self
            )
            #expect(request.path.rawValue == "events/testival-2026/event.yml")
            #expect(base.contains("Original event"))
            #expect(base.contains("A small fixture event."))
            #expect(local.contains("My local event"))
            #expect(local.contains("A small fixture event."))
            #expect(upstream.contains("Original event"))
            #expect(upstream.contains("Published description"))
            let merged = upstream.replacingOccurrences(
                of: "Original event",
                with: "My local event"
            )
            return .merged(contents: Data(merged.utf8))
        }
        let resolveRevision: SourceWorkspaceRevisionResolver = { _, _ in
            CommitID(rawValue: "synthetic-local-base")
        }

        try await withDependencies {
            $0.defaultDatabase = database
            $0.sourceControl = sourceControl
            $0.sourceWorkspaceReferenceMigrator = .openMusicEvent
            $0.sourceWorkspaceStorage = storage
            $0[SourcePatchGeneratorKey<SourceWorkspacePatchRequest>.self] = .openMusicEvent
            $0.sourceWorkspacePatchConversion = .live
            $0[SourceWorkspaceCheckoutClient.self] = SourceWorkspaceCheckoutClient {
                _, _, outputURL in
                let index = checkoutCount.withLock {
                    $0 += 1
                    return $0
                }
                try FileManager.default.createDirectory(
                    at: outputURL.appending(path: ".git"),
                    withIntermediateDirectories: true
                )
                var checkedOutSource = try makeSourceRepository(eventName: "Original event")
                if index > 1 {
                    checkedOutSource.events[0].components.event.description =
                        "Published description"
                }
                _ = try OpenMusicEventSourceRepositoryFileTree().write(
                    checkedOutSource,
                    to: outputURL
                )
                return SourceWorkspaceCheckout(
                    repository: Repository(url: outputURL),
                    reference: index == 1 ? oldReference : newReference
                )
            }
        } operation: {
            let prepared = try await SourceWorkspacePreparationClient
                .openMusicEvent(resolveRevision: resolveRevision)
                .prepare(workspace)
            let eventID = eventID("testival-source-testival-2026", organizerID: organizerID)
            try await database.write { db in
                try OME.Event.find(eventID).update { $0.name = "My local event" }.execute(db)
            }

            let result = try await WorkspaceReferenceUpdateClient
                .openMusicEvent(resolveRevision: resolveRevision)
                .reconcile(
                    prepared.source,
                    workspace.id,
                    prepared.baseline
                )
            guard case let .current(reconciled) = result else {
                Issue.record("Expected independent event-file edits to reconcile")
                return
            }

            expectNoDifference(reconciled.baseline, newReference)
            expectNoDifference(checkoutCount.withLock { $0 }, 2)
            expectNoDifference(mergeCount.withLock { $0 }, 1)
            let workingEvent = try #require(await database.read { db in
                try OME.Event.find(eventID).fetchOne(db)
            })
            expectNoDifference(workingEvent.name, "My local event")
            expectNoDifference(workingEvent.description, "Published description")
            let referenceEvent = try #require(prepared.source.referenceDatabase.read { db in
                try OME.Event.find(eventID).fetchOne(db)
            })
            expectNoDifference(referenceEvent.name, "Original event")
            expectNoDifference(referenceEvent.description, "Published description")
            let installedEvent = try #require(
                OpenMusicEventSourceRepositoryFileTree()
                    .read(from: prepared.source.repositoryURL)
                    .output
                    .requiredValue
                    .events.first?.components.event
            )
            expectNoDifference(installedEvent.name, "Original event")
            expectNoDifference(installedEvent.description, "Published description")
            let remainingPatch = try await SourcePatchGenerator<SourceWorkspacePatchRequest>
                .openMusicEvent
                .generate(SourceWorkspacePatchRequest(workspace: workspace))
            expectNoDifference(
                remainingPatch.fileChanges.map(\.path),
                ["events/testival-2026/event.yml"]
            )
        }
    }

    @Test
    func `a local edit already present upstream leaves no remaining workspace change`() async throws {
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let database = try makeCoreDatabase(
            path: directoryURL.appending(path: "application.sqlite").path
        )
        let storage = SourceWorkspaceStorage.fileBacked(
            rootURL: directoryURL.appending(path: "workspaces")
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let workspace = SourceWorkspace(
            organizerID: organizerID,
            repository: "tangled.org/example/testival-source",
            branch: "main"
        )
        let oldReference = WorkspaceBranchReference(
            branch: WorkspaceBranch(rawValue: "main"),
            revision: WorkspaceRevision(rawValue: "old-upstream-revision")
        )
        let newReference = WorkspaceBranchReference(
            branch: WorkspaceBranch(rawValue: "main"),
            revision: WorkspaceRevision(rawValue: "new-upstream-revision")
        )
        let checkoutCount = Mutex(0)
        let mergeCount = Mutex(0)
        var sourceControl = SourceControlClient.unimplemented
        sourceControl.open = { Repository(url: $0) }
        sourceControl.mergeFile = { request in
            mergeCount.withLock { $0 += 1 }
            return try await deterministicWorkspaceFileMerge(request)
        }
        let resolveRevision: SourceWorkspaceRevisionResolver = { _, _ in
            CommitID(rawValue: "synthetic-local-base")
        }

        try await withDependencies {
            $0.defaultDatabase = database
            $0.sourceControl = sourceControl
            $0.sourceWorkspaceReferenceMigrator = .openMusicEvent
            $0.sourceWorkspaceStorage = storage
            $0[SourcePatchGeneratorKey<SourceWorkspacePatchRequest>.self] = .openMusicEvent
            $0.sourceWorkspacePatchConversion = .live
            $0[SourceWorkspaceCheckoutClient.self] = SourceWorkspaceCheckoutClient {
                _, _, outputURL in
                let index = checkoutCount.withLock {
                    $0 += 1
                    return $0
                }
                try FileManager.default.createDirectory(
                    at: outputURL.appending(path: ".git"),
                    withIntermediateDirectories: true
                )
                _ = try OpenMusicEventSourceRepositoryFileTree().write(
                    makeSourceRepository(
                        eventName: index == 1 ? "Original event" : "Shared edit"
                    ),
                    to: outputURL
                )
                return SourceWorkspaceCheckout(
                    repository: Repository(url: outputURL),
                    reference: index == 1 ? oldReference : newReference
                )
            }
        } operation: {
            let prepared = try await SourceWorkspacePreparationClient
                .openMusicEvent(resolveRevision: resolveRevision)
                .prepare(workspace)
            let eventID = eventID("testival-source-testival-2026", organizerID: organizerID)
            try await database.write { db in
                try OME.Event.find(eventID).update { $0.name = "Shared edit" }.execute(db)
            }

            let result = try await WorkspaceReferenceUpdateClient
                .openMusicEvent(resolveRevision: resolveRevision)
                .reconcile(
                    prepared.source,
                    workspace.id,
                    prepared.baseline
                )
            guard case let .current(reconciled) = result else {
                Issue.record("Expected an already-published local edit to reconcile")
                return
            }

            expectNoDifference(reconciled.baseline, newReference)
            expectNoDifference(checkoutCount.withLock { $0 }, 2)
            expectNoDifference(mergeCount.withLock { $0 }, 1)
            let workingEventName = try await database.read { db in
                try OME.Event.find(eventID).fetchOne(db)?.name
            }
            expectNoDifference(workingEventName, "Shared edit")
            expectNoDifference(
                try prepared.source.referenceDatabase.read { db in
                    try OME.Event.find(eventID).fetchOne(db)?.name
                },
                "Shared edit"
            )
            #expect(
                try await SourcePatchGenerator<SourceWorkspacePatchRequest>
                    .openMusicEvent
                    .generate(SourceWorkspacePatchRequest(workspace: workspace))
                    .isEmpty
            )
        }
    }

    @Test(arguments: [
        WorkspaceCommunicationConflictScenario.addAdd,
        .deleteModify,
    ])
    func `add-add and delete-modify communication changes conflict without persistence mutation`(
        _ scenario: WorkspaceCommunicationConflictScenario
    ) async throws {
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let database = try makeCoreDatabase(
            path: directoryURL.appending(path: "application.sqlite").path
        )
        let storage = SourceWorkspaceStorage.fileBacked(
            rootURL: directoryURL.appending(path: "workspaces")
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let workspace = SourceWorkspace(
            organizerID: organizerID,
            repository: "tangled.org/example/postival-source",
            branch: "main"
        )
        let oldReference = WorkspaceBranchReference(
            branch: WorkspaceBranch(rawValue: "main"),
            revision: WorkspaceRevision(rawValue: "old-upstream-revision")
        )
        let newReference = WorkspaceBranchReference(
            branch: WorkspaceBranch(rawValue: "main"),
            revision: WorkspaceRevision(rawValue: "new-upstream-revision")
        )
        let checkoutCount = Mutex(0)
        let mergeCount = Mutex(0)
        var sourceControl = SourceControlClient.unimplemented
        sourceControl.open = { Repository(url: $0) }
        sourceControl.mergeFile = { request in
            mergeCount.withLock { $0 += 1 }
            #expect(
                request.path.rawValue
                    == "events/postival-2026/communications/general/arrival.md"
            )
            switch scenario {
            case .addAdd:
                #expect(request.baseContents == nil)
                #expect(request.localContents != nil)
                #expect(request.upstreamContents != nil)
                #expect(request.localContents != request.upstreamContents)

            case .deleteModify:
                #expect(request.baseContents != nil)
                #expect(request.localContents == nil)
                #expect(request.upstreamContents != nil)
                #expect(request.baseContents != request.upstreamContents)
            }
            return try await deterministicWorkspaceFileMerge(request)
        }
        let resolveRevision: SourceWorkspaceRevisionResolver = { _, _ in
            CommitID(rawValue: "synthetic-local-base")
        }

        try await withDependencies {
            $0.defaultDatabase = database
            $0.sourceControl = sourceControl
            $0.sourceWorkspaceReferenceMigrator = .openMusicEvent
            $0.sourceWorkspaceStorage = storage
            $0[SourcePatchGeneratorKey<SourceWorkspacePatchRequest>.self] = .openMusicEvent
            $0.sourceWorkspacePatchConversion = .live
            $0[SourceWorkspaceCheckoutClient.self] = SourceWorkspaceCheckoutClient {
                _, _, outputURL in
                let index = checkoutCount.withLock {
                    $0 += 1
                    return $0
                }
                try FileManager.default.createDirectory(
                    at: outputURL.appending(path: ".git"),
                    withIntermediateDirectories: true
                )
                var checkedOutSource = try sourceRepositoryWithCommunicationPosts(
                    includePosts: scenario == .deleteModify || index > 1
                )
                if scenario == .deleteModify, index > 1 {
                    checkedOutSource.events[0]
                        .components
                        .communicationPosts?[0]
                        .components[0]
                        .data = CommunicationPostDTO(
                            title: "Published arrival",
                            contents: "Use the south gate."
                        )
                }
                _ = try OpenMusicEventSourceRepositoryFileTree().write(
                    checkedOutSource,
                    to: outputURL
                )
                return SourceWorkspaceCheckout(
                    repository: Repository(url: outputURL),
                    reference: index == 1 ? oldReference : newReference
                )
            }
        } operation: {
            let prepared = try await SourceWorkspacePreparationClient
                .openMusicEvent(resolveRevision: resolveRevision)
                .prepare(workspace)
            let localEventID = id("postival-source-postival-2026") as OME.ID<OME.Event>
            let arrivalID = CommsPost.ID(
                organizerID: organizerID,
                eventID: localEventID,
                channelID: id("general"),
                postID: CommsPost.PostID("arrival")
            )
            try await database.write { db in
                switch scenario {
                case .addAdd:
                    try CommsPost.insert {
                        CommsPost(
                            id: arrivalID,
                            title: "My arrival",
                            contents: "Use the west gate.",
                            sortIndex: 0
                        )
                    }
                    .execute(db)

                case .deleteModify:
                    try CommsPost.find(arrivalID).delete().execute(db)
                }
            }
            let patchBefore = try await SourcePatchGenerator<SourceWorkspacePatchRequest>
                .openMusicEvent
                .generate(SourceWorkspacePatchRequest(workspace: workspace))
            expectNoDifference(
                patchBefore.fileChanges.map(\.path),
                ["events/postival-2026/communications/general/arrival.md"]
            )

            let result = try await WorkspaceReferenceUpdateClient
                .openMusicEvent(resolveRevision: resolveRevision)
                .reconcile(
                    prepared.source,
                    workspace.id,
                    prepared.baseline
                )
            guard case let .conflicted(conflict) = result else {
                Issue.record("Expected \(scenario) to conflict")
                return
            }

            expectNoDifference(conflict.baseline, oldReference)
            expectNoDifference(conflict.upstream, newReference)
            expectNoDifference(
                conflict.conflictingPaths.map(\.rawValue),
                ["events/postival-2026/communications/general/arrival.md"]
            )
            expectNoDifference(checkoutCount.withLock { $0 }, 2)
            expectNoDifference(mergeCount.withLock { $0 }, 1)
            let patchAfter = try await SourcePatchGenerator<SourceWorkspacePatchRequest>
                .openMusicEvent
                .generate(SourceWorkspacePatchRequest(workspace: workspace))
            expectNoDifference(patchAfter, patchBefore)
            let persistedRevision = try await database.read { db in
                try SourceWorkspaceInstallationRecord
                    .find(workspace.id)
                    .fetchOne(db)?.revision
            }
            expectNoDifference(persistedRevision, oldReference.revision.rawValue)
            let reference = try prepared.source.referenceDatabase.read { db in
                (
                    try SourceWorkspaceReferenceRecord
                        .find(workspace.id)
                        .fetchOne(db)?.revision,
                    try CommsPost.fetchCount(db)
                )
            }
            expectNoDifference(reference.0, oldReference.revision.rawValue)
            expectNoDifference(reference.1, scenario == .addAdd ? 0 : 2)
            let installedPosts = try OpenMusicEventSourceRepositoryFileTree()
                .read(from: prepared.source.repositoryURL)
                .output
                .requiredValue
                .events
                .first?
                .components
                .communicationPosts?
                .flatMap(\.components)
            expectNoDifference(installedPosts?.count ?? 0, scenario == .addAdd ? 0 : 2)
        }
    }

    @Test(arguments: [
        WorkspaceReconciliationFailurePoint.referenceDatabase,
        .writableDatabase,
        .repository,
    ])
    func `failed reconciliation commit restores the old baseline and every local edit`(
        _ failurePoint: WorkspaceReconciliationFailurePoint
    ) async throws {
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let database = try makeCoreDatabase(
            path: directoryURL.appending(path: "application.sqlite").path
        )
        let storage = SourceWorkspaceStorage.fileBacked(
            rootURL: directoryURL.appending(path: "workspaces")
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let workspace = SourceWorkspace(
            organizerID: organizerID,
            repository: "tangled.org/example/testival-source",
            branch: "main"
        )
        let oldReference = WorkspaceBranchReference(
            branch: WorkspaceBranch(rawValue: "main"),
            revision: WorkspaceRevision(rawValue: "old-upstream-revision")
        )
        let newReference = WorkspaceBranchReference(
            branch: WorkspaceBranch(rawValue: "main"),
            revision: WorkspaceRevision(rawValue: "new-upstream-revision")
        )
        let checkoutCount = Mutex(0)
        var sourceControl = SourceControlClient.unimplemented
        sourceControl.open = { Repository(url: $0) }
        sourceControl.mergeFile = deterministicWorkspaceFileMerge
        let resolveRevision: SourceWorkspaceRevisionResolver = { _, _ in
            CommitID(rawValue: "synthetic-local-base")
        }

        try await withDependencies {
            $0.defaultDatabase = database
            $0.sourceControl = sourceControl
            $0.sourceWorkspaceReferenceMigrator = .openMusicEvent
            $0.sourceWorkspaceStorage = storage
            $0[SourcePatchGeneratorKey<SourceWorkspacePatchRequest>.self] = .openMusicEvent
            $0.sourceWorkspacePatchConversion = .live
            if failurePoint == .repository {
                $0[SourceWorkspaceRepositoryInstaller.self] =
                    SourceWorkspaceRepositoryInstaller { _, _ in
                        throw WorkspaceReconciliationInjectedFailure
                            .injectedRepositoryReplacement
                    }
            }
            $0[SourceWorkspaceCheckoutClient.self] = SourceWorkspaceCheckoutClient {
                _, _, outputURL in
                let index = checkoutCount.withLock {
                    $0 += 1
                    return $0
                }
                try FileManager.default.createDirectory(
                    at: outputURL.appending(path: ".git"),
                    withIntermediateDirectories: true
                )
                var checkedOutSource = try makeSourceRepository(eventName: "Original event")
                if index > 1 {
                    checkedOutSource.events[0].components.event.description =
                        "Published description"
                }
                _ = try OpenMusicEventSourceRepositoryFileTree().write(
                    checkedOutSource,
                    to: outputURL
                )
                return SourceWorkspaceCheckout(
                    repository: Repository(url: outputURL),
                    reference: index == 1 ? oldReference : newReference
                )
            }
        } operation: {
            let prepared = try await SourceWorkspacePreparationClient
                .openMusicEvent(resolveRevision: resolveRevision)
                .prepare(workspace)
            let localEventID = id("testival-source-testival-2026") as OME.ID<OME.Event>
            try await database.write { db in
                try CommsPost.insert {
                    CommsPost(
                        id: CommsPost.ID(
                            organizerID: organizerID,
                            eventID: localEventID,
                            channelID: id("general"),
                            postID: CommsPost.PostID("local-update")
                        ),
                        title: "My local update",
                        contents: "This must survive rollback.",
                        sortIndex: 0
                    )
                }
                .execute(db)
            }
            let patchBefore = try await SourcePatchGenerator<SourceWorkspacePatchRequest>
                .openMusicEvent
                .generate(SourceWorkspacePatchRequest(workspace: workspace))
            let persistence = WorkspacePublicationPersistence(database: database)
            let checkpointBefore = try await persistence.checkpoint(
                workspaceID: workspace.id,
                attempt: WorkspaceProposalAttempt(
                    changes: patchBefore,
                    details: WorkspaceProposalDetails(
                        title: try #require(
                            WorkspaceProposalTitle("Preserve this checkpoint")
                        )
                    ),
                    target: oldReference
                )
            )

            let failureTrigger = """
                CREATE TRIGGER "fail_reconciliation_event_delete"
                BEFORE DELETE ON "app.openmusicevent.event"
                BEGIN
                  SELECT RAISE(ABORT, 'injected reconciliation failure');
                END
                """
            switch failurePoint {
            case .referenceDatabase:
                try await prepared.source.referenceDatabase.database.write { db in
                    try db.execute(sql: failureTrigger)
                }

            case .writableDatabase:
                try await database.write { db in
                    try db.execute(sql: failureTrigger)
                }

            case .repository:
                break
            }

            do {
                _ = try await WorkspaceReferenceUpdateClient
                    .openMusicEvent(resolveRevision: resolveRevision)
                    .reconcile(
                        prepared.source,
                        workspace.id,
                        prepared.baseline
                    )
                Issue.record("Expected the \(failurePoint) commit to fail")
            } catch {
                #expect(String(describing: error).contains("injected"))
            }

            expectNoDifference(checkoutCount.withLock { $0 }, 2)
            let patchAfter = try await SourcePatchGenerator<SourceWorkspacePatchRequest>
                .openMusicEvent
                .generate(SourceWorkspacePatchRequest(workspace: workspace))
            expectNoDifference(patchAfter, patchBefore)
            expectNoDifference(try persistence.checkpoint(workspace.id), checkpointBefore)
            let working = try await database.read { db in
                (
                    try OME.Event.find(
                        eventID("testival-source-testival-2026", organizerID: organizerID)
                    )
                    .fetchOne(db)?.description,
                    try CommsPost.fetchCount(db),
                    try SourceWorkspaceInstallationRecord
                        .find(workspace.id)
                        .fetchOne(db)?.revision,
                    try SourceWorkspaceSelectionRecord
                        .find(workspace.id)
                        .fetchOne(db)?.revision
                )
            }
            expectNoDifference(working.0, "A small fixture event.")
            expectNoDifference(working.1, 1)
            expectNoDifference(working.2, oldReference.revision.rawValue)
            expectNoDifference(working.3, oldReference.revision.rawValue)
            let reference = try prepared.source.referenceDatabase.read { db in
                (
                    try OME.Event.find(
                        eventID("testival-source-testival-2026", organizerID: organizerID)
                    )
                    .fetchOne(db)?.description,
                    try CommsPost.fetchCount(db),
                    try SourceWorkspaceReferenceRecord
                        .find(workspace.id)
                        .fetchOne(db)?.revision
                )
            }
            expectNoDifference(reference.0, "A small fixture event.")
            expectNoDifference(reference.1, 0)
            expectNoDifference(reference.2, oldReference.revision.rawValue)
            let installedSource = try OpenMusicEventSourceRepositoryFileTree()
                .read(from: prepared.source.repositoryURL)
                .output
                .requiredValue
            expectNoDifference(
                installedSource.events.first?.components.event.description,
                "A small fixture event."
            )
            #expect(installedSource.events.first?.components.communicationPosts == nil)
        }
    }

    @Test
    func `a local edit made during reconciliation is preserved and retried`() async throws {
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let database = try makeCoreDatabase(
            path: directoryURL.appending(path: "application.sqlite").path
        )
        let storage = SourceWorkspaceStorage.fileBacked(
            rootURL: directoryURL.appending(path: "workspaces")
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let workspace = SourceWorkspace(
            organizerID: organizerID,
            repository: "tangled.org/example/testival-source",
            branch: "main"
        )
        let oldReference = WorkspaceBranchReference(
            branch: WorkspaceBranch(rawValue: "main"),
            revision: WorkspaceRevision(rawValue: "old-upstream-revision")
        )
        let newReference = WorkspaceBranchReference(
            branch: WorkspaceBranch(rawValue: "main"),
            revision: WorkspaceRevision(rawValue: "new-upstream-revision")
        )
        let checkoutCount = Mutex(0)
        let mergeCount = Mutex(0)
        let eventID = eventID("testival-source-testival-2026", organizerID: organizerID)
        var sourceControl = SourceControlClient.unimplemented
        sourceControl.open = { Repository(url: $0) }
        sourceControl.mergeFile = { request in
            let call = mergeCount.withLock {
                $0 += 1
                return $0
            }
            if call == 1 {
                try await database.write { db in
                    try OME.Event.find(eventID).update {
                        $0.name = "Local edit made during checkout"
                    }
                    .execute(db)
                }
            }
            return try await deterministicWorkspaceFileMerge(request)
        }
        let resolveRevision: SourceWorkspaceRevisionResolver = { _, _ in
            CommitID(rawValue: "synthetic-local-base")
        }

        try await withDependencies {
            $0.defaultDatabase = database
            $0.sourceControl = sourceControl
            $0.sourceWorkspaceReferenceMigrator = .openMusicEvent
            $0.sourceWorkspaceStorage = storage
            $0[SourcePatchGeneratorKey<SourceWorkspacePatchRequest>.self] = .openMusicEvent
            $0.sourceWorkspacePatchConversion = .live
            $0[SourceWorkspaceCheckoutClient.self] = SourceWorkspaceCheckoutClient {
                _, _, outputURL in
                let index = checkoutCount.withLock {
                    $0 += 1
                    return $0
                }
                try FileManager.default.createDirectory(
                    at: outputURL.appending(path: ".git"),
                    withIntermediateDirectories: true
                )
                _ = try OpenMusicEventSourceRepositoryFileTree().write(
                    makeSourceRepository(eventName: "Published event"),
                    to: outputURL
                )
                return SourceWorkspaceCheckout(
                    repository: Repository(url: outputURL),
                    reference: index == 1 ? oldReference : newReference
                )
            }
        } operation: {
            let prepared = try await SourceWorkspacePreparationClient
                .openMusicEvent(resolveRevision: resolveRevision)
                .prepare(workspace)
            try await database.write { db in
                try OME.Event.find(eventID).update {
                    $0.name = "Local edit before checkout"
                }
                .execute(db)
            }

            let result = try await WorkspaceReferenceUpdateClient
                .openMusicEvent(resolveRevision: resolveRevision)
                .reconcile(
                    prepared.source,
                    workspace.id,
                    prepared.baseline
                )
            guard case let .current(reconciled) = result else {
                Issue.record("Expected the newer local edit to reconcile on retry")
                return
            }

            expectNoDifference(reconciled.baseline, newReference)
            expectNoDifference(checkoutCount.withLock { $0 }, 3)
            expectNoDifference(mergeCount.withLock { $0 }, 2)
            let persisted = try await database.read { db in
                (
                    eventName: try OME.Event.find(eventID).fetchOne(db)?.name,
                    revision: try SourceWorkspaceInstallationRecord
                        .find(workspace.id)
                        .fetchOne(db)?.revision
                )
            }
            expectNoDifference(
                persisted.eventName,
                "Local edit made during checkout"
            )
            expectNoDifference(
                persisted.revision,
                Optional(newReference.revision.rawValue)
            )
            expectNoDifference(
                try prepared.source.referenceDatabase.read { db in
                    try SourceWorkspaceReferenceRecord
                        .find(workspace.id)
                        .fetchOne(db)?.revision
                },
                Optional(newReference.revision.rawValue)
            )
            let patch = try await SourcePatchGenerator<SourceWorkspacePatchRequest>
                .openMusicEvent
                .generate(SourceWorkspacePatchRequest(workspace: workspace))
            expectNoDifference(patch.fileChanges.map(\.path), ["events/testival-2026/event.yml"])
            #expect(
                String(data: try #require(patch.fileChanges.first?.newContents), encoding: .utf8)?
                    .contains("Local edit made during checkout") == true
            )
        }
    }

    @Test
    func `overlapping published and local event edits report conflict without changing persistence`() async throws {
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let database = try makeCoreDatabase(
            path: directoryURL.appending(path: "application.sqlite").path
        )
        let storage = SourceWorkspaceStorage.fileBacked(
            rootURL: directoryURL.appending(path: "workspaces")
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let workspace = SourceWorkspace(
            organizerID: organizerID,
            repository: "tangled.org/example/testival-source",
            branch: "main"
        )
        let oldReference = WorkspaceBranchReference(
            branch: WorkspaceBranch(rawValue: "main"),
            revision: WorkspaceRevision(rawValue: "old-upstream-revision")
        )
        let newReference = WorkspaceBranchReference(
            branch: WorkspaceBranch(rawValue: "main"),
            revision: WorkspaceRevision(rawValue: "new-upstream-revision")
        )
        let checkoutCount = Mutex(0)
        var sourceControl = SourceControlClient.unimplemented
        sourceControl.open = { Repository(url: $0) }
        sourceControl.mergeFile = { request in
            if request.path.rawValue.hasSuffix("/event.yml") {
                return .conflicted
            }
            return try await deterministicWorkspaceFileMerge(request)
        }
        let resolveRevision: SourceWorkspaceRevisionResolver = { _, _ in
            CommitID(rawValue: "synthetic-local-base")
        }

        try await withDependencies {
            $0.defaultDatabase = database
            $0.sourceControl = sourceControl
            $0.sourceWorkspaceReferenceMigrator = .openMusicEvent
            $0.sourceWorkspaceStorage = storage
            $0[SourcePatchGeneratorKey<SourceWorkspacePatchRequest>.self] = .openMusicEvent
            $0.sourceWorkspacePatchConversion = .live
            $0[SourceWorkspaceCheckoutClient.self] = SourceWorkspaceCheckoutClient {
                _, _, outputURL in
                let index = checkoutCount.withLock {
                    $0 += 1
                    return $0
                }
                try FileManager.default.createDirectory(
                    at: outputURL.appending(path: ".git"),
                    withIntermediateDirectories: true
                )
                _ = try OpenMusicEventSourceRepositoryFileTree().write(
                    makeSourceRepository(
                        eventName: index == 1 ? "Original event" : "Published event"
                    ),
                    to: outputURL
                )
                return SourceWorkspaceCheckout(
                    repository: Repository(url: outputURL),
                    reference: index == 1 ? oldReference : newReference
                )
            }
        } operation: {
            let prepared = try await SourceWorkspacePreparationClient
                .openMusicEvent(resolveRevision: resolveRevision)
                .prepare(workspace)
            let eventID = eventID("testival-source-testival-2026", organizerID: organizerID)
            try await database.write { db in
                try OME.Event.find(eventID).update { $0.name = "My local event" }.execute(db)
            }
            let patchBefore = try await SourcePatchGenerator<SourceWorkspacePatchRequest>
                .openMusicEvent
                .generate(SourceWorkspacePatchRequest(workspace: workspace))

            let result = try await WorkspaceReferenceUpdateClient
                .openMusicEvent(resolveRevision: resolveRevision)
                .reconcile(
                    prepared.source,
                    workspace.id,
                    prepared.baseline
                )
            guard case let .conflicted(conflict) = result else {
                Issue.record("Expected overlapping event edits to conflict")
                return
            }
            expectNoDifference(conflict.baseline, oldReference)
            expectNoDifference(conflict.upstream, newReference)
            expectNoDifference(
                conflict.conflictingPaths.map(\.rawValue),
                ["events/testival-2026/event.yml"]
            )

            let persisted = try await database.read { db in
                (
                    eventName: try OME.Event.find(eventID).fetchOne(db)?.name,
                    installation: try SourceWorkspaceInstallationRecord
                        .find(workspace.id)
                        .fetchOne(db)?.revision,
                    selection: try SourceWorkspaceSelectionRecord
                        .find(workspace.id)
                        .fetchOne(db)
                )
            }
            expectNoDifference(persisted.eventName, "My local event")
            expectNoDifference(persisted.installation, Optional(oldReference.revision.rawValue))
            expectNoDifference(
                persisted.selection,
                SourceWorkspaceSelectionRecord(
                    id: workspace.id,
                    branch: oldReference.branch.rawValue,
                    revision: oldReference.revision.rawValue
                )
            )
            expectNoDifference(
                try prepared.source.referenceDatabase.read { db in
                    try SourceWorkspaceReferenceRecord.find(workspace.id).fetchOne(db)?.revision
                },
                Optional(oldReference.revision.rawValue)
            )
            expectNoDifference(
                try OpenMusicEventSourceRepositoryFileTree()
                    .read(from: prepared.source.repositoryURL)
                    .output
                    .requiredValue
                    .events.first?.components.event.name,
                "Original event"
            )
            let patchAfter = try await SourcePatchGenerator<SourceWorkspacePatchRequest>
                .openMusicEvent
                .generate(SourceWorkspacePatchRequest(workspace: workspace))
            expectNoDifference(patchAfter, patchBefore)
        }
    }

    @Test
    func `discarding local changes installs the latest published source coherently`() async throws {
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let database = try makeCoreDatabase(
            path: directoryURL.appending(path: "application.sqlite").path
        )
        let storage = SourceWorkspaceStorage.fileBacked(
            rootURL: directoryURL.appending(path: "workspaces")
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let workspace = SourceWorkspace(
            organizerID: organizerID,
            repository: "tangled.org/example/testival-source",
            branch: "main"
        )
        let oldReference = WorkspaceBranchReference(
            branch: WorkspaceBranch(rawValue: "main"),
            revision: WorkspaceRevision(rawValue: "old-upstream-revision")
        )
        let newReference = WorkspaceBranchReference(
            branch: WorkspaceBranch(rawValue: "main"),
            revision: WorkspaceRevision(rawValue: "new-upstream-revision")
        )
        let checkoutCount = Mutex(0)
        var sourceControl = SourceControlClient.unimplemented
        sourceControl.open = { Repository(url: $0) }
        let resolveRevision: SourceWorkspaceRevisionResolver = { _, _ in
            CommitID(rawValue: "synthetic-local-base")
        }

        try await withDependencies {
            $0.defaultDatabase = database
            $0.sourceControl = sourceControl
            $0.sourceWorkspaceReferenceMigrator = .openMusicEvent
            $0.sourceWorkspaceStorage = storage
            $0[SourcePatchGeneratorKey<SourceWorkspacePatchRequest>.self] = .openMusicEvent
            $0.sourceWorkspacePatchConversion = .live
            $0[SourceWorkspaceCheckoutClient.self] = SourceWorkspaceCheckoutClient {
                _, _, outputURL in
                let index = checkoutCount.withLock {
                    $0 += 1
                    return $0
                }
                try FileManager.default.createDirectory(
                    at: outputURL.appending(path: ".git"),
                    withIntermediateDirectories: true
                )
                _ = try OpenMusicEventSourceRepositoryFileTree().write(
                    makeSourceRepository(
                        eventName: index == 1 ? "Original event" : "Published event"
                    ),
                    to: outputURL
                )
                return SourceWorkspaceCheckout(
                    repository: Repository(url: outputURL),
                    reference: index == 1 ? oldReference : newReference
                )
            }
        } operation: {
            let prepared = try await SourceWorkspacePreparationClient
                .openMusicEvent(resolveRevision: resolveRevision)
                .prepare(workspace)
            let eventID = eventID("testival-source-testival-2026", organizerID: organizerID)
            try await database.write { db in
                try OME.Event.find(eventID).update { $0.name = "My local event" }.execute(db)
            }
            #expect(
                try await SourcePatchGenerator<SourceWorkspacePatchRequest>
                    .openMusicEvent
                    .generate(SourceWorkspacePatchRequest(workspace: workspace))
                    .isEmpty == false
            )

            let updated = try await WorkspaceReferenceUpdateClient
                .openMusicEvent(resolveRevision: resolveRevision)
                .discardChangesAndUpdate(
                    prepared.source,
                    workspace.id,
                    prepared.baseline
                )

            expectNoDifference(updated.baseline, newReference)
            expectNoDifference(checkoutCount.withLock { $0 }, 2)
            let persisted = try await database.read { db in
                (
                    eventName: try OME.Event.find(eventID).fetchOne(db)?.name,
                    installation: try SourceWorkspaceInstallationRecord
                        .find(workspace.id)
                        .fetchOne(db),
                    selection: try SourceWorkspaceSelectionRecord
                        .find(workspace.id)
                        .fetchOne(db)
                )
            }
            expectNoDifference(persisted.eventName, "Published event")
            expectNoDifference(
                persisted.installation?.revision,
                newReference.revision.rawValue
            )
            expectNoDifference(
                persisted.selection,
                SourceWorkspaceSelectionRecord(
                    id: workspace.id,
                    branch: newReference.branch.rawValue,
                    revision: newReference.revision.rawValue
                )
            )
            let referenceEventName = try prepared.source.referenceDatabase.read { db in
                try OME.Event.find(eventID).fetchOne(db)?.name
            }
            let referenceRevision = try prepared.source.referenceDatabase.read { db in
                try SourceWorkspaceReferenceRecord
                    .find(workspace.id)
                    .fetchOne(db)?.revision
            }
            expectNoDifference(referenceEventName, "Published event")
            expectNoDifference(referenceRevision, newReference.revision.rawValue)
            expectNoDifference(
                try OpenMusicEventSourceRepositoryFileTree()
                    .read(from: prepared.source.repositoryURL)
                    .output
                    .requiredValue
                    .events.first?.components.event.name,
                "Published event"
            )
            #expect(
                try await SourcePatchGenerator<SourceWorkspacePatchRequest>
                    .openMusicEvent
                    .generate(SourceWorkspacePatchRequest(workspace: workspace))
                    .isEmpty
            )
        }
    }

    @Test
    func `a branch selection installs its resolved immutable reference`() async throws {
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let database = try makeCoreDatabase(
            path: directoryURL.appending(path: "application.sqlite").path
        )
        let storage = SourceWorkspaceStorage.fileBacked(
            rootURL: directoryURL.appending(path: "workspaces")
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let workspace = SourceWorkspace(
            organizerID: organizerID,
            repository: "tangled.org/example/testival-source",
            branch: "main"
        )
        let reference = WorkspaceBranchReference(
            branch: WorkspaceBranch(rawValue: "main"),
            revision: WorkspaceRevision(rawValue: "upstream-revision")
        )
        let checkoutCount = Mutex(0)
        var sourceControl = SourceControlClient.unimplemented
        sourceControl.open = { Repository(url: $0) }
        let resolveRevision: SourceWorkspaceRevisionResolver = { _, _ in
            CommitID(rawValue: "synthetic-local-base")
        }

        try await withDependencies {
            $0.defaultDatabase = database
            $0.sourceControl = sourceControl
            $0.sourceWorkspaceReferenceMigrator = .openMusicEvent
            $0.sourceWorkspaceStorage = storage
            $0[SourcePatchGeneratorKey<SourceWorkspacePatchRequest>.self] =
                SourcePatchGenerator { _ in SourcePatch() }
            $0[SourceWorkspaceCheckoutClient.self] = SourceWorkspaceCheckoutClient {
                _, branch, outputURL in
                checkoutCount.withLock { $0 += 1 }
                try FileManager.default.createDirectory(
                    at: outputURL.appending(path: ".git"),
                    withIntermediateDirectories: true
                )
                _ = try OpenMusicEventSourceRepositoryFileTree().write(
                    makeSourceRepository(),
                    to: outputURL
                )
                return SourceWorkspaceCheckout(
                    repository: Repository(url: outputURL),
                    reference: WorkspaceBranchReference(
                        branch: branch ?? reference.branch,
                        revision: reference.revision
                    )
                )
            }
        } operation: {
            let prepared = try await SourceWorkspacePreparationClient
                .openMusicEvent(resolveRevision: resolveRevision)
                .prepare(workspace)
            let selected = try await WorkspaceReferenceUpdateClient
                .openMusicEvent(resolveRevision: resolveRevision)
                .select(
                    prepared.source,
                    workspace.id,
                    WorkspaceBranch(rawValue: "preview")
                )
            expectNoDifference(
                selected,
                WorkspaceBranchReference(
                    branch: WorkspaceBranch(rawValue: "preview"),
                    revision: WorkspaceRevision(rawValue: "upstream-revision")
                )
            )
            expectNoDifference(checkoutCount.withLock { $0 }, 2)
        }
    }

    @Test
    func `a changed default branch leaves the installed workspace untouched`() async throws {
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let database = try makeCoreDatabase(
            path: directoryURL.appending(path: "application.sqlite").path
        )
        let storage = SourceWorkspaceStorage.fileBacked(
            rootURL: directoryURL.appending(path: "workspaces")
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let workspace = SourceWorkspace(
            organizerID: organizerID,
            repository: "tangled.org/example/testival-source",
            branch: "main"
        )
        let oldReference = WorkspaceBranchReference(
            branch: WorkspaceBranch(rawValue: "main"),
            revision: WorkspaceRevision(rawValue: "old-upstream-revision")
        )
        let changedDefault = WorkspaceBranchReference(
            branch: WorkspaceBranch(rawValue: "trunk"),
            revision: WorkspaceRevision(rawValue: "new-upstream-revision")
        )
        let checkoutCount = Mutex(0)
        var sourceControl = SourceControlClient.unimplemented
        sourceControl.open = { Repository(url: $0) }
        let resolveRevision: SourceWorkspaceRevisionResolver = { _, _ in
            CommitID(rawValue: "synthetic-local-base")
        }

        try await withDependencies {
            $0.defaultDatabase = database
            $0.sourceControl = sourceControl
            $0.sourceWorkspaceReferenceMigrator = .openMusicEvent
            $0.sourceWorkspaceStorage = storage
            $0[SourcePatchGeneratorKey<SourceWorkspacePatchRequest>.self] =
                SourcePatchGenerator { _ in SourcePatch() }
            $0[SourceWorkspaceCheckoutClient.self] = SourceWorkspaceCheckoutClient {
                _, _, outputURL in
                let index = checkoutCount.withLock {
                    $0 += 1
                    return $0
                }
                try FileManager.default.createDirectory(
                    at: outputURL.appending(path: ".git"),
                    withIntermediateDirectories: true
                )
                _ = try OpenMusicEventSourceRepositoryFileTree().write(
                    makeSourceRepository(eventName: index == 1 ? "Installed" : "Rejected"),
                    to: outputURL
                )
                return SourceWorkspaceCheckout(
                    repository: Repository(url: outputURL),
                    reference: index == 1 ? oldReference : changedDefault
                )
            }
        } operation: {
            let prepared = try await SourceWorkspacePreparationClient
                .openMusicEvent(resolveRevision: resolveRevision)
                .prepare(workspace)
            await #expect(
                throws: SourceWorkspaceDatabaseError.contextSelectionRevisionChanged(
                    expected: "main",
                    observed: "trunk"
                )
            ) {
                _ = try await WorkspaceReferenceUpdateClient
                    .openMusicEvent(resolveRevision: resolveRevision)
                    .reconcile(
                        prepared.source,
                        workspace.id,
                        prepared.baseline
                    )
            }

            let installedSource = try OpenMusicEventSourceRepositoryFileTree()
                .read(from: prepared.source.repositoryURL)
                .output
                .requiredValue
            expectNoDifference(installedSource.events.first?.components.event.name, "Installed")
            let persisted = try await (
                prepared.source.referenceDatabase.read { db in
                    try SourceWorkspaceReferenceRecord.find(workspace.id).fetchOne(db)?.revision
                },
                database.read { db in
                    (
                        installation: try SourceWorkspaceInstallationRecord
                            .find(workspace.id)
                            .fetchOne(db)?.revision,
                        selection: try SourceWorkspaceSelectionRecord
                            .find(workspace.id)
                            .fetchOne(db)
                    )
                }
            )
            expectNoDifference(persisted.0, Optional(oldReference.revision.rawValue))
            expectNoDifference(persisted.1.installation, Optional(oldReference.revision.rawValue))
            expectNoDifference(
                persisted.1.selection,
                SourceWorkspaceSelectionRecord(
                    id: workspace.id,
                    branch: oldReference.branch.rawValue,
                    revision: oldReference.revision.rawValue
                )
            )
            let temporaryRepositories = try FileManager.default.contentsOfDirectory(
                at: prepared.source.repositoryURL.deletingLastPathComponent(),
                includingPropertiesForKeys: nil
            )
            .filter {
                $0.lastPathComponent.hasPrefix("repository-reconcile-")
                    || $0.lastPathComponent.hasPrefix("repository-backup-")
            }
            expectNoDifference(temporaryRepositories, [])
        }
    }

    @Test
    func materializesFileBackedRequiredStageLogosOnInsert() async throws {
        let repositoryURL = try temporaryDirectoryURL()
        let eventDirectoryURL = repositoryURL
            .appending(path: "events", directoryHint: .isDirectory)
            .appending(path: "testival-2026", directoryHint: .isDirectory)
        let imagesDirectoryURL = eventDirectoryURL.appending(path: "images", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: imagesDirectoryURL, withIntermediateDirectories: true)

        let sourceFileURL = imagesDirectoryURL.appending(path: "meadow-logo.png")
        let sourceData = Data("stage-logo".utf8)
        try sourceData.write(to: sourceFileURL)

        let source = try makeSourceRepository(
            stageImages: [
                SourceImageAsset(
                    source: .file("images/meadow-logo.png"),
                    role: .logo,
                    renderKind: .transparent,
                    materializationPolicy: .prefetchOnOpen
                )
            ]
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let insertion = try OME.SourceDatabaseInsertion(
            .init(
                source: source,
                organizerID: organizerID,
                sourceRootURL: repositoryURL
            )
        )
        let database = try makeCoreDatabase()
        let cacheDirectoryURL = try temporaryDirectoryURL()

        try await withDependencies {
            $0.localImageFileStore = testLocalImageFileStore(directory: cacheDirectoryURL)
        } operation: {
            try await insertion.insert(into: database)
        }

        let stage = try await database.read { db in
            try OME.Stage.fetchOne(db)
        }
        let storedBlob = try await database.read { db in
            try LocalImageBlob.fetchOne(db)
        }

        let stageLogoURL = try #require(stage?.images?.first?.url)
        #expect(stageLogoURL.isFileURL)
        let blob = try #require(storedBlob)
        #expect(blob.role == OME.ImageAsset.Role.logo)
        #expect(blob.renderKind == OME.ImageAsset.RenderKind.transparent)
        #expect(blob.sourceURL == sourceFileURL)
        expectNoDifference(blob.data, sourceData)
    }

    @Test
    func materializesFileBackedCalendarImagesOnInsert() async throws {
        let repositoryURL = try temporaryDirectoryURL()
        let imagesDirectoryURL = repositoryURL.appending(path: "images", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: imagesDirectoryURL, withIntermediateDirectories: true)

        let sourceFileURL = imagesDirectoryURL.appending(path: "calendar-hero.png")
        let sourceData = Data("calendar-hero".utf8)
        try sourceData.write(to: sourceFileURL)

        let source = try makeSourceRepository(
            calendar: CalendarDTO(
                name: "Testival Calendar",
                images: [
                    SourceImageAsset(
                        source: .file("images/calendar-hero.png"),
                        role: .hero,
                        renderKind: .fullImage,
                        materializationPolicy: .prefetchOnOpen
                    )
                ]
            )
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let insertion = try OME.SourceDatabaseInsertion(
            .init(
                source: source,
                organizerID: organizerID,
                sourceRootURL: repositoryURL
            )
        )
        let database = try makeCoreDatabase()
        let cacheDirectoryURL = try temporaryDirectoryURL()

        try await withDependencies {
            $0.localImageFileStore = testLocalImageFileStore(directory: cacheDirectoryURL)
        } operation: {
            try await insertion.insert(into: database)
        }

        let calendar = try await database.read { db in
            try OME.Calendar.fetchOne(db)
        }
        let storedBlob = try await database.read { db in
            try LocalImageBlob.fetchOne(db)
        }

        let heroURL = try #require(calendar?.images?.imageAsset(role: .hero)?.url)
        #expect(heroURL.isFileURL)
        let blob = try #require(storedBlob)
        #expect(blob.organizerID == organizerID)
        #expect(blob.eventID == nil)
        #expect(blob.parentKind == .calendar)
        #expect(blob.parentLocalID == OME.Calendar.defaultID.rawValue.rawValue)
        #expect(blob.role == OME.ImageAsset.Role.hero)
        #expect(blob.renderKind == OME.ImageAsset.RenderKind.fullImage)
        #expect(blob.sourceURL == sourceFileURL)
        expectNoDifference(blob.data, sourceData)
    }

    @Test
    func leavesRemoteCalendarImagesUnfetchedOnInsert() async throws {
        let remoteURL = try #require(URL(string: "https://example.com/calendar-hero.png"))
        let source = try makeSourceRepository(
            calendar: CalendarDTO(
                name: "Testival Calendar",
                images: [
                    SourceImageAsset(
                        source: .url(remoteURL),
                        role: .hero,
                        renderKind: .fullImage,
                        materializationPolicy: .prefetchOnOpen
                    )
                ]
            )
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let insertion = try OME.SourceDatabaseInsertion(
            .init(
                source: source,
                organizerID: organizerID
            )
        )
        let database = try makeCoreDatabase()

        try await insertion.insert(into: database)

        let calendar = try await database.read { db in
            try OME.Calendar.fetchOne(db)
        }
        let blobs = try await database.read { db in
            try LocalImageBlob.fetchAll(db)
        }

        #expect(calendar?.images?.imageAsset(role: .hero)?.url == remoteURL)
        expectNoDifference(blobs, [])
    }

    @Test
    func restoresMaterializedStageLogosFromBlobWhenLocalFileIsMissingOnOpen() async throws {
        let repositoryURL = try temporaryDirectoryURL()
        let eventDirectoryURL = repositoryURL
            .appending(path: "events", directoryHint: .isDirectory)
            .appending(path: "testival-2026", directoryHint: .isDirectory)
        let imagesDirectoryURL = eventDirectoryURL.appending(path: "images", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: imagesDirectoryURL, withIntermediateDirectories: true)

        let sourceFileURL = imagesDirectoryURL.appending(path: "meadow-logo.png")
        let sourceData = Data("stage-logo".utf8)
        try sourceData.write(to: sourceFileURL)

        let source = try makeSourceRepository(
            stageImages: [
                SourceImageAsset(
                    source: .file("images/meadow-logo.png"),
                    role: .logo,
                    renderKind: .transparent,
                    materializationPolicy: .prefetchOnOpen
                )
            ]
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let openedEventID = eventID("testival-2026", organizerID: organizerID)
        let insertion = try OME.SourceDatabaseInsertion(
            .init(
                source: source,
                organizerID: organizerID,
                sourceRootURL: repositoryURL
            )
        )
        let database = try makeCoreDatabase()
        let cacheDirectoryURL = try temporaryDirectoryURL()

        try await withDependencies {
            $0.localImageFileStore = testLocalImageFileStore(directory: cacheDirectoryURL)
        } operation: {
            try await insertion.insert(into: database)
        }

        let insertedStage = try await database.read { db in
            try OME.Stage.fetchOne(db)
        }
        let insertedLogoURL = try #require(insertedStage?.images?.first?.url)
        try FileManager.default.removeItem(at: insertedLogoURL)

        let recoveryDirectoryURL = try temporaryDirectoryURL()
        try await withDependencies {
            $0.defaultDatabase = database
            $0.eventImagePrefetch = .live
            $0.localImageFileStore = testLocalImageFileStore(directory: recoveryDirectoryURL)
            $0.httpClient = .testClient { _, path, _ in
                Issue.record("Did not expect HTTP request while restoring local image: \(path)")
                return Data()
            }
        } operation: {
            @Dependency(\.eventImagePrefetch) var eventImagePrefetch
            try await eventImagePrefetch.prefetchAssetsOnOpen(openedEventID)
        }

        let restoredStage = try await database.read { db in
            try OME.Stage.fetchOne(db)
        }
        let restoredLogoURL = try #require(restoredStage?.images?.first?.url)
        let blobs = try await database.read { db in
            try LocalImageBlob.fetchAll(db)
        }

        #expect(restoredLogoURL.isFileURL)
        #expect(restoredLogoURL != insertedLogoURL)
        #expect(FileManager.default.fileExists(atPath: restoredLogoURL.path))
        expectNoDifference(try Data(contentsOf: restoredLogoURL), sourceData)
        #expect(blobs.count == 1)
    }

    @Test
    func leavesRemoteImagesUnfetchedUntilEventOpen() async throws {
        let eventHeroURL = try #require(URL(string: "https://example.com/event-hero.jpg"))
        let contributorPhotoURL = try #require(URL(string: "https://example.com/artist-one.jpg"))
        let source = try makeSourceRepository(
            eventImages: [
                SourceImageAsset(
                    source: .url(eventHeroURL),
                    role: .hero,
                    renderKind: .fullImage,
                    materializationPolicy: .prefetchOnOpen
                )
            ],
            contributorImages: [
                SourceImageAsset(
                    source: .url(contributorPhotoURL),
                    role: .photo,
                    renderKind: .fullImage,
                    materializationPolicy: .lazy
                )
            ]
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let insertion = try OME.SourceDatabaseInsertion(
            .init(source: source, organizerID: organizerID)
        )
        let openedEventID = eventID("testival-2026", organizerID: organizerID)
        let database = try makeCoreDatabase()
        let remoteData = Data("remote-hero".utf8)

        try await withDependencies {
            $0.httpClient = .testClient { _, path, _ in
                Issue.record("Did not expect HTTP request during source insertion: \(path)")
                return Data()
            }
        } operation: {
            try await insertion.insert(into: database)
        }

        let event = try await database.read { db in
            try OME.Event.fetchOne(db)
        }
        let contributor = try await database.read { db in
            try OME.Contributor.fetchOne(db)
        }
        let blobs = try await database.read { db in
            try LocalImageBlob.fetchAll(db)
        }

        #expect(event?.images?.first?.url == eventHeroURL)
        #expect(contributor?.images?.first?.url == contributorPhotoURL)
        #expect(blobs.isEmpty)

        let cacheDirectoryURL = try temporaryDirectoryURL()
        try await withDependencies {
            $0.defaultDatabase = database
            $0.eventImagePrefetch = .live
            $0.localImageFileStore = testLocalImageFileStore(directory: cacheDirectoryURL)
            $0.httpClient = .testClient { _, path, _ in
                #expect(path == "/event-hero.jpg")
                return remoteData
            }
        } operation: {
            @Dependency(\.eventImagePrefetch) var eventImagePrefetch
            try await eventImagePrefetch.prefetchAssetsOnOpen(openedEventID)
        }

        let prefetchedEvent = try await database.read { db in
            try OME.Event.fetchOne(db)
        }
        let prefetchedContributor = try await database.read { db in
            try OME.Contributor.fetchOne(db)
        }
        let prefetchedBlobs = try await database.read { db in
            try LocalImageBlob.fetchAll(db)
        }

        let prefetchedHeroImage = try #require(prefetchedEvent?.images?.first)
        let prefetchedHeroURL = try #require(prefetchedHeroImage.url)
        #expect(prefetchedHeroURL == eventHeroURL)
        #expect(prefetchedContributor?.images?.first?.url == contributorPhotoURL)
        #expect(prefetchedBlobs.count == 1)
        let blob = try #require(prefetchedBlobs.first)
        #expect(blob.sourceURL == eventHeroURL)
        let cachedHeroURL = testLocalImageFileURL(
            directory: cacheDirectoryURL,
            assetKey: try #require(prefetchedHeroImage.assetKey)
        )
        #expect(FileManager.default.fileExists(atPath: cachedHeroURL.path))
        expectNoDifference(try Data(contentsOf: cachedHeroURL), remoteData)
        expectNoDifference(blob.data, remoteData)
    }

    @Test
    func prefetchesRemoteStageLogosWithoutMutatingStageSource() async throws {
        let remoteLogoURL = try #require(URL(string: "https://example.com/meadow-logo.png"))
        let source = try makeSourceRepository(
            stageImages: [
                SourceImageAsset(
                    source: .url(remoteLogoURL),
                    role: .logo,
                    renderKind: .transparent,
                    materializationPolicy: .prefetchOnOpen
                )
            ]
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let openedEventID = eventID("testival-2026", organizerID: organizerID)
        let insertion = try OME.SourceDatabaseInsertion(
            .init(source: source, organizerID: organizerID)
        )
        let database = try makeCoreDatabase()
        try await insertion.insert(into: database)

        let insertedStage = try #require(await database.read { db in
            try OME.Stage.fetchOne(db)
        })
        let cacheDirectoryURL = try temporaryDirectoryURL()
        let remoteData = Data("remote-stage-logo".utf8)

        try await withDependencies {
            $0.defaultDatabase = database
            $0.eventImagePrefetch = .live
            $0.localImageFileStore = testLocalImageFileStore(directory: cacheDirectoryURL)
            $0.httpClient = .testClient { _, path, _ in
                #expect(path == "/meadow-logo.png")
                return remoteData
            }
        } operation: {
            @Dependency(\.eventImagePrefetch) var eventImagePrefetch
            try await eventImagePrefetch.prefetchAssetsOnOpen(openedEventID)
        }

        let prefetchedStage = try #require(await database.read { db in
            try OME.Stage.fetchOne(db)
        })
        let blobs = try await database.read { db in
            try LocalImageBlob.fetchAll(db)
        }

        expectNoDifference(prefetchedStage, insertedStage)
        let blob = try #require(blobs.first)
        #expect(blobs.count == 1)
        #expect(blob.parentKind == .stage)
        #expect(blob.parentLocalID == "meadow")
        #expect(blob.sourceURL == remoteLogoURL)
        expectNoDifference(blob.data, remoteData)
        let cachedLogoURL = testLocalImageFileURL(
            directory: cacheDirectoryURL,
            assetKey: try #require(insertedStage.images?.first?.assetKey)
        )
        #expect(FileManager.default.fileExists(atPath: cachedLogoURL.path))
        expectNoDifference(try Data(contentsOf: cachedLogoURL), remoteData)
    }

    @Test
    func displayCacheUsesCachedStageLogoWithoutMutatingStageSource() async throws {
        let remoteLogoURL = try #require(URL(string: "https://example.com/meadow-logo.png"))
        let source = try makeSourceRepository(
            stageImages: [
                SourceImageAsset(
                    source: .url(remoteLogoURL),
                    role: .logo,
                    renderKind: .transparent,
                    materializationPolicy: .prefetchOnOpen
                )
            ]
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let openedEventID = eventID("testival-2026", organizerID: organizerID)
        let insertion = try OME.SourceDatabaseInsertion(
            .init(source: source, organizerID: organizerID)
        )
        let database = try makeCoreDatabase()
        try await insertion.insert(into: database)

        let insertedStage = try #require(await database.read { db in
            try OME.Stage.fetchOne(db)
        })
        let originalLogo = try #require(insertedStage.images?.first)
        let cacheDirectoryURL = try temporaryDirectoryURL()
        let remoteData = Data("remote-stage-logo".utf8)

        try await withDependencies {
            $0.defaultDatabase = database
            $0.eventImagePrefetch = .live
            $0.localImageFileStore = testLocalImageFileStore(directory: cacheDirectoryURL)
            $0.httpClient = .testClient { _, _, _ in remoteData }
        } operation: {
            @Dependency(\.eventImagePrefetch) var eventImagePrefetch
            try await eventImagePrefetch.prefetchAssetsOnOpen(openedEventID)
        }

        let cachedLogoURL = testLocalImageFileURL(
            directory: cacheDirectoryURL,
            assetKey: try #require(originalLogo.assetKey)
        )
        try FileManager.default.removeItem(at: cachedLogoURL)

        let displayLogo = try await withDependencies {
            $0.defaultDatabase = database
            $0.localImageDisplayCache = .live
            $0.localImageFileStore = testLocalImageFileStore(directory: cacheDirectoryURL)
        } operation: {
            @Dependency(\.localImageDisplayCache) var localImageDisplayCache
            return try await localImageDisplayCache.resolve(
                originalLogo,
                LocalImageCacheContext(stageID: insertedStage.id)
            )
        }

        let displayLogoURL = try #require(displayLogo?.url)
        let stageAfterDisplayCache = try #require(await database.read { db in
            try OME.Stage.fetchOne(db)
        })

        #expect(displayLogoURL == cachedLogoURL)
        #expect(displayLogoURL.isFileURL)
        #expect(FileManager.default.fileExists(atPath: cachedLogoURL.path))
        expectNoDifference(try Data(contentsOf: cachedLogoURL), remoteData)
        expectNoDifference(stageAfterDisplayCache, insertedStage)
    }

    @Test
    func `display cache reuses the existing materialized file without rewriting it`() async throws {
        let remoteLogoURL = try #require(URL(string: "https://example.com/meadow-logo.png"))
        let source = try makeSourceRepository(
            stageImages: [
                SourceImageAsset(
                    source: .url(remoteLogoURL),
                    role: .logo,
                    renderKind: .transparent,
                    materializationPolicy: .prefetchOnOpen
                )
            ]
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let openedEventID = eventID("testival-2026", organizerID: organizerID)
        let insertion = try OME.SourceDatabaseInsertion(
            .init(source: source, organizerID: organizerID)
        )
        let database = try makeCoreDatabase()
        try await insertion.insert(into: database)

        let insertedStage = try #require(await database.read { db in
            try OME.Stage.fetchOne(db)
        })
        let originalLogo = try #require(insertedStage.images?.first)
        let cacheDirectoryURL = try temporaryDirectoryURL()
        let remoteData = Data("remote-stage-logo".utf8)

        // Opening the event materializes the logo once for later display.
        try await withDependencies {
            $0.defaultDatabase = database
            $0.eventImagePrefetch = .live
            $0.localImageFileStore = testLocalImageFileStore(directory: cacheDirectoryURL)
            $0.httpClient = .testClient { _, _, _ in remoteData }
        } operation: {
            @Dependency(\.eventImagePrefetch) var eventImagePrefetch
            try await eventImagePrefetch.prefetchAssetsOnOpen(openedEventID)
        }

        let fileWrites = Mutex(0)
        let recordingFileStore = LocalImageFileStoreClient(
            existingFileURL: { assetKey, _ in
                let fileURL = testLocalImageFileURL(
                    directory: cacheDirectoryURL,
                    assetKey: assetKey
                )
                return FileManager.default.fileExists(atPath: fileURL.path)
                    ? fileURL
                    : nil
            },
            write: { assetKey, data, _ in
                fileWrites.withLock { $0 += 1 }
                let fileURL = testLocalImageFileURL(
                    directory: cacheDirectoryURL,
                    assetKey: assetKey
                )
                try data.write(to: fileURL, options: .atomic)
                return fileURL
            }
        )

        // Repeated view mounts resolve the same image without copying its bytes again.
        let resolvedLogos = try await withDependencies {
            $0.defaultDatabase = database
            $0.localImageDisplayCache = .live
            $0.localImageFileStore = recordingFileStore
        } operation: {
            @Dependency(\.localImageDisplayCache) var localImageDisplayCache
            let context = LocalImageCacheContext(stageID: insertedStage.id)
            return try await (
                localImageDisplayCache.resolve(originalLogo, context),
                localImageDisplayCache.resolve(originalLogo, context)
            )
        }

        let firstURL = try #require(resolvedLogos.0?.url)
        let secondURL = try #require(resolvedLogos.1?.url)
        #expect(firstURL == secondURL)
        #expect(fileWrites.withLock { $0 } == 0)
        expectNoDifference(try Data(contentsOf: firstURL), remoteData)
    }

    @Test
    func `concurrent lazy requests share one download`() async throws {
        let contributorPhotoURL = try #require(URL(string: "https://example.com/artist-one.jpg"))
        let source = try makeSourceRepository(
            contributorImages: [
                SourceImageAsset(
                    source: .url(contributorPhotoURL),
                    role: .photo,
                    renderKind: .fullImage,
                    materializationPolicy: .lazy
                )
            ]
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let insertion = try OME.SourceDatabaseInsertion(
            .init(source: source, organizerID: organizerID)
        )
        let database = try makeCoreDatabase()
        try await insertion.insert(into: database)

        let contributor = try #require(await database.read { db in
            try OME.Contributor.fetchOne(db)
        })
        let originalImage = try #require(contributor.images?.first)
        let cacheDirectoryURL = try temporaryDirectoryURL()
        let remoteData = Data("lazy-contributor-photo".utf8)
        let requests = Mutex(0)

        // Two bubbles asking for the same image at once share one transport operation.
        let resolvedImages = try await withDependencies {
            $0.date.now = testImageCacheDate
            $0.defaultDatabase = database
            $0.lazyImageCache = .live
            $0.localImageFileStore = testLocalImageFileStore(directory: cacheDirectoryURL)
            $0.httpClient = .testClient { _, _, _ in
                requests.withLock { $0 += 1 }
                Thread.sleep(forTimeInterval: 0.05)
                return remoteData
            }
        } operation: {
            @Dependency(\.lazyImageCache) var lazyImageCache
            let context = LocalImageCacheContext(contributorID: contributor.id)
            let cache = lazyImageCache.cache
            async let first = cache(originalImage, context)
            async let second = cache(originalImage, context)
            return try await (first, second)
        }

        #expect(requests.withLock { $0 } == 1)
        #expect(resolvedImages.0.url == resolvedImages.1.url)
        let resolvedURL = try #require(resolvedImages.0.url)
        expectNoDifference(try Data(contentsOf: resolvedURL), remoteData)
    }

    @Test
    func `a changed source URL replaces bytes stored under the same asset key`() async throws {
        let originalPhotoURL = try #require(URL(string: "https://example.com/artist-one.jpg"))
        let replacementPhotoURL = try #require(URL(string: "https://example.com/artist-one-v2.jpg"))
        let source = try makeSourceRepository(
            contributorImages: [
                SourceImageAsset(
                    source: .url(originalPhotoURL),
                    role: .photo,
                    renderKind: .fullImage,
                    materializationPolicy: .lazy
                )
            ]
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let insertion = try OME.SourceDatabaseInsertion(
            .init(source: source, organizerID: organizerID)
        )
        let database = try makeCoreDatabase()
        try await insertion.insert(into: database)

        let contributor = try #require(await database.read { db in
            try OME.Contributor.fetchOne(db)
        })
        let originalImage = try #require(contributor.images?.first)
        let context = LocalImageCacheContext(contributorID: contributor.id)
        let cacheDirectoryURL = try temporaryDirectoryURL()
        let originalData = Data("lazy-contributor-photo".utf8)

        // The original source is materialized under the contributor's stable asset key.
        _ = try await withDependencies {
            $0.date.now = testImageCacheDate
            $0.defaultDatabase = database
            $0.lazyImageCache = .live
            $0.localImageFileStore = testLocalImageFileStore(directory: cacheDirectoryURL)
            $0.httpClient = .testClient { _, _, _ in originalData }
        } operation: {
            @Dependency(\.lazyImageCache) var lazyImageCache
            return try await lazyImageCache.cache(originalImage, context)
        }

        var replacementImage = originalImage
        replacementImage.source = .url(replacementPhotoURL)
        let replacementData = Data("replacement-contributor-photo".utf8)
        let replacementRequests = Mutex(0)

        // Changing the source URL invalidates the old blob even though its asset key is stable.
        let resolvedImage = try await withDependencies {
            $0.date.now = testImageCacheDate.addingTimeInterval(60)
            $0.defaultDatabase = database
            $0.lazyImageCache = .live
            $0.localImageFileStore = testLocalImageFileStore(directory: cacheDirectoryURL)
            $0.httpClient = .testClient { _, path, _ in
                replacementRequests.withLock { $0 += 1 }
                #expect(path == "/artist-one-v2.jpg")
                return replacementData
            }
        } operation: {
            @Dependency(\.lazyImageCache) var lazyImageCache
            return try await lazyImageCache.cache(replacementImage, context)
        }

        let blob = try #require(await database.read { db in
            try LocalImageBlob.fetchOne(db)
        })
        let resolvedURL = try #require(resolvedImage.url)
        #expect(replacementRequests.withLock { $0 } == 1)
        #expect(blob.sourceURL == replacementPhotoURL)
        expectNoDifference(blob.data, replacementData)
        expectNoDifference(try Data(contentsOf: resolvedURL), replacementData)
    }

    @Test
    func cachesLazyRemoteContributorImagesOnDemand() async throws {
        let contributorPhotoURL = try #require(URL(string: "https://example.com/artist-one.jpg"))
        let source = try makeSourceRepository(
            contributorImages: [
                SourceImageAsset(
                    source: .url(contributorPhotoURL),
                    role: .photo,
                    renderKind: .fullImage,
                    materializationPolicy: .lazy
                )
            ]
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let insertion = try OME.SourceDatabaseInsertion(
            .init(source: source, organizerID: organizerID)
        )
        let database = try makeCoreDatabase()
        try await insertion.insert(into: database)

        let contributor = try #require(await database.read { db in
            try OME.Contributor.fetchOne(db)
        })
        let originalImage = try #require(contributor.images?.first)
        let cacheDirectoryURL = try temporaryDirectoryURL()
        let remoteData = Data("lazy-contributor-photo".utf8)

        let cachedImage = try await withDependencies {
            $0.date.now = testImageCacheDate
            $0.defaultDatabase = database
            $0.lazyImageCache = .live
            $0.localImageFileStore = testLocalImageFileStore(directory: cacheDirectoryURL)
            $0.httpClient = .testClient { _, path, _ in
                #expect(path == "/artist-one.jpg")
                return remoteData
            }
        } operation: {
            @Dependency(\.lazyImageCache) var lazyImageCache
            return try await lazyImageCache.cache(
                originalImage,
                .init(contributorID: contributor.id)
            )
        }

        let updatedContributor = try await database.read { db in
            try OME.Contributor.fetchOne(db)
        }
        let blobs = try await database.read { db in
            try LocalImageBlob.fetchAll(db)
        }

        let cachedURL = try #require(cachedImage.url)
        let updatedURL = try #require(updatedContributor?.images?.first?.url)
        #expect(cachedURL.isFileURL)
        #expect(updatedURL == contributorPhotoURL)
        expectNoDifference(try Data(contentsOf: cachedURL), remoteData)
        let blob = try #require(blobs.first)
        #expect(blob.parentKind == .contributor)
        #expect(blob.parentLocalID == "artist-one")
        #expect(blob.sourceURL == contributorPhotoURL)
        expectNoDifference(blob.data, remoteData)
        expectNoDifference(updatedContributor, contributor)
    }

    @Test
    func restoresLazyContributorImagesFromBlobWhenLocalFileIsMissing() async throws {
        let contributorPhotoURL = try #require(URL(string: "https://example.com/artist-one.jpg"))
        let source = try makeSourceRepository(
            contributorImages: [
                SourceImageAsset(
                    source: .url(contributorPhotoURL),
                    role: .photo,
                    renderKind: .fullImage,
                    materializationPolicy: .lazy
                )
            ]
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let insertion = try OME.SourceDatabaseInsertion(
            .init(source: source, organizerID: organizerID)
        )
        let database = try makeCoreDatabase()
        try await insertion.insert(into: database)

        let contributor = try #require(await database.read { db in
            try OME.Contributor.fetchOne(db)
        })
        let originalImage = try #require(contributor.images?.first)
        let cacheDirectoryURL = try temporaryDirectoryURL()
        let remoteData = Data("lazy-contributor-photo".utf8)

        let cachedImage = try await withDependencies {
            $0.date.now = testImageCacheDate
            $0.defaultDatabase = database
            $0.lazyImageCache = .live
            $0.localImageFileStore = testLocalImageFileStore(directory: cacheDirectoryURL)
            $0.httpClient = .testClient { _, _, _ in remoteData }
        } operation: {
            @Dependency(\.lazyImageCache) var lazyImageCache
            return try await lazyImageCache.cache(
                originalImage,
                .init(contributorID: contributor.id)
            )
        }
        let cachedURL = try #require(cachedImage.url)
        #expect(cachedURL.isFileURL)
        try FileManager.default.removeItem(at: cachedURL)

        let cachedContributor = try #require(await database.read { db in
            try OME.Contributor.fetchOne(db)
        })
        let cachedContributorImage = try #require(cachedContributor.images?.first)
        #expect(cachedContributorImage.url == contributorPhotoURL)

        let recoveryDirectoryURL = try temporaryDirectoryURL()
        let restoredImage = try await withDependencies {
            $0.date.now = testImageCacheDate
            $0.defaultDatabase = database
            $0.lazyImageCache = .live
            $0.localImageFileStore = testLocalImageFileStore(directory: recoveryDirectoryURL)
            $0.httpClient = .testClient { _, path, _ in
                Issue.record("Did not expect HTTP request while restoring lazy image: \(path)")
                return Data()
            }
        } operation: {
            @Dependency(\.lazyImageCache) var lazyImageCache
            return try await lazyImageCache.cache(
                cachedContributorImage,
                .init(contributorID: cachedContributor.id)
            )
        }

        let restoredURL = try #require(restoredImage.url)
        let blobs = try await database.read { db in
            try LocalImageBlob.fetchAll(db)
        }
        let restoredContributor = try await database.read { db in
            try OME.Contributor.fetchOne(db)
        }

        #expect(restoredURL.isFileURL)
        #expect(restoredURL != cachedURL)
        #expect(FileManager.default.fileExists(atPath: restoredURL.path))
        expectNoDifference(try Data(contentsOf: restoredURL), remoteData)
        expectNoDifference(restoredContributor, contributor)
        #expect(blobs.count == 1)
    }

    @Test
    func cachesLazyPosterImagesOnDemand() async throws {
        let source = try makeSourceRepository()
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let insertion = try OME.SourceDatabaseInsertion(
            .init(source: source, organizerID: organizerID)
        )
        let database = try makeCoreDatabase()
        try await insertion.insert(into: database)

        let poster = try #require(await database.read { db in
            try OME.Poster.fetchOne(db)
        })
        let cacheDirectoryURL = try temporaryDirectoryURL()
        let posterData = Data("lineup-poster".utf8)

        let cachedImage = try await withDependencies {
            $0.date.now = testImageCacheDate
            $0.defaultDatabase = database
            $0.lazyImageCache = .live
            $0.localImageFileStore = testLocalImageFileStore(directory: cacheDirectoryURL)
            $0.httpClient = .testClient { _, path, _ in
                #expect(path == "/lineup.png")
                return posterData
            }
        } operation: {
            @Dependency(\.lazyImageCache) var lazyImageCache
            return try await lazyImageCache.cache(
                poster.image,
                .init(posterID: poster.id)
            )
        }

        let updatedPoster = try await database.read { db in
            try OME.Poster.fetchOne(db)
        }
        let blobs = try await database.read { db in
            try LocalImageBlob.fetchAll(db)
        }

        let cachedURL = try #require(cachedImage.url)
        #expect(cachedURL.isFileURL)
        #expect(updatedPoster?.image.url == poster.image.url)
        let blob = try #require(blobs.first)
        #expect(blob.parentKind == .poster)
        #expect(blob.parentLocalID == "lineup")
        expectNoDifference(blob.data, posterData)
        expectNoDifference(updatedPoster, poster)
    }

    @Test
    func failingLazyImageCacheDoesNotMutateDatabase() async throws {
        let contributorPhotoURL = try #require(URL(string: "https://example.com/artist-one.jpg"))
        let source = try makeSourceRepository(
            contributorImages: [
                SourceImageAsset(
                    source: .url(contributorPhotoURL),
                    role: .photo,
                    renderKind: .fullImage,
                    materializationPolicy: .lazy
                )
            ]
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let insertion = try OME.SourceDatabaseInsertion(
            .init(source: source, organizerID: organizerID)
        )
        let database = try makeCoreDatabase()
        try await insertion.insert(into: database)

        let contributor = try #require(await database.read { db in
            try OME.Contributor.fetchOne(db)
        })
        let originalImage = try #require(contributor.images?.first)
        let cacheDirectoryURL = try temporaryDirectoryURL()

        do {
            _ = try await withDependencies {
                $0.date.now = testImageCacheDate
                $0.defaultDatabase = database
                $0.lazyImageCache = .live
                $0.localImageFileStore = testLocalImageFileStore(directory: cacheDirectoryURL)
                $0.httpClient = .testClient { _, _, _ -> Data in
                    throw TestImageCacheError.failed
                }
            } operation: {
                @Dependency(\.lazyImageCache) var lazyImageCache
                return try await lazyImageCache.cache(
                    originalImage,
                    .init(contributorID: contributor.id)
                )
            }
            Issue.record("Expected lazy image caching to fail.")
        } catch TestImageCacheError.failed {
        }

        let updatedContributor = try await database.read { db in
            try OME.Contributor.fetchOne(db)
        }
        let blobs = try await database.read { db in
            try LocalImageBlob.fetchAll(db)
        }

        expectNoDifference(updatedContributor, contributor)
        #expect(blobs.isEmpty)
    }

    @Test
    func insertsIntoDefaultDatabaseAfterRunningMigrations() async throws {
        let source = try makeSourceRepository()
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let insertion = try OME.SourceDatabaseInsertion(
            .init(source: source, organizerID: organizerID)
        )
        let database = try SQLiteData.defaultDatabase()

        try await withDependencies {
            $0.defaultDatabase = database
        } operation: {
            try await insertion.migrateAndInsertIntoDefaultDatabase()
        }

        let eventCount = try await database.read { db in
            try OME.Event.fetchCount(db)
        }
        let performanceCount = try await database.read { db in
            try OME.Performance.fetchCount(db)
        }

        expectNoDifference(eventCount, 1)
        expectNoDifference(performanceCount, 3)
    }

    private func makeSourceRepository(
        calendar: CalendarDTO? = nil,
        eventDirectoryName: String = "testival-2026",
        eventName: String = "Testival 2026",
        explicitLocalEventID: OME.ID<OME.Event>? = nil,
        eventPolicies: OME.Event.Policies? = nil,
        reportingLinks: [OME.Event.ReportingLink]? = nil,
        eventLocations: [OME.Event.Location]? = nil,
        eventContactNumbers: [OME.Event.ContactNumber]? = nil,
        eventImages: [SourceImageAsset]? = nil,
        stageImages: [SourceImageAsset]? = nil,
        contributorDID: DID? = nil,
        contributorImages: [SourceImageAsset]? = nil,
        contributorLinks: [ExternalPlatform.Link]? = nil,
        contributorName: String = "Artist One",
        includeDefaultContributor: Bool = true,
        scheduleItems: ScheduleDTO.ScheduleItems = [
            "meadow": [
                .init(
                    id: id("opening-set"),
                    title: "Opening Set",
                    startTime: "18:00",
                    endTime: "19:00",
                    contributors: [
                        .init(subject: .id(id("artist-one")))
                    ]
                ),
                .init(
                    title: "Late Set",
                    startTime: "20:00",
                    contributors: [
                        .init(subject: .name("Guest Artist"))
                    ]
                ),
                .init(
                    id: id("closing-set"),
                    title: "Closing Set",
                    startTime: "21:00",
                    endTime: "22:00"
                ),
            ]
        ]
    ) throws -> OpenMusicEventSourceRepository {
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let eventStartDate = try #require(LocalDate("2026-08-01"))
        let eventEndDate = try #require(LocalDate("2026-08-03"))
        let sourceOrganizerID = try #require(OME.Organizer.ID("did:plc:source"))

        return OpenMusicEventSourceRepository(
            calendar: calendar,
            events: [
                DirectoryContent(
                    directoryName: eventDirectoryName,
                    components: OpenMusicEventSourceEvent(
                        event: EventDTO(
                            id: explicitLocalEventID.map {
                                OME.Event.ID(
                                    organizerID: sourceOrganizerID,
                                    eventID: $0
                                )
                            },
                            name: eventName,
                            description: "A small fixture event.",
                            startDate: eventStartDate,
                            endDate: eventEndDate,
                            status: .known(.scheduled),
                            mode: .known(.inPerson),
                            locations: eventLocations,
                            uris: nil,
                            timeZone: timeZone,
                            images: eventImages,
                            contactNumbers: eventContactNumbers,
                            categoryConfigs: nil,
                            policies: eventPolicies,
                            reportingLinks: reportingLinks
                        ),
                        stages: [
                            try FileContent(
                                fileName: "meadow",
                                fileType: nil,
                                data: StageDTO(
                                    id: nil,
                                    name: "Meadow",
                                    color: 0x00aaee,
                                    category: nil,
                                    sortIndex: nil,
                                    images: stageImages,
                                    systemIconName: nil,
                                    iconShortCode: nil,
                                    lineup: nil
                                )
                            )
                        ],
                        contributors: includeDefaultContributor ? [
                            try FileContent(
                                fileName: "artist-one",
                                fileType: nil,
                                data: ContributorDTO(
                                    id: nil,
                                    name: contributorName,
                                    did: contributorDID,
                                    bio: nil,
                                    images: contributorImages,
                                    links: contributorLinks
                                )
                            )
                        ] : nil,
                        posters: [
                            try FileContent(
                                fileName: "lineup",
                                fileType: nil,
                                data: PosterDTO(
                                    id: nil,
                                    title: "Lineup",
                                    imageURL: URL(string: "https://example.com/lineup.png")!
                                )
                            )
                        ],
                        schedules: [
                            try FileContent(
                                fileName: "saturday",
                                fileType: nil,
                                data: ScheduleDTO(
                                    id: nil,
                                    eventID: nil,
                                    date: eventStartDate,
                                    startsAt: "18:00",
                                    endsAt: "22:30",
                                    customTitle: "Saturday",
                                    scheduleItems: scheduleItems
                                )
                            )
                        ],
                        channels: [
                            try FileContent(
                                fileName: "general",
                                fileType: nil,
                                data: OME.Channel.Draft(
                                    id: nil,
                                    name: "General",
                                    description: "Official fixture announcements.",
                                    iconImageURL: nil,
                                    headerImageURL: nil,
                                    sortIndex: nil,
                                    defaultNotificationState: .subscribed,
                                    notificationsRequired: false
                                )
                            )
                        ]
                    )
                )
            ]
        )
    }

    private func makeInlineScheduleSourceRepository() throws -> OpenMusicEventSourceRepository {
        var source = try makeSourceRepository()
        let scheduleItems = try #require(source.events[0].components.schedules?.first?.data.scheduleItems)
        source.events[0].components.event.schedule = InlineScheduleDTO(
            scheduleItems: scheduleItems
        )
        source.events[0].components.schedules = nil
        return source
    }

    private func sourceRepositoryWithCommunicationPosts(
        includePosts: Bool
    ) throws -> OpenMusicEventSourceRepository {
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let posts: [DirectoryContent<[FileContent<CommunicationPostDTO>]>]? = includePosts
            ? [
                DirectoryContent(
                    directoryName: "general",
                    components: [
                        try FileContent(
                            fileName: "arrival",
                            fileType: "md",
                            data: CommunicationPostDTO(
                                title: "Arrival Info",
                                contents: "Use the north gate."
                            )
                        ),
                        try FileContent(
                            fileName: "welcome",
                            fileType: "md",
                            data: CommunicationPostDTO(
                                title: "Welcome",
                                contents: "Welcome to Postival.",
                                headerImageURL: URL(string: "https://example.com/welcome.png")!,
                                images: [
                                    SourceImageAsset(
                                        source: .url(URL(string: "https://example.com/welcome-gallery.png")!),
                                        role: .photo,
                                        renderKind: .fullImage,
                                        materializationPolicy: .lazy
                                    )
                                ],
                                isPinned: true
                            )
                        ),
                    ]
                )
            ]
            : nil

        return OpenMusicEventSourceRepository(
            events: [
                DirectoryContent(
                    directoryName: "postival-2026",
                    components: OpenMusicEventSourceEvent(
                        event: EventDTO(
                            id: nil,
                            name: "Postival 2026",
                            description: nil,
                            startDate: nil,
                            endDate: nil,
                            status: nil,
                            mode: nil,
                            locations: nil,
                            uris: nil,
                            timeZone: timeZone,
                            images: nil,
                            contactNumbers: nil,
                            categoryConfigs: nil
                        ),
                        channels: [
                            try FileContent(
                                fileName: "general",
                                fileType: "yml",
                                data: OME.Channel.Draft(
                                    id: nil,
                                    name: "General",
                                    description: "Official updates.",
                                    iconImageURL: nil,
                                    headerImageURL: nil,
                                    sortIndex: nil,
                                    defaultNotificationState: .subscribed,
                                    notificationsRequired: false
                                )
                            )
                        ],
                        communicationPosts: posts
                    )
                )
            ]
        )
    }

    private func eventWorkspaceSummary(
        eventID: OME.Event.ID,
        database: any DatabaseWriter,
        baselineDatabase: SourceBaselineDatabase
    ) async throws -> EventWorkspaceSummary {
        return try EventWorkspaceSummary.query(
            eventID: eventID,
            using: database,
            referenceDatabase: baselineDatabase
        )
    }

    private func insert(
        _ insertion: OME.SourceDatabaseInsertion,
        into database: any DatabaseWriter,
        and baselineDatabase: SourceBaselineDatabase
    ) async throws {
        try await insertion.migrateAndInsert(into: baselineDatabase.database)
        try await insertion.insert(into: database)
    }

    private func makeCoreDatabase(path: String? = nil) throws -> any DatabaseWriter {
        let database: any DatabaseWriter
        if let path {
            var configuration = Configuration()
            configuration.busyMode = .timeout(5)
            configuration.foreignKeysEnabled = true
            database = try DatabasePool(path: path, configuration: configuration)
        } else {
            database = try SQLiteData.defaultDatabase()
        }
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        return database
    }

    private func temporaryDirectoryURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    enum WorkspaceCommunicationConflictScenario: Sendable {
        case addAdd
        case deleteModify
    }

    enum WorkspaceReconciliationFailurePoint: Equatable, Sendable {
        case referenceDatabase
        case writableDatabase
        case repository
    }

}

private func deterministicWorkspaceFileMerge(
    _ request: SourceControlFileMergeRequest
) async throws -> SourceControlFileMergeResult {
    if request.localContents == request.upstreamContents {
        return .merged(contents: request.localContents)
    }
    if request.baseContents == request.localContents {
        return .merged(contents: request.upstreamContents)
    }
    if request.baseContents == request.upstreamContents {
        return .merged(contents: request.localContents)
    }
    return .conflicted
}


private extension SourceRecordChange {
    func hasEventID(_ eventID: OME.Event.ID) -> Bool {
        primaryKeyValues.first { $0.columnName == "organizerID" }?.value
            == String(describing: eventID.organizerID).databaseValue
            && primaryKeyValues.first { $0.columnName == "eventID" }?.value
                == eventID.eventID.rawValue.rawValue.databaseValue
    }
}

private enum TestImageCacheError: Error {
    case failed
}

private enum WorkspaceReconciliationInjectedFailure: Error {
    case injectedRepositoryReplacement
}

private let testImageCacheDate = Date(timeIntervalSince1970: 1_700_000_000)

private func testLocalImageFileStore(directory: URL) -> LocalImageFileStoreClient {
    LocalImageFileStoreClient(
        existingFileURL: { assetKey, _ in
            let fileURL = testLocalImageFileURL(
                directory: directory,
                assetKey: assetKey
            )
            return FileManager.default.fileExists(atPath: fileURL.path)
                ? fileURL
                : nil
        },
        write: { assetKey, data, _ in
            let fileURL = testLocalImageFileURL(directory: directory, assetKey: assetKey)
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        }
    )
}

private func testLocalImageFileURL(directory: URL, assetKey: String) -> URL {
    directory.appending(path: assetKey.replacingOccurrences(of: "|", with: "-"))
}

private func id<Record>(_ string: String) -> OME.ID<Record> {
    OME.ID<Record>(.init(string))
}

private func tangledSourceProvenance(
    _ repository: String,
    ref: String = "HEAD"
) -> OME.SourceDatabaseInsertion.SourceProvenance {
    OME.SourceDatabaseInsertion.SourceProvenance(
        kind: .tangled,
        reference: "tangled.org/woody.fm/\(repository)",
        ref: ref
    )
}

private func eventID(
    _ eventID: String,
    organizerID: OME.Organizer.ID
) -> OME.Event.ID {
    OME.Event.ID(
        organizerID: organizerID,
        eventID: id(eventID)
    )
}

private func calendarID(
    organizerID: OME.Organizer.ID
) -> OME.Calendar.ID {
    OME.Calendar.ID(
        ownerID: organizerID,
        calendarID: OME.Calendar.defaultID
    )
}

private func calendarEntryID(
    _ entryID: String,
    organizerID: OME.Organizer.ID
) -> OME.CalendarEntry.ID {
    OME.CalendarEntry.ID(
        calendarOwnerID: organizerID,
        calendarID: OME.Calendar.defaultID,
        entryID: id(entryID)
    )
}

private func stageID(
    _ stageID: String,
    eventID: String,
    organizerID: OME.Organizer.ID
) -> OME.Stage.ID {
    OME.Stage.ID(
        organizerID: organizerID,
        eventID: id(eventID),
        stageID: id(stageID)
    )
}

private func scheduleID(
    _ scheduleID: String,
    eventID: String,
    organizerID: OME.Organizer.ID
) -> OME.Schedule.ID {
    OME.Schedule.ID(
        organizerID: organizerID,
        eventID: id(eventID),
        scheduleID: id(scheduleID)
    )
}

private func contributorID(
    _ contributorID: String,
    eventID: String,
    organizerID: OME.Organizer.ID
) -> OME.Contributor.ID {
    OME.Contributor.ID(
        organizerID: organizerID,
        eventID: id(eventID),
        contributorID: id(contributorID)
    )
}

private func channelID(
    _ channelID: String,
    eventID: String,
    organizerID: OME.Organizer.ID
) -> OME.Channel.ID {
    OME.Channel.ID(
        organizerID: organizerID,
        eventID: id(eventID),
        channelID: id(channelID)
    )
}

private func posterID(
    _ posterID: String,
    eventID: String,
    organizerID: OME.Organizer.ID
) -> OME.Poster.ID {
    OME.Poster.ID(
        organizerID: organizerID,
        eventID: id(eventID),
        posterID: id(posterID)
    )
}

private func performanceID(
    _ performanceID: String,
    eventID: String,
    organizerID: OME.Organizer.ID
) -> OME.Performance.ID {
    OME.Performance.ID(
        organizerID: organizerID,
        eventID: id(eventID),
        performanceID: id(performanceID)
    )
}

private func scheduleItemID(
    _ scheduleItemID: String,
    eventID: String,
    organizerID: OME.Organizer.ID
) -> OME.ScheduleItem.ID {
    OME.ScheduleItem.ID(
        organizerID: organizerID,
        eventID: id(eventID),
        scheduleItemID: id(scheduleItemID)
    )
}

private let pendingRelationshipCreatedAt = "1970-01-01T00:00:00Z"

private func scheduleContributorListingPolicy() -> OME.Event.Policies {
    OME.Event.Policies(
        contributors: .init(
            listing: .known(.scheduleContributors)
        )
    )
}

private func localDate(
    _ date: LocalDate,
    atHour hour: Int,
    minute: Int = 0,
    dayOffset: Int = 0,
    in timeZone: TimeZone
) throws -> Date {
    let resolvedDate = try #require(date.at(hour: hour, minute: minute, in: timeZone))
    guard dayOffset != 0 else { return resolvedDate }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return try #require(calendar.date(byAdding: .day, value: dayOffset, to: resolvedDate))
}
