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
    func calendarGeneratorOmitsLocalOnlyBinaryImageFiles() async throws {
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

        let change = try #require(patch.fileChanges.first)
        #expect(patch.fileChanges.count == 1)
        #expect(change.path == "calendar.yml")
        let newContents = try #require(change.newContents)
        let newText = String(decoding: newContents, as: UTF8.self)
        #expect(newText.contains("name: New Calendar"))
        #expect(!newText.contains("images:"))
        #expect(!newText.contains("file:"))
        #expect(!newText.contains("file://"))
        #expect(!newText.contains("local-image-cache"))
    }

    @Test
    func liveConversionUpdatesParticipantMarkdownFromDatabase() async throws {
        let fixture = try OpenMusicEventSourcePatchGenerationFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile(
            "events/test-event/event.yml",
            contents: "name: Test Event\ntimeZone: GMT\n"
        )
        try fixture.writeFile(
            "events/test-event/participants/artist-one.md",
            contents: """
            ---
            name: Artist One
            ---
            Old bio.
            """
        )
        let database = try makePreparedDatabase()
        let eventID = testEventID("test-event")
        let participantID = OME.Participant.ID(
            organizerID: eventID.organizerID,
            eventID: eventID.eventID,
            participantID: localID("artist-one")
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
            try OME.Participant.insert {
                OME.Participant.Draft(
                    id: participantID,
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
        #expect(change.path == "events/test-event/participants/artist-one.md")
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
            try OME.Performance.Participants.insert {
                OME.Performance.Participants.Draft(
                    organizerID: eventID.organizerID,
                    eventID: eventID.eventID,
                    performanceID: performanceID.performanceID,
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
        #expect(!newText.contains("Old Set"))
    }

    @Test
    func liveConversionPreservesScheduleDerivedParticipantsInScheduleYaml() async throws {
        let fixture = try OpenMusicEventSourcePatchGenerationFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile(
            "events/test-event/event.yml",
            contents: """
            name: Test Event
            timeZone: GMT
            policies:
              participants:
                listing:
                  type: scheduleParticipants
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
        let participantID = OME.Participant.ID(
            organizerID: eventID.organizerID,
            eventID: eventID.eventID,
            participantID: localID("schedule-name-Guest%20Artist")
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
                    policies: scheduleParticipantListingPolicy()
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
            try OME.Participant.insert {
                OME.Participant.Draft(
                    id: participantID,
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
            try OME.Performance.Participants.insert {
                OME.Performance.Participants.Draft(
                    organizerID: eventID.organizerID,
                    eventID: eventID.eventID,
                    performanceID: performanceID.performanceID,
                    participantID: participantID.participantID,
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

        #expect(!patch.fileChanges.contains { $0.path.contains("/participants/") })
        let change = try #require(
            patch.fileChanges.first { $0.path == "events/test-event/schedules/saturday.yml" }
        )
        #expect(change.path == "events/test-event/schedules/saturday.yml")
        #expect(change.kind == .modified)
        let newContents = try #require(change.newContents)
        let newText = String(decoding: newContents, as: UTF8.self)
        #expect(newText.contains("participantNames:"))
        #expect(newText.contains("Guest Artist"))
        #expect(!newText.contains("participantIDs:"))
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
}

private func testEventID(_ string: String) -> OME.Event.ID {
    OME.Event.ID(
        organizerID: OME.Organizer.ID("did:plc:sourcepatch")!,
        eventID: OME.ID<OME.Event>(.init(string))
    )
}

private func localID<Record>(_ string: String) -> OME.ID<Record> {
    OME.ID<Record>(.init(string))
}

private func scheduleParticipantListingPolicy() -> OME.Event.Policies {
    OME.Event.Policies(
        participants: .init(
            listing: .known(.scheduleParticipants)
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
