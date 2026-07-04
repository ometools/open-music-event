import ATProto
import Dependencies
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSourceEditing
import SourceEditing
import SQLiteData
import Testing

struct OpenMusicEventSourcePatchGenerationTests {
    @Test
    func generatorReadsExistingSourceAndUsesConversion() async throws {
        let fixture = try OpenMusicEventSourcePatchGenerationFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile(
            "events/test-event/event.yml",
            contents: """
            name: Old Event
            timeZone: UTC
            """
        )
        let database = try makePreparedDatabase()
        let eventID = testEventID("test-event")
        let repositoryURL = fixture.repositoryURL
        let sourceReference = repositoryURL.path
        let workingRootURL = fixture.rootURL

        try await database.write { db in
            try OME.Organizer.insert {
                OME.Organizer.Draft(id: eventID.organizerID)
            }
            .execute(db)
            try OME.Event.insert {
                OME.Event.Draft(
                    id: eventID,
                    name: "Old Event",
                    description: nil,
                    startDate: nil,
                    endDate: nil,
                    status: nil,
                    mode: nil,
                    locations: nil,
                    uris: nil,
                    timeZone: TimeZone(identifier: "UTC")!,
                    images: nil,
                    contactNumbers: nil,
                    categoryConfigs: nil
                )
            }
            .execute(db)
            try EventSourceProvenanceRecord.insert {
                EventSourceProvenanceRecord(
                    id: eventID,
                    sourceKind: .local,
                    sourceReference: sourceReference,
                    ref: nil,
                    eventIDOrigin: .inferred,
                    sourceEventDirectory: "test-event"
                )
            }
            .execute(db)
        }

        let patch = try await withDependencies {
            $0.defaultDatabase = database
            $0.uuid = .incrementing
            $0.sourceWorkingTreeMaterializer = .live(
                temporaryDirectoryURL: workingRootURL
            )
            $0.openMusicEventSourcePatchConversion = OpenMusicEventSourcePatchConversion {
                sourceEvent,
                _ in
                var sourceEvent = sourceEvent
                sourceEvent.event.name = "New Event"
                return sourceEvent
            }
            $0[SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self] = .openMusicEvent
        } operation: {
            @Dependency(SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self) var generator
            return try await generator.generate(
                OpenMusicEventSourcePatchRequest(eventID: eventID)
            )
        }

        let change = try #require(patch.fileChanges.first)
        #expect(patch.fileChanges.count == 1)
        #expect(change.path == "events/test-event/event.yml")
        #expect(change.kind == .modified)
        let newContents = try #require(change.newContents)
        #expect(String(decoding: newContents, as: UTF8.self).contains("name: New Event"))

        let originalContents = try String(
            contentsOf: repositoryURL
                .appending(path: "events/test-event/event.yml"),
            encoding: .utf8
        )
        #expect(originalContents.contains("name: Old Event"))
    }

    @Test
    func generatorAddsEventYamlForSourceBackedNewEventDirectory() async throws {
        let fixture = try OpenMusicEventSourcePatchGenerationFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile(
            "events/2025/event.yml",
            contents: """
            name: Wicked Woods 2025
            timeZone: America/Denver
            """
        )
        let database = try makePreparedDatabase()
        let source = localSourceProvenance(repositoryURL: fixture.repositoryURL)
        let sourceBaseline = SourceBaselineRecord(
            source: source,
            databaseFileName: "baseline.sqlite",
            importedAt: Date(timeIntervalSince1970: 1)
        )
        let eventID = sourceBackedEventID(
            source: source,
            sourceEventDirectory: "2026"
        )
        let repositoryURL = fixture.repositoryURL
        let workingRootURL = fixture.rootURL

        try await database.write { db in
            try OME.Organizer.insert {
                OME.Organizer.Draft(id: eventID.organizerID)
            }
            .execute(db)
            try SourceBaselineRecord.insert {
                sourceBaseline
            }
            .execute(db)
            try OME.Event.insert {
                OME.Event.Draft(
                    id: eventID,
                    name: "Wicked Woods 2026",
                    description: nil,
                    startDate: nil,
                    endDate: nil,
                    status: .known(.planned),
                    mode: .known(.inPerson),
                    locations: nil,
                    uris: nil,
                    timeZone: TimeZone(identifier: "America/Denver")!,
                    images: nil,
                    contactNumbers: nil,
                    categoryConfigs: nil
                )
            }
            .execute(db)
            try EventSourceProvenanceRecord.insert {
                EventSourceProvenanceRecord(
                    id: eventID,
                    sourceBaselineID: sourceBaseline.id,
                    sourceKind: source.kind,
                    sourceReference: source.reference,
                    ref: source.ref,
                    eventIDOrigin: .inferred,
                    sourceEventDirectory: "2026"
                )
            }
            .execute(db)
        }

        let patch = try await withDependencies {
            $0.defaultDatabase = database
            $0.uuid = .incrementing
            $0.sourceWorkingTreeMaterializer = .live(
                temporaryDirectoryURL: workingRootURL
            )
            $0.openMusicEventSourcePatchConversion = .live
            $0[SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self] = .openMusicEvent
        } operation: {
            @Dependency(SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self) var generator
            return try await generator.generate(
                OpenMusicEventSourcePatchRequest(eventID: eventID)
            )
        }

        let change = try #require(patch.fileChanges.first)
        #expect(patch.fileChanges.count == 1)
        #expect(change.path == "events/2026/event.yml")
        #expect(change.kind == .added)
        let newContents = try #require(change.newContents)
        let newText = String(decoding: newContents, as: UTF8.self)
        #expect(newText.contains("name: Wicked Woods 2026"))
        #expect(newText.contains("timeZone: America/Denver"))
        #expect(!FileManager.default.fileExists(atPath: repositoryURL.appending(path: "events/2026").path))
        let unchangedContents = try String(
            contentsOf: repositoryURL.appending(path: "events/2025/event.yml"),
            encoding: .utf8
        )
        #expect(unchangedContents.contains("name: Wicked Woods 2025"))
    }

