import ATProto
import CustomDump
import Dependencies
import FileTree
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceEditing
import SQLiteData
import SourceEditing
import Testing

struct SourceDatabaseInsertionTests {
    @Test
    func buildsInsertionRowsFromSourceRepository() throws {
        let source = try makeSourceRepository()
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let sourceProvenance = tangledSourceProvenance("testival-source")
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
            insertion.events.map(\.id),
            [
                eventID("testival-2026", organizerID: organizerID)
            ]
        )
        expectNoDifference(
            insertion.eventSourceProvenances,
            [
                OME.SourceDatabaseInsertion.EventSourceProvenance(
                    eventID: eventID("testival-2026", organizerID: organizerID),
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
                        eventID: id("testival-2026"),
                        eventOrganizerID: organizerID
                    )
                )
            ]
        )
        expectNoDifference(
            insertion.stages.map(\.id),
            [stageID("meadow", eventID: "testival-2026", organizerID: organizerID)]
        )
        expectNoDifference(
            insertion.participants.map(\.id),
            [participantID("artist-one", eventID: "testival-2026", organizerID: organizerID)]
        )
        expectNoDifference(
            insertion.channels.map(\.id),
            [channelID("general", eventID: "testival-2026", organizerID: organizerID)]
        )
        expectNoDifference(
            insertion.posters.map(\.id),
            [posterID("lineup", eventID: "testival-2026", organizerID: organizerID)]
        )
        expectNoDifference(
            insertion.schedules,
            [
                OME.Schedule.Draft(
                    id: scheduleID("saturday", eventID: "testival-2026", organizerID: organizerID),
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
                    id: performanceID("opening-set", eventID: "testival-2026", organizerID: organizerID),
                    stageID: id("meadow"),
                    scheduleID: id("saturday"),
                    startTime: try localDate(scheduleDate, atHour: 18, in: timeZone),
                    endTime: try localDate(scheduleDate, atHour: 19, in: timeZone),
                    title: "Opening Set",
                    description: nil,
                    recordings: []
                ),
                OME.Performance.Draft(
                    id: performanceID("saturday-meadow-2", eventID: "testival-2026", organizerID: organizerID),
                    stageID: id("meadow"),
                    scheduleID: id("saturday"),
                    startTime: try localDate(scheduleDate, atHour: 20, in: timeZone),
                    endTime: try localDate(scheduleDate, atHour: 21, in: timeZone),
                    title: "Late Set",
                    description: nil,
                    recordings: []
                ),
                OME.Performance.Draft(
                    id: performanceID("closing-set", eventID: "testival-2026", organizerID: organizerID),
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
                    organizerID: organizerID,
                    eventID: id("testival-2026"),
                    performanceID: id("opening-set"),
                    participantID: id("artist-one"),
                    anonymousName: nil
                ),
                OME.Performance.Participants.Draft(
                    organizerID: organizerID,
                    eventID: id("testival-2026"),
                    performanceID: id("saturday-meadow-2"),
                    participantID: nil,
                    anonymousName: "Guest Artist"
                ),
            ]
        )
    }

    @Test
    func sourceEditingListsSourceRecordTypes() {
        expectNoDifference(
            OME.sourceRecordTypes.map(ObjectIdentifier.init),
            [
                ObjectIdentifier(OME.Event.self),
                ObjectIdentifier(OME.Stage.self),
                ObjectIdentifier(OME.Participant.self),
                ObjectIdentifier(OME.Schedule.self),
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
    func eventEditSummaryReportsSourceBaselineAvailability() async throws {
        let source = try makeSourceRepository()
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let openedEventID = eventID("testival-2026", organizerID: organizerID)
        let sourceProvenance = tangledSourceProvenance("testival-source", ref: "main")
        let insertion = try OME.SourceDatabaseInsertion(
            .init(
                source: source,
                organizerID: organizerID,
                sourceProvenance: sourceProvenance
            )
        )
        let database = try makeCoreDatabase()

        let notSourceBacked = try await database.read { db in
            try EventEditSummaryRequest(eventID: openedEventID).fetch(db)
        }

        expectNoDifference(
            notSourceBacked,
            EventEditSummary(
                eventID: openedEventID,
                availability: .notSourceBacked,
                groups: []
            )
        )

        try await database.write { db in
            try OME.Organizer.insert {
                insertion.organizers
            }
            .execute(db)
            try OME.Event.insert {
                insertion.events
            }
            .execute(db)
            try EventSourceProvenanceRecord.insert {
                insertion.eventSourceProvenances.map { EventSourceProvenanceRecord($0) }
            }
            .execute(db)
        }

        let missingBaseline = try await database.read { db in
            try EventEditSummaryRequest(eventID: openedEventID).fetch(db)
        }

        expectNoDifference(
            missingBaseline,
            EventEditSummary(
                eventID: openedEventID,
                availability: .missingBaseline,
                groups: []
            )
        )

        let baselineDatabase = try defaultBaselineDatabase()
        defer { try? FileManager.default.removeItem(atPath: baselineDatabase.path) }

        try await withDependencies {
            $0.defaultBaselineDatabase = baselineDatabase
        } operation: {
            try await insertion.insert(into: database)
        }

        let baselineID = SourceBaselineRecord.ID(source: sourceProvenance)
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

        let baselineStage = try baselineDatabase.read { db in
            try OME.Stage
                .where { $0.id.eq(stageID("meadow", eventID: "testival-2026", organizerID: organizerID)) }
                .fetchOne(db)
        }
        #expect(baselineStage?.name == "Meadow")

        try await database.write { db in
            try OME.Stage
                .find(stageID("meadow", eventID: "testival-2026", organizerID: organizerID))
                .update { $0.name = "Updated Meadow" }
                .execute(db)
        }

        let available = try await withDependencies {
            $0.defaultBaselineDatabase = baselineDatabase
        } operation: {
            try await database.read { db in
                try EventEditSummaryRequest(eventID: openedEventID).fetch(db)
            }
        }

        #expect(available.eventID == openedEventID)
        #expect(available.availability == .available)
        #expect(available.totalCount == 1)
        let stageGroup = try #require(
            available.groups.first { $0.id == OME.Stage.tableName }
        )
        expectNoDifference(
            stageGroup,
            SourceChangeGroup(
                id: OME.Stage.tableName,
                displayName: "Stage",
                added: 0,
                modified: 1,
                deleted: 0
            )
        )

        try await database.write { db in
            try OME.Participant
                .find(participantID("artist-one", eventID: "testival-2026", organizerID: organizerID))
                .update { $0.name = "Updated Artist One" }
                .execute(db)
        }

        let withParticipantChange = try await withDependencies {
            $0.defaultBaselineDatabase = baselineDatabase
        } operation: {
            try await database.read { db in
                try EventEditSummaryRequest(eventID: openedEventID).fetch(db)
            }
        }

        #expect(withParticipantChange.eventID == openedEventID)
        #expect(withParticipantChange.availability == .available)
        #expect(withParticipantChange.totalCount == 2)
        let participantGroup = try #require(
            withParticipantChange.groups.first { $0.id == OME.Participant.tableName }
        )
        expectNoDifference(
            participantGroup,
            SourceChangeGroup(
                id: OME.Participant.tableName,
                displayName: "Participant",
                added: 0,
                modified: 1,
                deleted: 0
            )
        )
    }

    @Test
    func eventEditSummaryUsesSourceEditingSessionDatabase() async throws {
        let source = try makeSourceRepository()
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let openedEventID = eventID("testival-2026", organizerID: organizerID)
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
        } operation: {
            try await insertion.insert(into: database)
        }

        let session = try withDependencies {
            $0.defaultDatabase = database
            $0.defaultBaselineDatabase = baselineDatabase
            $0.sourceEditingWorkingDatabasePath = workingDatabasePath
        } operation: {
            try #require(try SourceEditingSession.openMusicEvent(eventID: openedEventID))
        }

        try await session.database.write { db in
            try OME.Stage
                .find(stageID("meadow", eventID: "testival-2026", organizerID: organizerID))
                .update { $0.name = "Changed through session" }
                .execute(db)
        }

        let summary = try await withDependencies {
            $0.defaultDatabase = session.database
            $0.defaultBaselineDatabase = baselineDatabase
            $0.sourceEditingSession = session
        } operation: {
            try await session.database.read { db in
                try EventEditSummaryRequest(eventID: openedEventID).fetch(db)
            }
        }

        #expect(summary.availability == .available)
        #expect(summary.totalCount == 1)
        let stageGroup = try #require(
            summary.groups.first { $0.id == OME.Stage.tableName }
        )
        expectNoDifference(
            stageGroup,
            SourceChangeGroup(
                id: OME.Stage.tableName,
                displayName: "Stage",
                added: 0,
                modified: 1,
                deleted: 0
            )
        )
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
                eventID("2025", organizerID: organizerID),
                eventID("2026", organizerID: organizerID),
            ])
        )
        expectNoDifference(
            Set(eventOrganizers.map(\.id.eventID)),
            Set([
                id("2025"),
                id("2026"),
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
    func rejectsInferredEventIDCollisionFromDifferentSource() async throws {
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

        do {
            try await secondInsertion.insert(into: database)
            Issue.record("Expected inferred event ID collision to fail.")
        } catch let error as OME.SourceDatabaseInsertion.Error {
            expectNoDifference(
                error,
                .conflictingInferredEventID(
                    eventID: eventID("2026", organizerID: organizerID),
                    existingSourceKind: .tangled,
                    existingSourceReference: "tangled.org/woody.fm/first-source",
                    incomingSourceKind: .tangled,
                    incomingSourceReference: "tangled.org/woody.fm/second-source"
                )
            )
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
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
            try OME.Event.where { $0.id.eq(eventID("2026", organizerID: organizerID)) }
                .fetchOne(db)
        }
        let sourceProvenance = try await database.read { db in
            try EventSourceProvenanceRecord
                .where { $0.id.eq(eventID("2026", organizerID: organizerID)) }
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
        let performanceParticipantCount = try await database.read { db in
            try OME.Performance.Participants.fetchCount(db)
        }

        #expect(organizerCount == 1)
        #expect(eventCount == 1)
        #expect(eventOrganizerCount == 1)
        #expect(performanceCount == 3)
        #expect(performanceParticipantCount == 2)
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
        let participantPhotoURL = try #require(URL(string: "https://example.com/artist-one.jpg"))
        let source = try makeSourceRepository(
            eventImages: [
                SourceImageAsset(
                    source: .url(eventHeroURL),
                    role: .hero,
                    renderKind: .fullImage,
                    materializationPolicy: .prefetchOnOpen
                )
            ],
            participantImages: [
                SourceImageAsset(
                    source: .url(participantPhotoURL),
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
        let participant = try await database.read { db in
            try OME.Participant.fetchOne(db)
        }
        let blobs = try await database.read { db in
            try LocalImageBlob.fetchAll(db)
        }

        #expect(event?.images?.first?.url == eventHeroURL)
        #expect(participant?.images?.first?.url == participantPhotoURL)
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
        let prefetchedParticipant = try await database.read { db in
            try OME.Participant.fetchOne(db)
        }
        let prefetchedBlobs = try await database.read { db in
            try LocalImageBlob.fetchAll(db)
        }

        let prefetchedHeroURL = try #require(prefetchedEvent?.images?.first?.url)
        #expect(prefetchedHeroURL.isFileURL)
        #expect(prefetchedParticipant?.images?.first?.url == participantPhotoURL)
        #expect(prefetchedBlobs.count == 1)
        expectNoDifference(try Data(contentsOf: prefetchedHeroURL), remoteData)
        expectNoDifference(prefetchedBlobs.first?.data, remoteData)
    }

    @Test
    func cachesLazyRemoteParticipantImagesOnDemand() async throws {
        let participantPhotoURL = try #require(URL(string: "https://example.com/artist-one.jpg"))
        let source = try makeSourceRepository(
            participantImages: [
                SourceImageAsset(
                    source: .url(participantPhotoURL),
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

        let participant = try #require(await database.read { db in
            try OME.Participant.fetchOne(db)
        })
        let originalImage = try #require(participant.images?.first)
        let cacheDirectoryURL = try temporaryDirectoryURL()
        let remoteData = Data("lazy-participant-photo".utf8)

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
                .init(participantID: participant.id)
            )
        }

        let updatedParticipant = try await database.read { db in
            try OME.Participant.fetchOne(db)
        }
        let blobs = try await database.read { db in
            try LocalImageBlob.fetchAll(db)
        }

        let cachedURL = try #require(cachedImage.url)
        let updatedURL = try #require(updatedParticipant?.images?.first?.url)
        #expect(cachedURL.isFileURL)
        #expect(updatedURL == cachedURL)
        expectNoDifference(try Data(contentsOf: cachedURL), remoteData)
        let blob = try #require(blobs.first)
        #expect(blob.parentKind == .participant)
        #expect(blob.parentLocalID == "artist-one")
        #expect(blob.sourceURL == participantPhotoURL)
        expectNoDifference(blob.data, remoteData)
    }

    @Test
    func restoresLazyParticipantImagesFromBlobWhenLocalFileIsMissing() async throws {
        let participantPhotoURL = try #require(URL(string: "https://example.com/artist-one.jpg"))
        let source = try makeSourceRepository(
            participantImages: [
                SourceImageAsset(
                    source: .url(participantPhotoURL),
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

        let participant = try #require(await database.read { db in
            try OME.Participant.fetchOne(db)
        })
        let originalImage = try #require(participant.images?.first)
        let cacheDirectoryURL = try temporaryDirectoryURL()
        let remoteData = Data("lazy-participant-photo".utf8)

        _ = try await withDependencies {
            $0.date.now = testImageCacheDate
            $0.defaultDatabase = database
            $0.lazyImageCache = .live
            $0.localImageFileStore = testLocalImageFileStore(directory: cacheDirectoryURL)
            $0.httpClient = .testClient { _, _, _ in remoteData }
        } operation: {
            @Dependency(\.lazyImageCache) var lazyImageCache
            return try await lazyImageCache.cache(
                originalImage,
                .init(participantID: participant.id)
            )
        }

        let cachedParticipant = try #require(await database.read { db in
            try OME.Participant.fetchOne(db)
        })
        let cachedImage = try #require(cachedParticipant.images?.first)
        let cachedURL = try #require(cachedImage.url)
        try FileManager.default.removeItem(at: cachedURL)

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
                cachedImage,
                .init(participantID: cachedParticipant.id)
            )
        }

        let restoredURL = try #require(restoredImage.url)
        let blobs = try await database.read { db in
            try LocalImageBlob.fetchAll(db)
        }

        #expect(restoredURL.isFileURL)
        #expect(restoredURL != cachedURL)
        #expect(FileManager.default.fileExists(atPath: restoredURL.path))
        expectNoDifference(try Data(contentsOf: restoredURL), remoteData)
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
        #expect(updatedPoster?.image.url == cachedURL)
        let blob = try #require(blobs.first)
        #expect(blob.parentKind == .poster)
        #expect(blob.parentLocalID == "lineup")
        expectNoDifference(blob.data, posterData)
    }

    @Test
    func failingLazyImageCacheDoesNotMutateDatabase() async throws {
        let participantPhotoURL = try #require(URL(string: "https://example.com/artist-one.jpg"))
        let source = try makeSourceRepository(
            participantImages: [
                SourceImageAsset(
                    source: .url(participantPhotoURL),
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

        let participant = try #require(await database.read { db in
            try OME.Participant.fetchOne(db)
        })
        let originalImage = try #require(participant.images?.first)
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
                    .init(participantID: participant.id)
                )
            }
            Issue.record("Expected lazy image caching to fail.")
        } catch TestImageCacheError.failed {
        }

        let updatedParticipant = try await database.read { db in
            try OME.Participant.fetchOne(db)
        }
        let blobs = try await database.read { db in
            try LocalImageBlob.fetchAll(db)
        }

        expectNoDifference(updatedParticipant, participant)
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
        eventDirectoryName: String = "testival-2026",
        eventName: String = "Testival 2026",
        explicitLocalEventID: OME.ID<OME.Event>? = nil,
        eventImages: [SourceImageAsset]? = nil,
        stageImages: [SourceImageAsset]? = nil,
        participantImages: [SourceImageAsset]? = nil,
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
        let sourceOrganizerID = try #require(OME.Organizer.ID("did:plc:source"))

        return OpenMusicEventSourceRepository(
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
                            categoryConfigs: nil
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
                        participants: [
                            try FileContent(
                                fileName: "artist-one",
                                fileType: nil,
                                data: ParticipantDTO(
                                    id: nil,
                                    name: "Artist One",
                                    bio: nil,
                                    images: participantImages,
                                    kind: nil,
                                    links: nil
                                )
                            )
                        ],
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
        let fileURL = directory.appending(path: assetKey.replacingOccurrences(of: "|", with: "-"))
        try data.write(to: fileURL, options: .atomic)
        return fileURL
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

private func participantID(
    _ participantID: String,
    eventID: String,
    organizerID: OME.Organizer.ID
) -> OME.Participant.ID {
    OME.Participant.ID(
        organizerID: organizerID,
        eventID: id(eventID),
        participantID: id(participantID)
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
