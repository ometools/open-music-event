import ATProto
import CustomDump
import Dependencies
import FileTree
import Foundation
import GRDB
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceEditing
import SQLiteData
import SourceEditing
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
            insertion.performances,
            [
                OME.Performance.Draft(
                    id: performanceID("opening-set", eventID: resolvedEventID, organizerID: organizerID),
                    stageID: id("meadow"),
                    scheduleID: id("saturday"),
                    startTime: try localDate(scheduleDate, atHour: 18, in: timeZone),
                    endTime: try localDate(scheduleDate, atHour: 19, in: timeZone),
                    title: "Opening Set",
                    description: nil,
                    recordings: []
                ),
                OME.Performance.Draft(
                    id: performanceID("saturday-meadow-2", eventID: resolvedEventID, organizerID: organizerID),
                    stageID: id("meadow"),
                    scheduleID: id("saturday"),
                    startTime: try localDate(scheduleDate, atHour: 20, in: timeZone),
                    endTime: try localDate(scheduleDate, atHour: 21, in: timeZone),
                    title: "Late Set",
                    description: nil,
                    recordings: []
                ),
                OME.Performance.Draft(
                    id: performanceID("closing-set", eventID: resolvedEventID, organizerID: organizerID),
                    stageID: id("meadow"),
                    scheduleID: id("saturday"),
                    startTime: try localDate(scheduleDate, atHour: 21, in: timeZone),
                    endTime: try localDate(scheduleDate, atHour: 22, in: timeZone),
                    title: "Closing Set",
                    description: nil,
                    recordings: []
                ),
            ]
        )
        expectNoDifference(
            insertion.performanceContributors,
            [
                OME.Performance.Contributors.Draft(
                    performanceID: performanceID("opening-set", eventID: resolvedEventID, organizerID: organizerID),
                    contributorID: id("artist-one"),
                    anonymousName: nil
                ),
                OME.Performance.Contributors.Draft(
                    performanceID: performanceID("saturday-meadow-2", eventID: resolvedEventID, organizerID: organizerID),
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
            insertion.performances.map(\.id?.performanceID.rawValue.rawValue),
            [
                "opening-set",
                "schedule-meadow-2",
                "closing-set",
            ]
        )
        expectNoDifference(
            insertion.performances.map(\.scheduleID?.rawValue.rawValue),
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
                    performances: [:]
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
    func sourceRepositoryReportingLinkPersistsToEventRow() async throws {
        let reportingLink = OME.Event.ReportingLink(
            name: "Report an Incident",
            url: URL(string: "https://example.org/report")!,
            description: "Use this form to report an event safety concern."
        )
        let source = try makeSourceRepository(reportingLink: reportingLink)
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
            insertion.events.first?.reportingLink,
            reportingLink
        )

        let database = try makeCoreDatabase()
        try await insertion.insert(into: database)

        let insertedEvent = try await database.read { db in
            try OME.Event.where { $0.id.eq(eventID) }
                .fetchOne(db)
        }
        expectNoDifference(
            try #require(insertedEvent?.reportingLink),
            reportingLink
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
            performances: [
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
            insertion.performanceContributors,
            [
                OME.Performance.Contributors.Draft(
                    performanceID: performanceID("actor-set", eventID: "testival-source-testival-2026", organizerID: organizerID),
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
            performances: [
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
            performances: [
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
            insertion.performanceContributors,
            [
                OME.Performance.Contributors.Draft(
                    performanceID: performanceID("credited-set", eventID: "testival-source-testival-2026", organizerID: organizerID),
                    contributorID: id("artist-one"),
                    anonymousName: nil,
                    billing: .primary,
                    role: "dj",
                    sortIndex: 0
                ),
                OME.Performance.Contributors.Draft(
                    performanceID: performanceID("credited-set", eventID: "testival-source-testival-2026", organizerID: organizerID),
                    contributorID: nil,
                    anonymousName: "Dance Crew",
                    billing: .supporting,
                    role: "dancer",
                    sortIndex: 1
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
            performances: [
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
            insertion.performanceContributors,
            [
                OME.Performance.Contributors.Draft(
                    performanceID: performanceID("guest-set", eventID: "testival-source-testival-2026", organizerID: organizerID),
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
            performances: [
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
                    performanceIndex: 1,
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
            performances: [
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
            insertion.performanceContributors,
            [
                OME.Performance.Contributors.Draft(
                    performanceID: performanceID("actor-set", eventID: "testival-source-testival-2026", organizerID: organizerID),
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
            performances: [
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
            insertion.performanceContributors,
            [
                OME.Performance.Contributors.Draft(
                    performanceID: performanceID("artist-set", eventID: "testival-source-testival-2026", organizerID: organizerID),
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
        expectNoDifference(
            OME.sourceRecordTableTypes.map(ObjectIdentifier.init),
            [
                ObjectIdentifier(OME.Event.self),
                ObjectIdentifier(OME.Stage.self),
                ObjectIdentifier(OME.Contributor.self),
                ObjectIdentifier(OME.Schedule.self),
                ObjectIdentifier(OME.Performance.self),
                ObjectIdentifier(OME.Channel.self),
                ObjectIdentifier(OME.Poster.self),
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

        let notInWorkspace = try await database.read { db in
            try EventWorkspaceSummaryRequest(eventID: openedEventID).fetch(db)
        }

        expectNoDifference(
            notInWorkspace,
            EventWorkspaceSummary(
                eventID: openedEventID,
                availability: .notInWorkspace,
                groups: []
            )
        )

        let baselineID = SourceBaselineRecord.ID(source: sourceProvenance)
        let sourceBaseline = SourceBaselineRecord(
            source: sourceProvenance,
            databaseFileName: "missing-reference.sqlite",
            importedAt: Date(timeIntervalSince1970: 0)
        )
        let workspace = EditingWorkspaceRecord(teamSourceBaseline: sourceBaseline)
        try await database.write { db in
            try OME.Organizer.insert {
                insertion.organizers
            }
            .execute(db)
            try OME.Event.insert {
                insertion.events
            }
            .execute(db)
            try SourceBaselineRecord.insert {
                sourceBaseline
            }
            .execute(db)
            try EditingWorkspaceRecord.insert {
                workspace
            }
            .execute(db)
            try EventSourceProvenanceRecord.insert {
                insertion.eventSourceProvenances.map {
                    EventSourceProvenanceRecord($0, sourceBaselineID: baselineID)
                }
            }
            .execute(db)
            try EventEditingWorkspaceRecord.insert {
                insertion.eventSourceProvenances.map {
                    EventEditingWorkspaceRecord(
                        id: $0.eventID,
                        workspaceID: workspace.id
                    )
                }
            }
            .execute(db)
        }

        let workspaceNeedsPreparation = try await database.read { db in
            try EventWorkspaceSummaryRequest(eventID: openedEventID).fetch(db)
        }

        expectNoDifference(
            workspaceNeedsPreparation,
            EventWorkspaceSummary(
                eventID: openedEventID,
                availability: .workspaceNeedsPreparation,
                groups: []
            )
        )

        try await database.write { db in
            try EventEditingWorkspaceRecord
                .where { $0.id.eq(openedEventID) }
                .delete()
                .execute(db)
            try EditingWorkspaceRecord
                .where { $0.id.eq(workspace.id) }
                .delete()
                .execute(db)
            try SourceBaselineRecord
                .where { $0.id.eq(baselineID) }
                .delete()
                .execute(db)
        }

        let baselineDatabase = try defaultBaselineDatabase()
        defer { try? FileManager.default.removeItem(atPath: baselineDatabase.path) }

        try await withDependencies {
            $0.defaultBaselineDatabase = baselineDatabase
            $0.sourceReferenceDatabase = .test(database: baselineDatabase)
        } operation: {
            try await insertion.insert(into: database)
        }

        let baselineRecord = try await database.read { db in
            try SourceBaselineRecord
                .where { $0.id.eq(baselineID) }
                .fetchOne(db)
        }
        #expect(baselineRecord?.id == baselineID)
        #expect(baselineRecord?.sourceKind == sourceProvenance.kind)
        #expect(baselineRecord?.sourceReference == sourceProvenance.reference)
        #expect(baselineRecord?.ref == sourceProvenance.ref)
        #expect(baselineRecord?.databaseFileName == URL(fileURLWithPath: baselineDatabase.path).lastPathComponent)

        let sourceProvenanceRecord = try await database.read { db in
            try EventSourceProvenanceRecord
                .where { $0.id.eq(openedEventID) }
                .fetchOne(db)
        }
        #expect(sourceProvenanceRecord?.sourceBaselineID == baselineID)

        let workspaceRecord = try await database.read { db in
            try EditingWorkspaceRecord
                .where { $0.id.eq(EditingWorkspaceRecord.ID(sourceBaselineID: baselineID)) }
                .fetchOne(db)
        }
        #expect(workspaceRecord?.kind == .team)
        #expect(workspaceRecord?.sourceBaselineID == baselineID)

        let eventWorkspaceRecord = try await database.read { db in
            try EventEditingWorkspaceRecord
                .where { $0.id.eq(openedEventID) }
                .fetchOne(db)
        }
        #expect(eventWorkspaceRecord?.workspaceID == workspaceRecord?.id)

        let baselineStage = try baselineDatabase.read { db in
            try OME.Stage
                .where { $0.id.eq(stageID("meadow", eventID: "testival-source-testival-2026", organizerID: organizerID)) }
                .fetchOne(db)
        }
        #expect(baselineStage?.name == "Meadow")

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
    func sourceEditSummaryIncludesEventChangesForSourceBaseline() async throws {
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

        try await withDependencies {
            $0.defaultBaselineDatabase = baselineDatabase
            $0.sourceReferenceDatabase = .test(database: baselineDatabase)
        } operation: {
            try await insertion.insert(into: database)
        }

        try await database.write { db in
            try OME.Stage
                .find(stageID("meadow", eventID: "testival-source-testival-2026", organizerID: organizerID))
                .update { $0.name = "Updated Meadow" }
                .execute(db)
        }

        let sourceEditingSession = try SourceEditingSession(
            workingDatabasePath: workingDatabasePath,
            baselineDatabasePath: baselineDatabasePath
        )
        let summary = try await withDependencies {
            $0.defaultDatabase = sourceEditingSession.database
            $0.sourceEditingSession = sourceEditingSession
        } operation: {
            try await sourceEditingSession.database.read { db in
                try SourceEditSummaryRequest(
                    sourceBaselineID: SourceBaselineRecord.ID(source: sourceProvenance),
                    calendarID: calendarID(organizerID: organizerID)
                )
                .fetch(db)
            }
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
    func sourceInsertionStoresSourceKindSeparatelyFromEventIDOrigin() async throws {
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

        try await withDependencies {
            $0.defaultBaselineDatabase = baselineDatabase
            $0.sourceReferenceDatabase = .test(database: baselineDatabase)
        } operation: {
            try await insertion.insert(into: database)
        }

        let appSourceBaselineRow = try database.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                SELECT "sourceKind", "sourceReference", "ref"
                FROM "sourceBaselines"
                LIMIT 1
                """
            )
            return try #require(row)
        }
        #expect(appSourceBaselineRow["sourceKind"] as String == "tangled")
        #expect(appSourceBaselineRow["sourceReference"] as String == sourceProvenance.reference)
        #expect(appSourceBaselineRow["ref"] as String == "HEAD")

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

        let referenceSourceBaselineRow = try baselineDatabase.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                SELECT "sourceKind", "sourceReference", "ref"
                FROM "sourceBaselines"
                LIMIT 1
                """
            )
            return try #require(row)
        }
        #expect(referenceSourceBaselineRow["sourceKind"] as String == "tangled")
        #expect(referenceSourceBaselineRow["sourceReference"] as String == sourceProvenance.reference)
        #expect(referenceSourceBaselineRow["ref"] as String == "HEAD")

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
    func editSummariesUseAttachedSourceEditingSession() async throws {
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

        try await withDependencies {
            $0.defaultBaselineDatabase = baselineDatabase
            $0.sourceReferenceDatabase = .test(database: baselineDatabase)
        } operation: {
            try await insertion.insert(into: database)
        }

        try await database.write { db in
            try OME.Stage
                .find(stageID("meadow", eventID: "testival-source-testival-2026", organizerID: organizerID))
                .update { $0.name = "Updated Meadow" }
                .execute(db)
        }

        let sourceEditingSession = try SourceEditingSession(
            workingDatabasePath: workingDatabasePath,
            baselineDatabasePath: baselineDatabasePath
        )
        let eventSummary = try await withDependencies {
            $0.defaultDatabase = sourceEditingSession.database
            $0.sourceEditingSession = sourceEditingSession
        } operation: {
            try await sourceEditingSession.database.read { db in
                try EventWorkspaceSummaryRequest(eventID: openedEventID).fetch(db)
            }
        }
        let sourceSummary = try await withDependencies {
            $0.defaultDatabase = sourceEditingSession.database
            $0.sourceEditingSession = sourceEditingSession
        } operation: {
            try await sourceEditingSession.database.read { db in
                try SourceEditSummaryRequest(
                    sourceBaselineID: SourceBaselineRecord.ID(source: sourceProvenance),
                    calendarID: calendarID(organizerID: organizerID)
                )
                .fetch(db)
            }
        }

        #expect(eventSummary.availability == .available)
        #expect(eventSummary.totalCount == 1)
        #expect(sourceSummary.availability == .available)
        #expect(sourceSummary.totalCount == 1)
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

        try await withDependencies {
            $0.defaultBaselineDatabase = baselineDatabase
            $0.sourceReferenceDatabase = .test(database: baselineDatabase)
        } operation: {
            try await insertion.insert(into: database)
        }

        try await database.write { db in
            try OME.Stage
                .find(stageID("meadow", eventID: "testival-source-testival-2026", organizerID: organizerID))
                .update { $0.name = "Changed through default database" }
                .execute(db)
        }

        let sourceEditingSession = try SourceEditingSession(
            workingDatabasePath: workingDatabasePath,
            baselineDatabasePath: baselineDatabase.path
        )
        let summary = try await withDependencies {
            $0.defaultDatabase = sourceEditingSession.database
            $0.sourceEditingSession = sourceEditingSession
        } operation: {
            try await sourceEditingSession.database.read { db in
                try EventWorkspaceSummaryRequest(eventID: openedEventID).fetch(db)
            }
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
    func eventWorkspaceSummaryCountsAddedPerformanceInDefaultDatabase() async throws {
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

        try await withDependencies {
            $0.defaultBaselineDatabase = baselineDatabase
            $0.sourceReferenceDatabase = .test(database: baselineDatabase)
        } operation: {
            try await insertion.insert(into: database)
        }

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
        #expect(summary.totalCount == 1)
        #expect(summary.badgeCount == 1)
        let performanceGroup = try #require(
            summary.groups.first { $0.id == OME.Performance.tableName }
        )
        #expect(performanceGroup.displayName == "Performance")
        #expect(performanceGroup.added == 1)
        #expect(performanceGroup.modified == 0)
        #expect(performanceGroup.deleted == 0)
        let performanceRecord = try #require(performanceGroup.records.first)
        #expect(performanceRecord.kind == .added)
        #expect(performanceRecord.recordDiff?.contains("Late Addition") == true)
        let performanceComparison = try #require(
            summary.recordComparisons[performanceRecord]?.as(OME.Performance.self)
        )
        #expect(performanceComparison.left == nil)
        #expect(performanceComparison.right?.title == "Late Addition")
        let titleChange = try #require(
            performanceRecord.fieldChanges.first { $0.columnName == "title" }
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

        try await withDependencies {
            $0.defaultBaselineDatabase = baselineDatabase
            $0.sourceReferenceDatabase = .test(database: baselineDatabase)
        } operation: {
            try await insertion.insert(into: database)
        }

        try await database.write { db in
            try OME.Event
                .find(openedEventID)
                .update { $0.name = "Changed Event" }
                .execute(db)
            try OME.Stage
                .find(stageID("meadow", eventID: "testival-source-testival-2026", organizerID: organizerID))
                .update { $0.name = "Changed Stage" }
                .execute(db)
        }

        let changedSummary = try await eventWorkspaceSummary(
            eventID: openedEventID,
            database: database,
            baselineDatabase: baselineDatabase
        )
        #expect(changedSummary.availability == .available)
        #expect(changedSummary.totalCount == 2)

        try withDependencies {
            $0.defaultDatabase = database
            $0.defaultBaselineDatabase = baselineDatabase
            $0.eventWorkspaceResetter = .openMusicEvent
            $0.sourceReferenceDatabase = .test(database: baselineDatabase)
        } operation: {
            @Dependency(\.eventWorkspaceResetter) var resetter
            try resetter.reset(openedEventID)
        }

        let resetSummary = try await eventWorkspaceSummary(
            eventID: openedEventID,
            database: database,
            baselineDatabase: baselineDatabase
        )
        #expect(resetSummary.availability == .available)
        #expect(resetSummary.totalCount == 0)

        let restoredRows = try await database.read { db in
            let event = try #require(try OME.Event.find(openedEventID).fetchOne(db))
            let stage = try #require(
                try OME.Stage
                    .find(stageID("meadow", eventID: "testival-source-testival-2026", organizerID: organizerID))
                    .fetchOne(db)
            )
            return (event, stage)
        }
        #expect(restoredRows.0.name == "Testival 2026")
        #expect(restoredRows.1.name == "Meadow")
    }

    @Test
    func eventWorkspaceSummaryUsesSourceLocalReferenceDatabase() async throws {
        let source = try makeSourceRepository()
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let openedEventID = eventID("source-testival-2026", organizerID: organizerID)
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let repositoryURL = directoryURL.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        let sourceProvenance = OME.SourceDatabaseInsertion.SourceProvenance(
            kind: .local,
            reference: repositoryURL.path
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
        try await insertion.insert(into: database)

        #expect(
            FileManager.default.fileExists(
                atPath: repositoryURL.appending(path: ".ome/reference.sqlite").path()
            )
        )

        try await database.write { db in
            try OME.Stage
                .find(stageID("meadow", eventID: "source-testival-2026", organizerID: organizerID))
                .update { $0.name = "Changed through default database" }
                .execute(db)
        }

        let baselineDatabasePath = repositoryURL
            .appending(path: ".ome/reference.sqlite")
            .path()
        let sourceEditingSession = try SourceEditingSession(
            workingDatabasePath: directoryURL.appendingPathComponent("working.sqlite").path,
            baselineDatabasePath: baselineDatabasePath
        )
        let summary = try await withDependencies {
            $0.defaultDatabase = sourceEditingSession.database
            $0.sourceEditingSession = sourceEditingSession
        } operation: {
            try await sourceEditingSession.database.read { db in
                try EventWorkspaceSummaryRequest(eventID: openedEventID).fetch(db)
            }
        }

        #expect(summary.availability == .available)
        #expect(summary.totalCount == 1)
        let stageGroup = try #require(
            summary.groups.first { $0.id == OME.Stage.tableName }
        )
        let stageRecord = try #require(stageGroup.records.first)
        #expect(stageRecord.recordDiff?.contains("Changed through default database") == true)
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
            $0.defaultBaselineDatabase = baselineDatabase
            $0.sourceReferenceDatabase = .test(database: baselineDatabase)
            $0.localImageFileStore = testLocalImageFileStore(directory: cacheDirectoryURL)
        } operation: {
            try await insertion.insert(into: database)
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

        try await withDependencies {
            $0.defaultBaselineDatabase = baselineDatabase
            $0.sourceReferenceDatabase = .test(database: baselineDatabase)
        } operation: {
            try await insertion.insert(into: database)
        }

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

        try await withDependencies {
            $0.defaultBaselineDatabase = baselineDatabase
            $0.sourceReferenceDatabase = .test(database: baselineDatabase)
        } operation: {
            try await insertion.insert(into: database)
        }

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

        try await withDependencies {
            $0.defaultBaselineDatabase = baselineDatabase
            $0.sourceReferenceDatabase = .test(database: baselineDatabase)
        } operation: {
            try await insertion.insert(into: database)
        }

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
    func eventWorkspaceSummaryCountsImageMetadataChanges() async throws {
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

        try await withDependencies {
            $0.defaultBaselineDatabase = baselineDatabase
            $0.sourceReferenceDatabase = .test(database: baselineDatabase)
        } operation: {
            try await insertion.insert(into: database)
        }

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
        #expect(record.recordDiff?.contains("focalPoint") == true)
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
    func reimportsSameSourceRefWithoutDuplicatingSourceBaseline() async throws {
        let firstSource = try makeSourceRepository(
            eventDirectoryName: "2026",
            eventName: "Wicked Woods"
        )
        let secondSource = try makeSourceRepository(
            eventDirectoryName: "2026",
            eventName: "Wicked Woods Updated"
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let sourceProvenance = tangledSourceProvenance("wicked-woods", ref: "main")
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
        let baselineDatabase = try defaultBaselineDatabase()
        defer { try? FileManager.default.removeItem(atPath: baselineDatabase.path) }

        try await withDependencies {
            $0.defaultBaselineDatabase = baselineDatabase
            $0.sourceReferenceDatabase = .test(database: baselineDatabase)
        } operation: {
            try await firstInsertion.insert(into: database)
            try await secondInsertion.insert(into: database)
        }

        let baselineID = SourceBaselineRecord.ID(source: sourceProvenance)
        let baselineRecords = try await database.read { db in
            try SourceBaselineRecord.fetchAll(db)
        }
        let baselineDatabaseRecords = try baselineDatabase.read { db in
            try SourceBaselineRecord.fetchAll(db)
        }
        let baselineEvent = try baselineDatabase.read { db in
            try OME.Event
                .where { $0.id.eq(eventID("wicked-woods-2026", organizerID: organizerID)) }
                .fetchOne(db)
        }

        expectNoDifference(baselineRecords.map(\.id), [baselineID])
        expectNoDifference(baselineDatabaseRecords.map(\.id), [baselineID])
        #expect(baselineEvent?.name == "Wicked Woods Updated")
    }

    @Test
    func deletesDownloadedOrganizerSourceData() async throws {
        let source = try makeSourceRepository(
            eventDirectoryName: "2026",
            eventName: "Wicked Woods"
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let sourceProvenance = tangledSourceProvenance("wicked-woods", ref: "main")
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

        try await withDependencies {
            $0.defaultBaselineDatabase = baselineDatabase
            $0.sourceReferenceDatabase = .test(database: baselineDatabase)
        } operation: {
            try await insertion.insert(into: database)
        }

        let deletion = try await withDependencies {
            $0.defaultBaselineDatabase = baselineDatabase
            $0.sourceReferenceDatabase = .test(database: baselineDatabase)
        } operation: {
            try await database.write { db in
                try OME.deleteDownloadedOrganizerSourceData(
                    for: organizerID,
                    in: db
                )
            }
        }
        try await database.write { db in
            try OME.Organizer
                .where { $0.id.eq(organizerID) }
                .delete()
                .execute(db)
        }

        let sourceBaselineCount = try await database.read { db in
            try SourceBaselineRecord.fetchCount(db)
        }
        let baselineSourceBaselineCount = try baselineDatabase.read { db in
            try SourceBaselineRecord.fetchCount(db)
        }
        let sourceProvenanceCount = try await database.read { db in
            try EventSourceProvenanceRecord.fetchCount(db)
        }
        let baselineSourceProvenanceCount = try baselineDatabase.read { db in
            try EventSourceProvenanceRecord.fetchCount(db)
        }
        let baselineOrganizerCount = try baselineDatabase.read { db in
            try OME.Organizer.fetchCount(db)
        }

        expectNoDifference(deletion.sourceProvenances, [sourceProvenance])
        #expect(sourceBaselineCount == 0)
        #expect(baselineSourceBaselineCount == 0)
        #expect(sourceProvenanceCount == 0)
        #expect(baselineSourceProvenanceCount == 0)
        #expect(baselineOrganizerCount == 0)
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
            performances: [
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
            insertion.performances,
            [
                OME.Performance.Draft(
                    id: performanceID("late-night", eventID: "2025", organizerID: organizerID),
                    stageID: id("meadow"),
                    scheduleID: id("saturday"),
                    startTime: try localDate(scheduleDate, atHour: 23, minute: 30, in: timeZone),
                    endTime: try localDate(
                        scheduleDate,
                        atHour: 0,
                        minute: 15,
                        dayOffset: 1,
                        in: timeZone
                    ),
                    title: "Late Night",
                    description: nil,
                    recordings: []
                ),
                OME.Performance.Draft(
                    id: performanceID("after-midnight", eventID: "2025", organizerID: organizerID),
                    stageID: id("meadow"),
                    scheduleID: id("saturday"),
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
                    description: nil,
                    recordings: []
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
            performances: [
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
            insertion.performances.map(\.recordings),
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
            performances: [
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
                .missingPerformanceEndTime(
                    scheduleID: scheduleID("saturday", eventID: "testival-2026", organizerID: organizerID),
                    stageID: id("meadow"),
                    performanceIndex: 1
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
        reportingLink: OME.Event.ReportingLink? = nil,
        eventImages: [SourceImageAsset]? = nil,
        stageImages: [SourceImageAsset]? = nil,
        contributorDID: DID? = nil,
        contributorImages: [SourceImageAsset]? = nil,
        includeDefaultContributor: Bool = true,
        performances: [String: [ScheduleDTO.Performance]] = [
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
                            locations: nil,
                            uris: nil,
                            timeZone: timeZone,
                            images: eventImages,
                            contactNumbers: nil,
                            categoryConfigs: nil,
                            policies: eventPolicies,
                            reportingLink: reportingLink
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
                                    name: "Artist One",
                                    did: contributorDID,
                                    bio: nil,
                                    images: contributorImages,
                                    links: nil
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
                                    performances: performances
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
        let performances = try #require(source.events[0].components.schedules?.first?.data.performances)
        source.events[0].components.event.schedule = InlineScheduleDTO(
            performances: performances
        )
        source.events[0].components.schedules = nil
        return source
    }

    private func eventWorkspaceSummary(
        eventID: OME.Event.ID,
        database: any DatabaseWriter,
        baselineDatabase: SourceBaselineDatabase
    ) async throws -> EventWorkspaceSummary {
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let workingDatabasePath = directoryURL.appendingPathComponent("working.sqlite").path
        let workingDatabase = try makeCoreDatabase(path: workingDatabasePath)
        try database.backup(to: workingDatabase)
        let sourceEditingSession = try SourceEditingSession(
            workingDatabasePath: workingDatabasePath,
            baselineDatabasePath: baselineDatabase.path
        )
        return try await withDependencies {
            $0.defaultDatabase = sourceEditingSession.database
            $0.sourceEditingSession = sourceEditingSession
        } operation: {
            try await sourceEditingSession.database.read { db in
                try EventWorkspaceSummaryRequest(eventID: eventID).fetch(db)
            }
        }
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
}


private enum TestImageCacheError: Error {
    case failed
}

private let testImageCacheDate = Date(timeIntervalSince1970: 1_700_000_000)

private func testLocalImageFileStore(directory: URL) -> LocalImageFileStoreClient {
    LocalImageFileStoreClient { assetKey, data, _ in
        let fileURL = testLocalImageFileURL(directory: directory, assetKey: assetKey)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }
}

private func testLocalImageFileURL(directory: URL, assetKey: String) -> URL {
    directory.appending(path: assetKey.replacingOccurrences(of: "|", with: "-"))
}

private extension SourceReferenceDatabaseClient {
    static func test(database: SourceBaselineDatabase) -> Self {
        Self(
            url: { _ in URL(fileURLWithPath: database.path) },
            prepareForImport: { _ in database },
            existing: { _ in database }
        )
    }
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