    @Test
    func generatorAddsHydratedSourceBackedNewEventDirectoryFiles() async throws {
        let fixture = try OpenMusicEventSourcePatchGenerationFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile(
            "events/2025/event.yml",
            contents: """
            name: Wicked Woods 2025
            timeZone: America/Denver
            """
        )
        let database = try makePreparedDatabase()
        let source = localSourceProvenance(repositoryURL: fixture.repositoryURL)
        let sourceBaseline = SourceBaselineRecord(
            source: source,
            databaseFileName: "baseline.sqlite",
            importedAt: Date(timeIntervalSince1970: 1)
        )
        let eventID = sourceBackedEventID(
            source: source,
            sourceEventDirectory: "2026"
        )
        let scheduleDate = try #require(LocalDate("2026-08-01"))
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let stageID = OME.Stage.ID(
            organizerID: eventID.organizerID,
            eventID: eventID.eventID,
            stageID: localID("main-stage")
        )
        let contributorID = OME.Contributor.ID(
            organizerID: eventID.organizerID,
            eventID: eventID.eventID,
            contributorID: localID("artist-one")
        )
        let posterID = OME.Poster.ID(
            organizerID: eventID.organizerID,
            eventID: eventID.eventID,
            posterID: localID("lineup")
        )
        let scheduleID = OME.Schedule.ID(
            organizerID: eventID.organizerID,
            eventID: eventID.eventID,
            scheduleID: localID("saturday")
        )
        let performanceID = OME.Performance.ID(
            organizerID: eventID.organizerID,
            eventID: eventID.eventID,
            performanceID: localID("saturday-main-stage-1")
        )
        let performanceStart = try #require(scheduleDate.at(hour: 20, in: timeZone))
        let performanceEnd = try #require(scheduleDate.at(hour: 21, minute: 30, in: timeZone))
        let repositoryURL = fixture.repositoryURL
        let workingRootURL = fixture.rootURL
        let contributorDID = try #require(DID("did:plc:artist123"))

        try await database.write { db in
            try OME.Organizer.insert {
                OME.Organizer.Draft(id: eventID.organizerID)
            }
            .execute(db)
            try SourceBaselineRecord.insert {
                sourceBaseline
            }
            .execute(db)
            try OME.Event.insert {
                OME.Event.Draft(
                    id: eventID,
                    name: "Wicked Woods 2026",
                    description: "Hydrated from app editors.",
                    startDate: scheduleDate,
                    endDate: scheduleDate,
                    status: .known(.planned),
                    mode: .known(.inPerson),
                    locations: nil,
                    uris: nil,
                    timeZone: timeZone,
                    images: nil,
                    contactNumbers: nil,
                    categoryConfigs: nil
                )
            }
            .execute(db)
            try OME.Stage.insert {
                OME.Stage.Draft(
                    id: stageID,
                    name: "Main Stage",
                    color: 0x00bbcc,
                    sortIndex: 1
                )
            }
            .execute(db)
            try OME.Contributor.insert {
                OME.Contributor.Draft(
                    id: contributorID,
                    name: "Artist One",
                    did: contributorDID,
                    bio: "Forest set.",
                    images: nil,
                    kind: nil,
                    links: nil
                )
            }
            .execute(db)
            try OME.Poster.insert {
                OME.Poster.Draft(
                    id: posterID,
                    title: "Lineup",
                    imageURL: URL(string: "https://example.com/wicked-woods-2026-lineup.png")!
                )
            }
            .execute(db)
            try OME.Schedule.insert {
                OME.Schedule.Draft(
                    id: scheduleID,
                    date: scheduleDate,
                    startsAt: nil,
                    endsAt: nil,
                    customTitle: "Saturday"
                )
            }
            .execute(db)
            try OME.Performance.insert {
                OME.Performance.Draft(
                    id: performanceID,
                    stageID: stageID.stageID,
                    scheduleID: scheduleID.scheduleID,
                    startTime: performanceStart,
                    endTime: performanceEnd,
                    title: "Artist One",
                    description: "Main stage set.",
                    recordings: []
                )
            }
            .execute(db)
            try OME.Performance.Contributors.insert {
                OME.Performance.Contributors.Draft(
                    performanceID: performanceID,
                    contributorID: contributorID.contributorID,
                    anonymousName: nil,
                    contributorActor: OME.Contributor.Actor("did:plc:artist123")
                )
            }
            .execute(db)
            try EventSourceProvenanceRecord.insert {
                EventSourceProvenanceRecord(
                    id: eventID,
                    sourceBaselineID: sourceBaseline.id,
                    sourceKind: source.kind,
                    sourceReference: source.reference,
                    ref: source.ref,
                    eventIDOrigin: .inferred,
                    sourceEventDirectory: "2026"
                )
            }
            .execute(db)
        }

        let patch = try await withDependencies {
            $0.defaultDatabase = database
            $0.uuid = .incrementing
            $0.sourceWorkingTreeMaterializer = .live(
                temporaryDirectoryURL: workingRootURL
            )
            $0.openMusicEventSourcePatchConversion = .live
            $0[SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self] = .openMusicEvent
        } operation: {
            @Dependency(SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self) var generator
            return try await generator.generate(
                OpenMusicEventSourcePatchRequest(eventID: eventID)
            )
        }

        let paths = patch.fileChanges.map(\.path).sorted()
        #expect(paths == [
            "events/2026/contributors/artist-one.md",
            "events/2026/event.yml",
            "events/2026/posters/lineup.yml",
            "events/2026/schedules/saturday.yml",
            "events/2026/stages/main-stage.yml",
        ])
        #expect(patch.fileChanges.allSatisfy { $0.kind == .added })
        let eventText = String(
            decoding: try #require(
                patch.fileChanges.first { $0.path == "events/2026/event.yml" }?.newContents
            ),
            as: UTF8.self
        )
        let scheduleText = String(
            decoding: try #require(
                patch.fileChanges.first { $0.path == "events/2026/schedules/saturday.yml" }?.newContents
            ),
            as: UTF8.self
        )
        let contributorText = String(
            decoding: try #require(
                patch.fileChanges.first { $0.path == "events/2026/contributors/artist-one.md" }?.newContents
            ),
            as: UTF8.self
        )
        let posterText = String(
            decoding: try #require(
                patch.fileChanges.first { $0.path == "events/2026/posters/lineup.yml" }?.newContents
            ),
            as: UTF8.self
        )
        #expect(eventText.contains("name: Wicked Woods 2026"))
        #expect(contributorText.contains("did: did:plc:artist123"))
        #expect(contributorText.contains("Forest set."))
        #expect(!contributorText.contains("bio:"))
        #expect(scheduleText.contains("Artist One"))
        #expect(scheduleText.contains("20:00"))
        #expect(scheduleText.contains("21:30"))
        #expect(scheduleText.contains("contributors:"))
        #expect(scheduleText.contains("id: artist-one"))
        #expect(!scheduleText.contains("contributorActors:"))
        #expect(!scheduleText.contains("contributorIDs:"))
        #expect(posterText.contains("wicked-woods-2026-lineup.png"))
        #expect(!FileManager.default.fileExists(atPath: repositoryURL.appending(path: "events/2026").path))
    }

    @Test
    func liveConversionWritesEventPoliciesFromDatabase() async throws {
        let fixture = try OpenMusicEventSourcePatchGenerationFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile(
            "events/test-event/event.yml",
            contents: """
            name: Test Event
            timeZone: UTC
            """
        )
        let database = try makePreparedDatabase()
        let eventID = testEventID("test-event")
        let repositoryURL = fixture.repositoryURL
        let sourceReference = repositoryURL.path
        let workingRootURL = fixture.rootURL

        try await database.write { db in
            try OME.Organizer.insert {
                OME.Organizer.Draft(id: eventID.organizerID)
            }
            .execute(db)
            try OME.Event.insert {
                OME.Event.Draft(
                    id: eventID,
                    name: "Test Event",
                    description: nil,
                    startDate: nil,
                    endDate: nil,
                    status: nil,
                    mode: nil,
                    locations: nil,
                    uris: nil,
                    timeZone: TimeZone(identifier: "UTC")!,
                    images: nil,
                    contactNumbers: nil,
                    categoryConfigs: nil,
                    policies: scheduleContributorListingPolicy()
                )
            }
            .execute(db)
            try EventSourceProvenanceRecord.insert {
                EventSourceProvenanceRecord(
                    id: eventID,
                    sourceKind: .local,
                    sourceReference: sourceReference,
                    ref: nil,
                    eventIDOrigin: .inferred,
                    sourceEventDirectory: "test-event"
                )
            }
            .execute(db)
        }

        let patch = try await withDependencies {
            $0.defaultDatabase = database
            $0.uuid = .incrementing
            $0.sourceWorkingTreeMaterializer = .live(
                temporaryDirectoryURL: workingRootURL
            )
            $0.openMusicEventSourcePatchConversion = .live
            $0[SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self] = .openMusicEvent
        } operation: {
            @Dependency(SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self) var generator
            return try await generator.generate(
                OpenMusicEventSourcePatchRequest(eventID: eventID)
            )
        }

        let change = try #require(patch.fileChanges.first)
        #expect(patch.fileChanges.count == 1)
        #expect(change.path == "events/test-event/event.yml")
        #expect(change.kind == .modified)
        let newContents = try #require(change.newContents)
        let newText = String(decoding: newContents, as: UTF8.self)
        #expect(newText.contains("policies:"))
        #expect(newText.contains("contributors:"))
        #expect(newText.contains("listing:"))
        #expect(newText.contains("type: scheduleContributors"))
    }

    @Test
    func calendarGeneratorUpdatesRootCalendarYamlFromDatabase() async throws {
        let fixture = try OpenMusicEventSourcePatchGenerationFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile(
            "calendar.yml",
            contents: """
            name: Old Calendar
            description: Old description.
            """
        )
        try fixture.writeFile(
            "events/test-event/event.yml",
            contents: "name: Test Event\ntimeZone: GMT\n"
        )
        let database = try makePreparedDatabase()
        let organizerID = try #require(OME.Organizer.ID("did:plc:sourcepatch"))
        let calendarID = OME.Calendar.ID(
            ownerID: organizerID,
            calendarID: OME.Calendar.defaultID
        )
        let source = localSourceProvenance(repositoryURL: fixture.repositoryURL)
        let sourceBaselineID = SourceBaselineRecord.ID(source: source)
        let workingRootURL = fixture.rootURL

        try await database.write { db in
            try OME.Organizer.insert {
                OME.Organizer.Draft(id: organizerID)
            }
            .execute(db)
            try OME.Calendar.insert {
                OME.Calendar.Draft(
                    id: calendarID,
                    name: "New Calendar",
                    description: "Updated description.",
                    images: [
                        OME.ImageAsset.calendarHero(
                            url: URL(string: "https://example.com/calendar-hero.jpg")!
                        ),
                        OME.ImageAsset.calendarLogo(
                            url: URL(string: "https://example.com/calendar-logo.png")!
                        ),
                    ]
                )
            }
            .execute(db)
            try SourceBaselineRecord.insert {
                SourceBaselineRecord(
                    source: source,
                    databaseFileName: "baseline.sqlite",
                    importedAt: Date(timeIntervalSince1970: 1)
                )
            }
            .execute(db)
        }

        let patch = try await withDependencies {
            $0.defaultDatabase = database
            $0.uuid = .incrementing
            $0.sourceWorkingTreeMaterializer = .live(
                temporaryDirectoryURL: workingRootURL
            )
            $0.openMusicEventCalendarSourcePatchConversion = .live
            $0[SourcePatchGeneratorKey<OpenMusicEventCalendarSourcePatchRequest>.self] = .openMusicEventCalendar
        } operation: {
            @Dependency(SourcePatchGeneratorKey<OpenMusicEventCalendarSourcePatchRequest>.self) var generator
            return try await generator.generate(
                OpenMusicEventCalendarSourcePatchRequest(
                    calendarID: calendarID,
                    sourceBaselineID: sourceBaselineID
                )
            )
        }

        let change = try #require(patch.fileChanges.first)
        #expect(patch.fileChanges.count == 1)
        #expect(change.path == "calendar.yml")
        #expect(change.kind == .modified)
        let newContents = try #require(change.newContents)
        let newText = String(decoding: newContents, as: UTF8.self)
        #expect(newText.contains("name: New Calendar"))
        #expect(newText.contains("description: Updated description."))
        #expect(newText.contains("url: https://example.com/calendar-hero.jpg"))
        #expect(newText.contains("role: hero"))
        #expect(newText.contains("renderKind: fullImage"))
        #expect(newText.contains("url: https://example.com/calendar-logo.png"))
        #expect(newText.contains("role: logo"))
        #expect(newText.contains("renderKind: transparent"))
    }

    @Test
    func calendarGeneratorPreservesSourceFileImageReferences() async throws {
        let fixture = try OpenMusicEventSourcePatchGenerationFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile(
            "calendar.yml",
            contents: """
            name: Old Calendar
            images:
            - source:
                file: images/calendar-logo.png
              role: logo
              renderKind: transparent
              materializationPolicy: prefetchOnOpen
            """
        )
        try fixture.writeFile(
            "images/calendar-logo.png",
            contents: "logo"
        )
        try fixture.writeFile(
            "events/test-event/event.yml",
            contents: "name: Test Event\ntimeZone: GMT\n"
        )
        let database = try makePreparedDatabase()
        let organizerID = try #require(OME.Organizer.ID("did:plc:sourcepatch"))
        let calendarID = OME.Calendar.ID(
            ownerID: organizerID,
            calendarID: OME.Calendar.defaultID
        )
        let materializedImageURL = fixture.rootURL
            .appending(path: "local-image-cache/calendar-logo.png")
        let source = localSourceProvenance(repositoryURL: fixture.repositoryURL)
        let sourceBaselineID = SourceBaselineRecord.ID(source: source)
        let workingRootURL = fixture.rootURL

        try await database.write { db in
            try OME.Organizer.insert {
                OME.Organizer.Draft(id: organizerID)
            }
            .execute(db)
            try OME.Calendar.insert {
                OME.Calendar.Draft(
                    id: calendarID,
                    name: "New Calendar",
                    description: nil,
                    images: [
                        OME.ImageAsset(
                            assetKey: calendarSourceImageAssetKey(
                                organizerID: organizerID,
                                parentLocalID: "self",
                                role: .logo
                            ),
                            source: .url(materializedImageURL),
                            role: .logo,
                            renderKind: .transparent,
                            materializationPolicy: .prefetchOnOpen,
                            focalPoint: OME.ImageAsset.FocalPoint(x: 0.4, y: 0.6)
                        )
                    ]
                )
            }
            .execute(db)
            try SourceBaselineRecord.insert {
                SourceBaselineRecord(
                    source: source,
                    databaseFileName: "baseline.sqlite",
                    importedAt: Date(timeIntervalSince1970: 1)
                )
            }
            .execute(db)
        }

        let patch = try await withDependencies {
            $0.defaultDatabase = database
            $0.uuid = .incrementing
            $0.sourceWorkingTreeMaterializer = .live(
                temporaryDirectoryURL: workingRootURL
            )
            $0.openMusicEventCalendarSourcePatchConversion = .live
            $0[SourcePatchGeneratorKey<OpenMusicEventCalendarSourcePatchRequest>.self] = .openMusicEventCalendar
        } operation: {
            @Dependency(SourcePatchGeneratorKey<OpenMusicEventCalendarSourcePatchRequest>.self) var generator
            return try await generator.generate(
                OpenMusicEventCalendarSourcePatchRequest(
                    calendarID: calendarID,
                    sourceBaselineID: sourceBaselineID
                )
            )
        }

        let change = try #require(patch.fileChanges.first)
        #expect(patch.fileChanges.count == 1)
        #expect(change.path == "calendar.yml")
        let newContents = try #require(change.newContents)
        let newText = String(decoding: newContents, as: UTF8.self)
        #expect(newText.contains("name: New Calendar"))
        #expect(newText.contains("file: images/calendar-logo.png"))
        #expect(newText.contains("focalPoint:"))
        #expect(!newText.contains("assetKey:"))
        #expect(!newText.contains("url:"))
        #expect(!newText.contains("local-image-cache"))
    }

    @Test
    func calendarGeneratorMaterializesLocalOnlyBinaryImageFiles() async throws {
        let fixture = try OpenMusicEventSourcePatchGenerationFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile(
            "calendar.yml",
            contents: "name: Old Calendar\n"
        )
        try fixture.writeFile(
            "events/test-event/event.yml",
            contents: "name: Test Event\ntimeZone: GMT\n"
        )
        let database = try makePreparedDatabase()
        let organizerID = try #require(OME.Organizer.ID("did:plc:sourcepatch"))
        let calendarID = OME.Calendar.ID(
            ownerID: organizerID,
            calendarID: OME.Calendar.defaultID
        )
        let localImageURL = fixture.rootURL
            .appending(path: "local-image-cache/imported-hero.png")
        let imageData = Data([0xff, 0xfe, 0xfd])
        try fixture.writeRootFile("local-image-cache/imported-hero.png", data: imageData)
        let source = localSourceProvenance(repositoryURL: fixture.repositoryURL)
        let sourceBaselineID = SourceBaselineRecord.ID(source: source)
        let workingRootURL = fixture.rootURL

        try await database.write { db in
            try OME.Organizer.insert {
                OME.Organizer.Draft(id: organizerID)
            }
            .execute(db)
            try OME.Calendar.insert {
                OME.Calendar.Draft(
                    id: calendarID,
                    name: "New Calendar",
                    description: nil,
                    images: [
                        OME.ImageAsset(
                            assetKey: calendarSourceImageAssetKey(
                                organizerID: organizerID,
                                parentLocalID: "self",
                                role: .hero
                            ),
                            source: .url(localImageURL),
                            role: .hero,
                            renderKind: .fullImage,
                            materializationPolicy: .lazy
                        )
                    ]
                )
            }
            .execute(db)
            try SourceBaselineRecord.insert {
                SourceBaselineRecord(
                    source: source,
                    databaseFileName: "baseline.sqlite",
                    importedAt: Date(timeIntervalSince1970: 1)
                )
            }
            .execute(db)
        }

        let patch = try await withDependencies {
            $0.defaultDatabase = database
            $0.uuid = .incrementing
            $0.sourceWorkingTreeMaterializer = .live(
                temporaryDirectoryURL: workingRootURL
            )
            $0.openMusicEventCalendarSourcePatchConversion = .live
            $0[SourcePatchGeneratorKey<OpenMusicEventCalendarSourcePatchRequest>.self] = .openMusicEventCalendar
        } operation: {
            @Dependency(SourcePatchGeneratorKey<OpenMusicEventCalendarSourcePatchRequest>.self) var generator
            return try await generator.generate(
                OpenMusicEventCalendarSourcePatchRequest(
                    calendarID: calendarID,
                    sourceBaselineID: sourceBaselineID
                )
            )
        }

        let changesByPath = Dictionary(
            uniqueKeysWithValues: patch.fileChanges.map { ($0.path, $0) }
        )
        #expect(patch.fileChanges.map(\.path).sorted() == [
            "calendar.yml",
            "images/calendar-hero.png",
        ])
        let calendarChange = try #require(changesByPath["calendar.yml"])
        #expect(calendarChange.kind == .modified)
        let newContents = try #require(calendarChange.newContents)
        let newText = String(decoding: newContents, as: UTF8.self)
        #expect(newText.contains("name: New Calendar"))
        #expect(newText.contains("file: images/calendar-hero.png"))
        #expect(!newText.contains("assetKey:"))
        #expect(!newText.contains("file://"))
        #expect(!newText.contains("local-image-cache"))
        let imageChange = try #require(changesByPath["images/calendar-hero.png"])
        #expect(imageChange.kind == .added)
        #expect(imageChange.newContents == imageData)
    }

    @Test
    func liveConversionUpdatesContributorMarkdownFromDatabase() async throws {
        let fixture = try OpenMusicEventSourcePatchGenerationFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile(
            "events/test-event/event.yml",
            contents: "name: Test Event\ntimeZone: GMT\n"
        )
        try fixture.writeFile(
            "events/test-event/contributors/artist-one.md",
            contents: """
            ---
            name: Artist One
            ---
            Old bio.
            """
        )
        let database = try makePreparedDatabase()
        let eventID = testEventID("test-event")
        let contributorID = OME.Contributor.ID(
            organizerID: eventID.organizerID,
            eventID: eventID.eventID,
            contributorID: localID("artist-one")
        )
        let repositoryURL = fixture.repositoryURL
        let workingRootURL = fixture.rootURL

        try await database.write { db in
            try OME.Organizer.insert {
                OME.Organizer.Draft(id: eventID.organizerID)
            }
            .execute(db)
            try OME.Event.insert {
                OME.Event.Draft(
                    id: eventID,
                    name: "Test Event",
                    description: nil,
                    startDate: nil,
                    endDate: nil,
                    status: nil,
                    mode: nil,
                    locations: nil,
                    uris: nil,
                    timeZone: TimeZone(identifier: "GMT")!,
                    images: nil,
                    contactNumbers: nil,
                    categoryConfigs: nil
                )
            }
            .execute(db)
            try OME.Contributor.insert {
                OME.Contributor.Draft(
                    id: contributorID,
                    name: "Artist One",
                    bio: "New bio."
                )
            }
            .execute(db)
            try EventSourceProvenanceRecord.insert {
                EventSourceProvenanceRecord(
                    id: eventID,
                    sourceKind: .local,
                    sourceReference: repositoryURL.path,
                    ref: nil,
                    eventIDOrigin: .inferred,
                    sourceEventDirectory: "test-event"
                )
            }
            .execute(db)
        }

        let patch = try await withDependencies {
            $0.defaultDatabase = database
            $0.uuid = .incrementing
            $0.sourceWorkingTreeMaterializer = .live(
                temporaryDirectoryURL: workingRootURL
            )
            $0.openMusicEventSourcePatchConversion = .live
            $0[SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self] = .openMusicEvent
        } operation: {
            @Dependency(SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self) var generator
            return try await generator.generate(
                OpenMusicEventSourcePatchRequest(eventID: eventID)
            )
        }

        let change = try #require(patch.fileChanges.first)
        #expect(patch.fileChanges.count == 1)
        #expect(change.path == "events/test-event/contributors/artist-one.md")
        #expect(change.kind == .modified)
        let newContents = try #require(change.newContents)
        let newText = String(decoding: newContents, as: UTF8.self)
        #expect(newText.contains("name: Artist One"))
        #expect(newText.contains("New bio."))
        #expect(!newText.contains("Old bio."))
        #expect(!newText.contains("bio:"))
    }

    @Test
    func liveConversionUpdatesEventYamlFromDatabase() async throws {
        let fixture = try OpenMusicEventSourcePatchGenerationFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile(
            "events/test-event/event.yml",
            contents: "name: Old Event\ntimeZone: GMT\n"
        )
        let database = try makePreparedDatabase()
        let eventID = testEventID("test-event")
        let repositoryURL = fixture.repositoryURL
        let workingRootURL = fixture.rootURL

        try await database.write { db in
            try OME.Organizer.insert {
                OME.Organizer.Draft(id: eventID.organizerID)
            }
            .execute(db)
            try OME.Event.insert {
                OME.Event.Draft(
                    id: eventID,
                    name: "New Event",
                    description: "Updated from the database.",
                    startDate: nil,
                    endDate: nil,
                    status: nil,
                    mode: nil,
                    locations: nil,
                    uris: nil,
                    timeZone: TimeZone(identifier: "GMT")!,
                    images: nil,
                    contactNumbers: nil,
                    categoryConfigs: nil
                )
            }
            .execute(db)
            try EventSourceProvenanceRecord.insert {
                EventSourceProvenanceRecord(
                    id: eventID,
                    sourceKind: .local,
                    sourceReference: repositoryURL.path,
                    ref: nil,
                    eventIDOrigin: .inferred,
                    sourceEventDirectory: "test-event"
                )
            }
            .execute(db)
        }

        let patch = try await withDependencies {
            $0.defaultDatabase = database
            $0.uuid = .incrementing
            $0.sourceWorkingTreeMaterializer = .live(
                temporaryDirectoryURL: workingRootURL
            )
            $0.openMusicEventSourcePatchConversion = .live
            $0[SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self] = .openMusicEvent
        } operation: {
            @Dependency(SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self) var generator
            return try await generator.generate(
                OpenMusicEventSourcePatchRequest(eventID: eventID)
            )
        }

        let change = try #require(patch.fileChanges.first)
        #expect(patch.fileChanges.count == 1)
        #expect(change.path == "events/test-event/event.yml")
        #expect(change.kind == .modified)
        let newContents = try #require(change.newContents)
        let newText = String(decoding: newContents, as: UTF8.self)
        #expect(newText.contains("name: New Event"))
        #expect(newText.contains("description: Updated from the database."))
    }

    @Test
    func liveConversionUpdatesStageYamlFromDatabase() async throws {
        let fixture = try OpenMusicEventSourcePatchGenerationFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile(
            "events/test-event/event.yml",
            contents: "name: Test Event\ntimeZone: GMT\n"
        )
        try fixture.writeFile(
            "events/test-event/stages/meadow.yml",
            contents: "name: Meadow\ncolor: 43758\n"
        )
        let database = try makePreparedDatabase()
        let eventID = testEventID("test-event")
        let stageID = OME.Stage.ID(
            organizerID: eventID.organizerID,
            eventID: eventID.eventID,
            stageID: localID("meadow")
        )
        let repositoryURL = fixture.repositoryURL
        let workingRootURL = fixture.rootURL

        try await database.write { db in
            try OME.Organizer.insert {
                OME.Organizer.Draft(id: eventID.organizerID)
            }
            .execute(db)
            try OME.Event.insert {
                OME.Event.Draft(
                    id: eventID,
                    name: "Test Event",
                    description: nil,
                    startDate: nil,
                    endDate: nil,
                    status: nil,
                    mode: nil,
                    locations: nil,
                    uris: nil,
                    timeZone: TimeZone(identifier: "GMT")!,
                    images: nil,
                    contactNumbers: nil,
                    categoryConfigs: nil
                )
            }
            .execute(db)
            try OME.Stage.insert {
                OME.Stage.Draft(
                    id: stageID,
                    name: "Main Stage",
                    color: 0x00bbcc,
                    sortIndex: 1
                )
            }
            .execute(db)
            try EventSourceProvenanceRecord.insert {
                EventSourceProvenanceRecord(
                    id: eventID,
                    sourceKind: .local,
                    sourceReference: repositoryURL.path,
                    ref: nil,
                    eventIDOrigin: .inferred,
                    sourceEventDirectory: "test-event"
                )
            }
            .execute(db)
        }

        let patch = try await withDependencies {
            $0.defaultDatabase = database
            $0.uuid = .incrementing
            $0.sourceWorkingTreeMaterializer = .live(
                temporaryDirectoryURL: workingRootURL
            )
            $0.openMusicEventSourcePatchConversion = .live
            $0[SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self] = .openMusicEvent
        } operation: {
            @Dependency(SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self) var generator
            return try await generator.generate(
                OpenMusicEventSourcePatchRequest(eventID: eventID)
            )
        }

        let change = try #require(patch.fileChanges.first)
        #expect(patch.fileChanges.count == 1)
        #expect(change.path == "events/test-event/stages/meadow.yml")
        #expect(change.kind == .modified)
        let newContents = try #require(change.newContents)
        let newText = String(decoding: newContents, as: UTF8.self)
        #expect(newText.contains("name: Main Stage"))
        #expect(newText.contains("color: 48076"))
        #expect(newText.contains("sortIndex: 1"))
    }

    @Test
    func liveConversionPreservesSourceFileImageReferences() async throws {
        let fixture = try OpenMusicEventSourcePatchGenerationFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile(
            "events/test-event/event.yml",
            contents: "name: Test Event\ntimeZone: GMT\n"
        )
        try fixture.writeFile(
            "events/test-event/images/meadow-logo.png",
            contents: "image"
        )
        try fixture.writeFile(
            "events/test-event/stages/meadow.yml",
            contents: """
            name: Meadow
            color: 43758
            images:
            - source:
                file: images/meadow-logo.png
              role: logo
              renderKind: transparent
              materializationPolicy: prefetchOnOpen
            """
        )
        let database = try makePreparedDatabase()
        let eventID = testEventID("test-event")
        let stageID = OME.Stage.ID(
            organizerID: eventID.organizerID,
            eventID: eventID.eventID,
            stageID: localID("meadow")
        )
        let materializedImageURL = fixture.rootURL
            .appending(path: "local-image-cache/meadow-logo.png")
        let repositoryURL = fixture.repositoryURL
        let workingRootURL = fixture.rootURL

        try await database.write { db in
            try OME.Organizer.insert {
                OME.Organizer.Draft(id: eventID.organizerID)
            }
            .execute(db)
            try OME.Event.insert {
                OME.Event.Draft(
                    id: eventID,
                    name: "Test Event",
                    description: nil,
                    startDate: nil,
                    endDate: nil,
                    status: nil,
                    mode: nil,
                    locations: nil,
                    uris: nil,
                    timeZone: TimeZone(identifier: "GMT")!,
                    images: nil,
                    contactNumbers: nil,
                    categoryConfigs: nil
                )
            }
            .execute(db)
            try OME.Stage.insert {
                OME.Stage.Draft(
                    id: stageID,
                    name: "Main Meadow",
                    color: 0x00aaee,
                    images: [
                        OME.ImageAsset(
                            assetKey: sourceImageAssetKey(
                                eventID: eventID,
                                parentKind: "stage",
                                parentLocalID: "meadow",
                                role: .logo
                            ),
                            source: .url(materializedImageURL),
                            role: .logo,
                            renderKind: .transparent,
                            materializationPolicy: .prefetchOnOpen,
                            focalPoint: OME.ImageAsset.FocalPoint(x: 0.25, y: 0.75)
                        )
                    ]
                )
            }
            .execute(db)
            try EventSourceProvenanceRecord.insert {
                EventSourceProvenanceRecord(
                    id: eventID,
                    sourceKind: .local,
                    sourceReference: repositoryURL.path,
                    ref: nil,
                    eventIDOrigin: .inferred,
                    sourceEventDirectory: "test-event"
                )
            }
            .execute(db)
        }

        let patch = try await withDependencies {
            $0.defaultDatabase = database
            $0.uuid = .incrementing
            $0.sourceWorkingTreeMaterializer = .live(
                temporaryDirectoryURL: workingRootURL
            )
            $0.openMusicEventSourcePatchConversion = .live
            $0[SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self] = .openMusicEvent
        } operation: {
            @Dependency(SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self) var generator
            return try await generator.generate(
                OpenMusicEventSourcePatchRequest(eventID: eventID)
            )
        }

        let change = try #require(patch.fileChanges.first)
        #expect(patch.fileChanges.count == 1)
        #expect(change.path == "events/test-event/stages/meadow.yml")
        #expect(change.kind == .modified)
        let newContents = try #require(change.newContents)
        let newText = String(decoding: newContents, as: UTF8.self)
        #expect(newText.contains("name: Main Meadow"))
        #expect(newText.contains("file: images/meadow-logo.png"))
        #expect(newText.contains("focalPoint:"))
        #expect(!newText.contains("assetKey:"))
        #expect(!newText.contains("url:"))
        #expect(!newText.contains("local-image-cache"))
    }

    @Test
    func liveConversionMaterializesLocalStageImageFiles() async throws {
        let fixture = try OpenMusicEventSourcePatchGenerationFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile(
            "events/test-event/event.yml",
            contents: "name: Test Event\ntimeZone: GMT\n"
        )
        try fixture.writeFile(
            "events/test-event/stages/meadow.yml",
            contents: "name: Meadow\ncolor: 43758\n"
        )
        let database = try makePreparedDatabase()
        let eventID = testEventID("test-event")
        let stageID = OME.Stage.ID(
            organizerID: eventID.organizerID,
            eventID: eventID.eventID,
            stageID: localID("meadow")
        )
        let localImageURL = fixture.rootURL
            .appending(path: "local-image-cache/meadow-logo.png")
        let imageData = Data([0xff, 0xfe, 0xfd])
        try fixture.writeRootFile("local-image-cache/meadow-logo.png", data: imageData)
        let repositoryURL = fixture.repositoryURL
        let workingRootURL = fixture.rootURL

        try await database.write { db in
            try OME.Organizer.insert {
                OME.Organizer.Draft(id: eventID.organizerID)
            }
            .execute(db)
            try OME.Event.insert {
                OME.Event.Draft(
                    id: eventID,
                    name: "Test Event",
                    description: nil,
                    startDate: nil,
                    endDate: nil,
                    status: nil,
                    mode: nil,
                    locations: nil,
                    uris: nil,
                    timeZone: TimeZone(identifier: "GMT")!,
                    images: nil,
                    contactNumbers: nil,
                    categoryConfigs: nil
                )
            }
            .execute(db)
            try OME.Stage.insert {
                OME.Stage.Draft(
                    id: stageID,
                    name: "Main Meadow",
                    color: 0x00aaee,
                    images: [
                        OME.ImageAsset(
                            assetKey: sourceImageAssetKey(
                                eventID: eventID,
                                parentKind: "stage",
                                parentLocalID: "meadow",
                                role: .logo
                            ),
                            source: .url(localImageURL),
                            role: .logo,
                            renderKind: .transparent,
                            materializationPolicy: .lazy
                        )
                    ]
                )
            }
            .execute(db)
            try EventSourceProvenanceRecord.insert {
                EventSourceProvenanceRecord(
                    id: eventID,
                    sourceKind: .local,
                    sourceReference: repositoryURL.path,
                    ref: nil,
                    eventIDOrigin: .inferred,
                    sourceEventDirectory: "test-event"
                )
            }
            .execute(db)
        }

        let patch = try await withDependencies {
            $0.defaultDatabase = database
            $0.uuid = .incrementing
            $0.sourceWorkingTreeMaterializer = .live(
                temporaryDirectoryURL: workingRootURL
            )
            $0.openMusicEventSourcePatchConversion = .live
            $0[SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self] = .openMusicEvent
        } operation: {
            @Dependency(SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self) var generator
            return try await generator.generate(
                OpenMusicEventSourcePatchRequest(eventID: eventID)
            )
        }

        let changesByPath = Dictionary(
            uniqueKeysWithValues: patch.fileChanges.map { ($0.path, $0) }
        )
        #expect(patch.fileChanges.map(\.path).sorted() == [
            "events/test-event/images/meadow-logo.png",
            "events/test-event/stages/meadow.yml",
        ])
        let stageChange = try #require(changesByPath["events/test-event/stages/meadow.yml"])
        #expect(stageChange.kind == .modified)
        let newContents = try #require(stageChange.newContents)
        let newText = String(decoding: newContents, as: UTF8.self)
        #expect(newText.contains("name: Main Meadow"))
        #expect(newText.contains("file: images/meadow-logo.png"))
        #expect(!newText.contains("assetKey:"))
        #expect(!newText.contains("url:"))
        #expect(!newText.contains("local-image-cache"))
        let imageChange = try #require(changesByPath["events/test-event/images/meadow-logo.png"])
        #expect(imageChange.kind == .added)
        #expect(imageChange.newContents == imageData)
    }

    @Test
    func liveConversionUpdatesPosterYamlFromDatabase() async throws {
        let fixture = try OpenMusicEventSourcePatchGenerationFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile(
            "events/test-event/event.yml",
            contents: "name: Test Event\ntimeZone: GMT\n"
        )
        try fixture.writeFile(
            "events/test-event/posters/lineup.yml",
            contents: """
            title: Old Lineup
            image:
              source:
                url: https://example.com/old-lineup.png
              role: poster
              renderKind: fullImage
              materializationPolicy: lazy
            """
        )
        let database = try makePreparedDatabase()
        let eventID = testEventID("test-event")
        let posterID = OME.Poster.ID(
            organizerID: eventID.organizerID,
            eventID: eventID.eventID,
            posterID: localID("lineup")
        )
        let repositoryURL = fixture.repositoryURL
        let workingRootURL = fixture.rootURL

        try await database.write { db in
            try OME.Organizer.insert {
                OME.Organizer.Draft(id: eventID.organizerID)
            }
            .execute(db)
            try OME.Event.insert {
                OME.Event.Draft(
                    id: eventID,
                    name: "Test Event",
                    description: nil,
                    startDate: nil,
                    endDate: nil,
                    status: nil,
                    mode: nil,
                    locations: nil,
                    uris: nil,
                    timeZone: TimeZone(identifier: "GMT")!,
                    images: nil,
                    contactNumbers: nil,
                    categoryConfigs: nil
                )
            }
            .execute(db)
            try OME.Poster.insert {
                OME.Poster.Draft(
                    id: posterID,
                    title: "Lineup",
                    imageURL: URL(string: "https://example.com/lineup.png")!
                )
            }
            .execute(db)
            try EventSourceProvenanceRecord.insert {
                EventSourceProvenanceRecord(
                    id: eventID,
                    sourceKind: .local,
                    sourceReference: repositoryURL.path,
                    ref: nil,
                    eventIDOrigin: .inferred,
                    sourceEventDirectory: "test-event"
                )
            }
            .execute(db)
        }

        let patch = try await withDependencies {
            $0.defaultDatabase = database
            $0.uuid = .incrementing
            $0.sourceWorkingTreeMaterializer = .live(
                temporaryDirectoryURL: workingRootURL
            )
            $0.openMusicEventSourcePatchConversion = .live
            $0[SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self] = .openMusicEvent
        } operation: {
            @Dependency(SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self) var generator
            return try await generator.generate(
                OpenMusicEventSourcePatchRequest(eventID: eventID)
            )
        }

        let change = try #require(patch.fileChanges.first)
        #expect(patch.fileChanges.count == 1)
        #expect(change.path == "events/test-event/posters/lineup.yml")
        #expect(change.kind == .modified)
        let newContents = try #require(change.newContents)
        let newText = String(decoding: newContents, as: UTF8.self)
        #expect(newText.contains("title: Lineup"))
        #expect(newText.contains("url: https://example.com/lineup.png"))
        #expect(!newText.contains("old-lineup.png"))
    }

    @Test
    func liveConversionUpdatesScheduleYamlFromDatabase() async throws {
        let fixture = try OpenMusicEventSourcePatchGenerationFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile(
            "events/test-event/event.yml",
            contents: "name: Test Event\ntimeZone: GMT\n"
        )
        try fixture.writeFile(
            "events/test-event/stages/meadow.yml",
            contents: "name: Meadow\ncolor: 43758\n"
        )
        try fixture.writeFile(
            "events/test-event/schedules/saturday.yml",
            contents: """
            date: 2026-08-01
            performances:
              meadow:
              - id: main-set
                title: Old Set
                startTime: "18:00"
                endTime: "19:00"
            """
        )
        let database = try makePreparedDatabase()
        let eventID = testEventID("test-event")
        let scheduleDate = try #require(LocalDate("2026-08-01"))
        let timeZone = try #require(TimeZone(identifier: "GMT"))
        let stageID = OME.Stage.ID(
            organizerID: eventID.organizerID,
            eventID: eventID.eventID,
            stageID: localID("meadow")
        )
        let scheduleID = OME.Schedule.ID(
            organizerID: eventID.organizerID,
            eventID: eventID.eventID,
            scheduleID: localID("saturday")
        )
        let performanceID = OME.Performance.ID(
            organizerID: eventID.organizerID,
            eventID: eventID.eventID,
            performanceID: localID("main-set")
        )
        let performanceStart = try #require(scheduleDate.at(hour: 20, in: timeZone))
        let performanceEnd = try #require(scheduleDate.at(hour: 21, minute: 30, in: timeZone))
        let repositoryURL = fixture.repositoryURL
        let workingRootURL = fixture.rootURL

        try await database.write { db in
            try OME.Organizer.insert {
                OME.Organizer.Draft(id: eventID.organizerID)
            }
            .execute(db)
            try OME.Event.insert {
                OME.Event.Draft(
                    id: eventID,
                    name: "Test Event",
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
                )
            }
            .execute(db)
            try OME.Stage.insert {
                OME.Stage.Draft(
                    id: stageID,
                    name: "Meadow",
                    color: 0x00aaee
                )
            }
            .execute(db)
            try OME.Schedule.insert {
                OME.Schedule.Draft(
                    id: scheduleID,
                    date: scheduleDate,
                    startsAt: nil,
                    endsAt: nil,
                    customTitle: nil
                )
            }
            .execute(db)
            try OME.Performance.insert {
                OME.Performance.Draft(
                    id: performanceID,
                    stageID: stageID.stageID,
                    scheduleID: scheduleID.scheduleID,
                    startTime: performanceStart,
                    endTime: performanceEnd,
                    title: "New Set",
                    description: nil,
                    recordings: []
                )
            }
            .execute(db)
            try OME.Performance.Contributors.insert {
                OME.Performance.Contributors.Draft(
                    performanceID: performanceID,
                    anonymousName: "Guest Artist",
                    billing: .supporting,
                    role: "dancer"
                )
            }
            .execute(db)
            try EventSourceProvenanceRecord.insert {
                EventSourceProvenanceRecord(
                    id: eventID,
                    sourceKind: .local,
                    sourceReference: repositoryURL.path,
                    ref: nil,
                    eventIDOrigin: .inferred,
                    sourceEventDirectory: "test-event"
                )
            }
            .execute(db)
        }

        let patch = try await withDependencies {
            $0.defaultDatabase = database
            $0.uuid = .incrementing
            $0.sourceWorkingTreeMaterializer = .live(
                temporaryDirectoryURL: workingRootURL
            )
            $0.openMusicEventSourcePatchConversion = .live
            $0[SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self] = .openMusicEvent
        } operation: {
            @Dependency(SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self) var generator
            return try await generator.generate(
                OpenMusicEventSourcePatchRequest(eventID: eventID)
            )
        }

        let change = try #require(patch.fileChanges.first)
        #expect(patch.fileChanges.count == 1)
        #expect(change.path == "events/test-event/schedules/saturday.yml")
        #expect(change.kind == .modified)
        let newContents = try #require(change.newContents)
        let newText = String(decoding: newContents, as: UTF8.self)
        #expect(newText.contains("New Set"))
        #expect(newText.contains("20:00"))
        #expect(newText.contains("21:30"))
        #expect(newText.contains("Guest Artist"))
        #expect(newText.contains("billing: supporting"))
        #expect(newText.contains("role: dancer"))
        #expect(!newText.contains("billing: primary"))
        #expect(!newText.contains("Old Set"))
    }

    @Test
    func liveConversionPreservesScheduleDerivedContributorsInScheduleYaml() async throws {
        let fixture = try OpenMusicEventSourcePatchGenerationFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile(
            "events/test-event/event.yml",
            contents: """
            name: Test Event
            timeZone: GMT
            policies:
              contributors:
                listing:
                  type: scheduleContributors
            """
        )
        try fixture.writeFile(
            "events/test-event/stages/meadow.yml",
            contents: "name: Meadow\ncolor: 43758\n"
        )
        try fixture.writeFile(
            "events/test-event/schedules/saturday.yml",
            contents: """
            date: 2026-08-01
            performances:
              meadow:
              - id: main-set
                title: Old Set
                startTime: "18:00"
                endTime: "19:00"
            """
        )
        let database = try makePreparedDatabase()
        let eventID = testEventID("test-event")
        let scheduleDate = try #require(LocalDate("2026-08-01"))
        let timeZone = try #require(TimeZone(identifier: "GMT"))
        let stageID = OME.Stage.ID(
            organizerID: eventID.organizerID,
            eventID: eventID.eventID,
            stageID: localID("meadow")
        )
        let scheduleID = OME.Schedule.ID(
            organizerID: eventID.organizerID,
            eventID: eventID.eventID,
            scheduleID: localID("saturday")
        )
        let performanceID = OME.Performance.ID(
            organizerID: eventID.organizerID,
            eventID: eventID.eventID,
            performanceID: localID("main-set")
        )
        let contributorID = OME.Contributor.ID(
            organizerID: eventID.organizerID,
            eventID: eventID.eventID,
            contributorID: localID("schedule-name-Guest%20Artist")
        )
        let performanceStart = try #require(scheduleDate.at(hour: 20, in: timeZone))
        let performanceEnd = try #require(scheduleDate.at(hour: 21, minute: 30, in: timeZone))
        let repositoryURL = fixture.repositoryURL
        let workingRootURL = fixture.rootURL

        try await database.write { db in
            try OME.Organizer.insert {
                OME.Organizer.Draft(id: eventID.organizerID)
            }
            .execute(db)
            try OME.Event.insert {
                OME.Event.Draft(
                    id: eventID,
                    name: "Test Event",
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
                    categoryConfigs: nil,
                    policies: scheduleContributorListingPolicy()
                )
            }
            .execute(db)
            try OME.Stage.insert {
                OME.Stage.Draft(
                    id: stageID,
                    name: "Meadow",
                    color: 0x00aaee
                )
            }
            .execute(db)
            try OME.Schedule.insert {
                OME.Schedule.Draft(
                    id: scheduleID,
                    date: scheduleDate,
                    startsAt: nil,
                    endsAt: nil,
                    customTitle: nil
                )
            }
            .execute(db)
            try OME.Contributor.insert {
                OME.Contributor.Draft(
                    id: contributorID,
                    name: "Guest Artist",
                    bio: nil,
                    images: nil,
                    kind: nil,
                    links: nil
                )
            }
            .execute(db)
            try OME.Performance.insert {
                OME.Performance.Draft(
                    id: performanceID,
                    stageID: stageID.stageID,
                    scheduleID: scheduleID.scheduleID,
                    startTime: performanceStart,
                    endTime: performanceEnd,
                    title: "New Set",
                    description: nil,
                    recordings: []
                )
            }
            .execute(db)
            try OME.Performance.Contributors.insert {
                OME.Performance.Contributors.Draft(
                    performanceID: performanceID,
                    contributorID: contributorID.contributorID,
                    anonymousName: "Guest Artist"
                )
            }
            .execute(db)
            try EventSourceProvenanceRecord.insert {
                EventSourceProvenanceRecord(
                    id: eventID,
                    sourceKind: .local,
                    sourceReference: repositoryURL.path,
                    ref: nil,
                    eventIDOrigin: .inferred,
                    sourceEventDirectory: "test-event"
                )
            }
            .execute(db)
        }

        let patch = try await withDependencies {
            $0.defaultDatabase = database
            $0.uuid = .incrementing
            $0.sourceWorkingTreeMaterializer = .live(
                temporaryDirectoryURL: workingRootURL
            )
            $0.openMusicEventSourcePatchConversion = .live
            $0[SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self] = .openMusicEvent
        } operation: {
            @Dependency(SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self) var generator
            return try await generator.generate(
                OpenMusicEventSourcePatchRequest(eventID: eventID)
            )
        }

        #expect(!patch.fileChanges.contains { $0.path.contains("/contributors/") })
        let change = try #require(
            patch.fileChanges.first { $0.path == "events/test-event/schedules/saturday.yml" }
        )
        #expect(change.path == "events/test-event/schedules/saturday.yml")
        #expect(change.kind == .modified)
        let newContents = try #require(change.newContents)
        let newText = String(decoding: newContents, as: UTF8.self)
        #expect(newText.contains("contributors:"))
        #expect(newText.contains("name: Guest Artist"))
        #expect(newText.contains("Guest Artist"))
        #expect(!newText.contains("contributorIDs:"))
        #expect(!newText.contains("contributorNames:"))
    }

    private func makePreparedDatabase() throws -> any DatabaseWriter {
        try withDependencies {
            $0.context = .test
        } operation: {
            let database = try SQLiteData.defaultDatabase()
            var migrator = DatabaseMigrator()
            OME.DatabaseMigrations.register(into: &migrator)
            try migrator.migrate(database)
            return database
        }
    }
}

