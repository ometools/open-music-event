import CustomDump
import FileTree
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSource
import SQLiteData
import Testing

struct SourceDatabaseInsertionTests {
    @Test
    func buildsInsertionRowsFromSourceRepository() throws {
        let source = try makeSourceRepository()
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let insertion = try OME.SourceDatabaseInsertion(
            .init(source: source, organizerID: organizerID)
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
            insertion.events.map(\.id),
            [
                id("testival-2026")
            ]
        )
        expectNoDifference(
            insertion.eventOrganizers,
            [
                OME.EventOrganizer.Draft(
                    id: .init(
                        eventID: id("testival-2026"),
                        organizerID: organizerID
                    )
                )
            ]
        )
        expectNoDifference(insertion.stages.map(\.id), [id("meadow")])
        expectNoDifference(insertion.participants.map(\.id), [id("artist-one")])
        expectNoDifference(insertion.channels.map(\.id), [id("general")])
        expectNoDifference(insertion.posters.map(\.id), [id("lineup")])
        expectNoDifference(
            insertion.schedules,
            [
                OME.Schedule.Draft(
                    id: id("saturday"),
                    eventID: id("testival-2026"),
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
                    id: id("opening-set"),
                    eventID: id("testival-2026"),
                    stageID: id("meadow"),
                    scheduleID: id("saturday"),
                    startTime: try localDate(scheduleDate, atHour: 18, in: timeZone),
                    endTime: try localDate(scheduleDate, atHour: 19, in: timeZone),
                    title: "Opening Set",
                    description: nil,
                    recordings: []
                ),
                OME.Performance.Draft(
                    id: id("saturday-meadow-2"),
                    eventID: id("testival-2026"),
                    stageID: id("meadow"),
                    scheduleID: id("saturday"),
                    startTime: try localDate(scheduleDate, atHour: 20, in: timeZone),
                    endTime: try localDate(scheduleDate, atHour: 21, in: timeZone),
                    title: "Late Set",
                    description: nil,
                    recordings: []
                ),
                OME.Performance.Draft(
                    id: id("closing-set"),
                    eventID: id("testival-2026"),
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
            insertion.performanceParticipants,
            [
                OME.Performance.Participants.Draft(
                    performanceID: id("opening-set"),
                    participantID: id("artist-one"),
                    anonymousName: nil
                ),
                OME.Performance.Participants.Draft(
                    performanceID: id("saturday-meadow-2"),
                    participantID: nil,
                    anonymousName: "Guest Artist"
                ),
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
                    scheduleID: id("saturday"),
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
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)

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
        let performanceParticipantCount = try await database.read { db in
            try OME.Performance.Participants.fetchCount(db)
        }

        #expect(organizerCount == 1)
        #expect(eventCount == 1)
        #expect(eventOrganizerCount == 1)
        #expect(performanceCount == 3)
        #expect(performanceParticipantCount == 2)
    }

    private func makeSourceRepository(
        performances: [String: [ScheduleDTO.Performance]] = [
            "meadow": [
                .init(
                    id: id("opening-set"),
                    title: "Opening Set",
                    startTime: "18:00",
                    endTime: "19:00",
                    participantIDs: [id("artist-one")]
                ),
                .init(
                    title: "Late Set",
                    startTime: "20:00",
                    participantNames: ["Guest Artist"]
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

        return OpenMusicEventSourceRepository(
            events: [
                DirectoryContent(
                    directoryName: "testival-2026",
                    components: OpenMusicEventSourceEvent(
                        event: OME.Event.Draft(
                            id: nil,
                            name: "Testival 2026",
                            description: "A small fixture event.",
                            startDate: eventStartDate,
                            endDate: eventEndDate,
                            status: .scheduled,
                            mode: .known(.inPerson),
                            locations: nil,
                            uris: nil,
                            timeZone: timeZone,
                            imageURL: nil,
                            iconImageURL: nil,
                            siteMapImageURL: nil,
                            contactNumbers: nil,
                            categoryConfigs: nil
                        ),
                        stages: [
                            try FileContent(
                                fileName: "meadow",
                                fileType: nil,
                                data: OME.Stage.Draft(
                                    id: nil,
                                    name: "Meadow",
                                    color: 0x00aaee,
                                    category: nil,
                                    sortIndex: nil,
                                    iconImageURL: nil,
                                    systemIconName: nil,
                                    iconShortCode: nil,
                                    imageURL: nil,
                                    posterImageURL: nil,
                                    lineup: nil
                                )
                            )
                        ],
                        participants: [
                            try FileContent(
                                fileName: "artist-one",
                                fileType: nil,
                                data: OME.Participant.Draft(
                                    id: nil,
                                    name: "Artist One",
                                    bio: nil,
                                    imageURL: nil,
                                    logoURL: nil,
                                    kind: nil,
                                    links: nil
                                )
                            )
                        ],
                        posters: [
                            try FileContent(
                                fileName: "lineup",
                                fileType: nil,
                                data: OME.Poster.Draft(
                                    id: nil,
                                    eventID: id("testival-2026"),
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
                                    eventID: id("testival-2026"),
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
}

private func id<Record>(_ string: String) -> OME.ID<Record> {
    OME.ID<Record>(.init(string))
}

private func localDate(
    _ date: LocalDate,
    atHour hour: Int,
    minute: Int = 0,
    in timeZone: TimeZone
) throws -> Date {
    try #require(date.at(hour: hour, minute: minute, in: timeZone))
}