private final class OpenMusicEventSourcePatchGenerationFixture {
    let repositoryURL: URL
    let rootURL: URL

    init() throws {
        self.rootURL = FileManager.default.temporaryDirectory
            .appending(path: "OpenMusicEventSourcePatchGenerationTests-\(UUID().uuidString)")
            .standardizedFileURL
        self.repositoryURL = rootURL.appending(path: "repository").standardizedFileURL

        try FileManager.default.createDirectory(
            at: repositoryURL,
            withIntermediateDirectories: true
        )
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func writeFile(_ path: String, contents: String) throws {
        let url = repositoryURL.appending(path: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    func writeRootFile(_ path: String, data: Data) throws {
        let url = rootURL.appending(path: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}

private func testEventID(_ string: String) -> OME.Event.ID {
    OME.Event.ID(
        organizerID: OME.Organizer.ID("did:plc:sourcepatch")!,
        eventID: OME.ID<OME.Event>(.init(string))
    )
}

private func sourceBackedEventID(
    source: OME.SourceDatabaseInsertion.SourceProvenance,
    sourceEventDirectory: String
) -> OME.Event.ID {
    OME.Event.ID(
        organizerID: OME.Organizer.ID("did:plc:sourcepatch")!,
        eventID: OME.SourceDatabaseInsertion.inferredEventID(
            eventDirectoryName: sourceEventDirectory,
            sourceProvenance: source
        )
    )
}

private func localID<Record>(_ string: String) -> OME.ID<Record> {
    OME.ID<Record>(.init(string))
}

private func scheduleContributorListingPolicy() -> OME.Event.Policies {
    OME.Event.Policies(
        contributors: .init(
            listing: .known(.scheduleContributors)
        )
    )
}

private func sourceImageAssetKey(
    eventID: OME.Event.ID,
    parentKind: String,
    parentLocalID: String,
    role: OME.ImageAsset.Role,
    appearance: OME.ImageAsset.Appearance? = nil
) -> String {
    [
        eventID.organizerID.description,
        eventID.eventID.rawValue.rawValue,
        parentKind,
        parentLocalID,
        role.rawValue,
        appearance?.rawValue ?? "default",
    ]
    .joined(separator: "|")
}

private func calendarSourceImageAssetKey(
    organizerID: OME.Organizer.ID,
    parentLocalID: String,
    role: OME.ImageAsset.Role,
    appearance: OME.ImageAsset.Appearance? = nil
) -> String {
    [
        organizerID.description,
        "calendar",
        parentLocalID,
        role.rawValue,
        appearance?.rawValue ?? "default",
    ]
    .joined(separator: "|")
}

private func localSourceProvenance(
    repositoryURL: URL
) -> OME.SourceDatabaseInsertion.SourceProvenance {
    OME.SourceDatabaseInsertion.SourceProvenance(
        kind: .local,
        reference: repositoryURL.path,
        ref: nil
    )
}
