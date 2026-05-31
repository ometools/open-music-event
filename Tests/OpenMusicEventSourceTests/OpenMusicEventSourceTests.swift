import ATProto
import CustomDump
import FileTree
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSource
import Testing

struct OpenMusicEventSourceTests {
    @Test
    func validatesLocalRepositoryAndBuildsInsertion() async throws {
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let result = try await OpenMusicEventSourceValidator(
            OpenMusicEventSourceValidationRequest(
                source: fixtureURL("Organizer").path(),
                organizerID: organizerID
            )
        )
        .validate()

        let resolvedEventIDs = [
            "Organizer-minimal-event",
            "Organizer-testival-2026",
        ]
        expectNoDifference(
            result.summary.events.map(\.eventID),
            resolvedEventIDs
        )
        expectNoDifference(
            result.insertedEventIDs.map(\.eventID.rawValue.rawValue),
            resolvedEventIDs
        )
        expectNoDifference(
            result.insertion.calendars,
            [
                OME.Calendar.Draft(
                    id: OME.Calendar.ID(
                        ownerID: organizerID,
                        calendarID: OME.Calendar.defaultID
                    ),
                    name: "Testival Calendar",
                    description: "Organizer default calendar.",
                    images: nil
                )
            ]
        )
        expectNoDifference(
            result.insertion.calendarEntries.map(\.id?.entryID.rawValue.rawValue),
            resolvedEventIDs
        )
        expectNoDifference(
            result.insertion.eventSourceProvenances.map(\.eventIDOrigin),
            [
                .inferred,
                .inferred,
            ]
        )
        expectNoDifference(
            Set(result.insertion.eventSourceProvenances.map(\.source.reference)),
            [try fixtureURL("Organizer").standardizedFileURL.path()]
        )
        #expect(result.organizerID == organizerID)
    }

    @Test
    func rejectsLocalRepositoryWithoutOrganizerID() async throws {
        do {
            _ = try await OpenMusicEventSourceValidator(
                OpenMusicEventSourceValidationRequest(
                    source: fixtureURL("Organizer").path()
                )
            )
            .validate()
            Issue.record("Expected local source validation to require an organizer ID.")
        } catch OpenMusicEventSourceValidationError.missingOrganizerIDForLocalSource {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func readsOrganizerRepository() throws {
        let repositoryResult = try OpenMusicEventSourceRepositoryFileTree()
            .read(from: fixtureURL("Organizer"))
        let repository = try repositoryResult.output.requiredValue

        expectNoDifference(
            repository.calendar,
            CalendarDTO(
                name: "Testival Calendar",
                description: "Organizer default calendar."
            )
        )
        expectNoDifference(
            repository.events.map(\.directoryName),
            [
                "minimal-event",
                "testival-2026",
            ]
        )

        let testival = try #require(
            repository.events.first { $0.directoryName == "testival-2026" }?.components
        )

        #expect(testival.event.id == nil)
        #expect(testival.event.name == "Testival 2026")
        #expect(testival.event.startDate?.description == "2026-08-01")
        #expect(testival.event.endDate?.description == "2026-08-03")
        #expect(testival.event.timeZone.identifier == "America/Denver")
        expectNoDifference(
            testival.event.images,
            [
                SourceImageAsset(
                    source: .url(URL(string: "https://example.com/event.jpg")!),
                    role: .hero,
                    renderKind: .fullImage,
                    materializationPolicy: .prefetchOnOpen
                ),
                SourceImageAsset(
                    source: .url(URL(string: "https://example.com/icon.png")!),
                    role: .icon,
                    renderKind: .transparent,
                    materializationPolicy: .prefetchOnOpen
                ),
                SourceImageAsset(
                    source: .url(URL(string: "https://example.com/map.png")!),
                    role: .siteMap,
                    renderKind: .fullImage,
                    materializationPolicy: .lazy
                ),
            ]
        )

        let stage = try #require(testival.stages?.first)
        #expect(stage.fileName == "meadow")
        #expect(stage.data.id == nil)
        #expect(stage.data.name == "Meadow")
        #expect(stage.data.color.rawValue == 0x00aaee)
        expectNoDifference(
            stage.data.images,
            [
                SourceImageAsset(
                    source: .url(URL(string: "https://example.com/meadow-icon.png")!),
                    role: .logo,
                    renderKind: .transparent,
                    materializationPolicy: .prefetchOnOpen
                )
            ]
        )

        let contributor = try #require(testival.contributors?.first)
        #expect(contributor.fileName == "artist-one")
        #expect(contributor.data.id == nil)
        #expect(contributor.data.name == "Artist One")
        #expect(contributor.data.bio == "Artist One writes sturdy test fixtures.\n")
        expectNoDifference(
            contributor.data.images,
            [
                SourceImageAsset(
                    source: .url(URL(string: "https://example.com/artist-one.jpg")!),
                    role: .photo,
                    renderKind: .fullImage,
                    materializationPolicy: .lazy
                )
            ]
        )
        #expect(contributor.data.links?.first?.platform == .soundcloud)

        let poster = try #require(testival.posters?.first)
        #expect(poster.fileName == "lineup")
        #expect(poster.data.id == nil)
        expectNoDifference(
            poster.data.image,
            SourceImageAsset(
                source: .url(URL(string: "https://example.com/lineup.png")!),
                role: .poster,
                renderKind: .fullImage,
                materializationPolicy: .lazy
            )
        )

        let channel = try #require(testival.channels?.first)
        #expect(channel.fileName == "general")
        #expect(channel.data.id == nil)
        #expect(channel.data.defaultNotificationState == .subscribed)

        let schedule = try #require(testival.schedules?.first)
        #expect(schedule.fileName == "saturday")
        #expect(schedule.data.id == nil)
        #expect(schedule.data.date.description == "2026-08-01")

        let performances = try #require(schedule.data.performances["meadow"])
        expectNoDifference(
            performances.map(\.id?.rawValue.rawValue),
            [
                "opening-set",
                nil,
                "closing-set",
            ]
        )
        #expect(performances[0].contributorIDs?.first?.rawValue.rawValue == "artist-one")
        expectNoDifference(
            performances[0].recordings,
            [
                ExternalPlatform.Asset(
                    url: URL(string: "https://example.com/opening-set.mp3")!
                ),
                ExternalPlatform.Asset(
                    record: .init(
                        uri: ATProto.URI("at://did:plc:streamer/place.stream.livestream/3k5nobkf2w72g")!,
                        cid: "bafyreibvlzqnyqbyq2xlxzyelbnzczd3i2cppmx7xghg42yyjz7dss6xju"
                    )
                ),
            ]
        )
        #expect(performances[1].contributorNames == ["Guest Artist"])

        let minimal = try #require(
            repository.events.first { $0.directoryName == "minimal-event" }?.components
        )
        #expect(minimal.stages == nil)
        #expect(minimal.contributors == nil)
        #expect(minimal.posters == nil)
        #expect(minimal.schedules == nil)
        #expect(minimal.channels == nil)
    }

    @Test
    func writesOrganizerRepository() throws {
        let tree = OpenMusicEventSourceRepositoryFileTree()
        let repositoryResult = try tree.read(from: fixtureURL("Organizer"))
        let repository = try repositoryResult.output.requiredValue
        let outputURL = try temporaryRepositoryURL()

        _ = try tree.write(repository, to: outputURL)
        let writtenResult = try tree.read(from: outputURL)
        let writtenRepository = try writtenResult.output.requiredValue

        expectNoDifference(writtenRepository, repository)
        let calendarText = try String(
            contentsOf: outputURL.appending(path: "calendar.yml"),
            encoding: .utf8
        )
        #expect(calendarText.contains("name: Testival Calendar"))
        #expect(calendarText.contains("description: Organizer default calendar."))

        let contributorText = try String(
            contentsOf: outputURL
                .appending(path: "events", directoryHint: .isDirectory)
                .appending(path: "testival-2026", directoryHint: .isDirectory)
                .appending(path: "contributors", directoryHint: .isDirectory)
                .appending(path: "artist-one.md"),
            encoding: .utf8
        )
        #expect(contributorText.hasPrefix("---\n"))
        #expect(contributorText.contains("Artist One writes sturdy test fixtures."))
        #expect(!contributorText.contains("bio:"))
    }

    @Test
    func missingCalendarYAMLReadsAsNilAndDoesNotWriteFile() throws {
        let repositoryURL = try temporaryRepositoryURL()
        let eventURL = repositoryURL
            .appending(path: "events", directoryHint: .isDirectory)
            .appending(path: "minimal", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: eventURL,
            withIntermediateDirectories: true
        )
        try """
        name: Minimal
        timeZone: America/Denver
        """
        .write(to: eventURL.appending(path: "event.yml"), atomically: true, encoding: .utf8)

        let tree = OpenMusicEventSourceRepositoryFileTree()
        let repository = try tree.read(from: repositoryURL).output.requiredValue
        let outputURL = try temporaryRepositoryURL()
        try """
        name: Stale Calendar
        """
        .write(to: outputURL.appending(path: "calendar.yml"), atomically: true, encoding: .utf8)

        _ = try $deletingNilOptionalWrites.withValue(true) {
            try tree.write(repository, to: outputURL)
        }
        let writtenRepository = try tree.read(from: outputURL).output.requiredValue

        #expect(repository.calendar == nil)
        expectNoDifference(writtenRepository, repository)
        #expect(!FileManager.default.fileExists(atPath: outputURL.appending(path: "calendar.yml").path()))
    }

    @Test
    func contributorProfilePoliciesAndActorsRoundTrip() throws {
        let repositoryURL = try temporaryRepositoryURL()
        let eventURL = repositoryURL
            .appending(path: "events", directoryHint: .isDirectory)
            .appending(path: "actor-event", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: eventURL.appending(path: "stages", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: eventURL.appending(path: "schedules", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )

        try """
        name: Actor Event
        timeZone: America/Denver
        policies:
          contributors:
            listing:
              type: scheduleContributors
            profile:
              type: actorProfiles
              providers:
                - app.bsky.actor.profile
                - social.example.profile
        """
        .write(to: eventURL.appending(path: "event.yml"), atomically: true, encoding: .utf8)

        try """
        name: Main
        color: "0x00aaee"
        """
        .write(
            to: eventURL
                .appending(path: "stages", directoryHint: .isDirectory)
                .appending(path: "main.yml"),
            atomically: true,
            encoding: .utf8
        )

        try """
        date: 2026-08-01
        performances:
          main:
            - title: Actor Set
              startTime: "18:00"
              endTime: "19:00"
              contributorActors:
                - WOODY.FM
                - did:plc:actor123
        """
        .write(
            to: eventURL
                .appending(path: "schedules", directoryHint: .isDirectory)
                .appending(path: "saturday.yml"),
            atomically: true,
            encoding: .utf8
        )

        let tree = OpenMusicEventSourceRepositoryFileTree()
        let repository = try tree.read(from: repositoryURL).output.requiredValue
        let event = try #require(repository.events.first?.components)

        expectNoDifference(
            event.event.policies,
            OME.Event.Policies(
                contributors: .init(
                    listing: .known(.scheduleContributors),
                    profile: .known(
                        .actorProfiles(
                            .init(
                                providers: [
                                    .known(.bskyActorProfile),
                                    .unknown(.string("social.example.profile")),
                                ]
                            )
                        )
                    )
                )
            )
        )

        let performance = try #require(event.schedules?.first?.data.performances["main"]?.first)
        expectNoDifference(
            performance.contributorActors?.map(\.description),
            [
                "woody.fm",
                "did:plc:actor123",
            ]
        )

        let outputURL = try temporaryRepositoryURL()
        _ = try tree.write(repository, to: outputURL)
        let roundTripped = try tree.read(from: outputURL).output.requiredValue

        expectNoDifference(roundTripped, repository)
    }

    @Test
    func readsSourceImageAssetsFromRepositoryFiles() throws {
        let repositoryURL = try temporaryRepositoryURL()
        try writeImageFixtureRepository(at: repositoryURL)

        let repositoryResult = try OpenMusicEventSourceRepositoryFileTree()
            .read(from: repositoryURL)
        let repository = try repositoryResult.output.requiredValue
        let calendar = try #require(repository.calendar)
        let calendarHero = try #require(calendar.images?.first { $0.role == .hero })
        expectNoDifference(calendarHero.renderKind, .fullImage)
        expectNoDifference(calendarHero.materializationPolicy, .lazy)
        expectNoDifference(calendarHero.source, .url(URL(string: "https://example.com/calendar-hero.jpg")!))
        let calendarLogo = try #require(calendar.images?.first { $0.role == .logo })
        expectNoDifference(calendarLogo.renderKind, .transparent)
        expectNoDifference(calendarLogo.materializationPolicy, .prefetchOnOpen)
        expectNoDifference(calendarLogo.source, .file("images/calendar-logo.png"))

        let event = try #require(repository.events.first?.components)

        let hero = try #require(event.event.images?.first)
        expectNoDifference(hero.role, .hero)
        expectNoDifference(hero.renderKind, .fullImage)
        expectNoDifference(hero.materializationPolicy, .prefetchOnOpen)
        expectNoDifference(hero.source, .url(URL(string: "https://example.com/event-hero.jpg")!))

        let stage = try #require(event.stages?.first)
        let stageLogo = try #require(stage.data.images?.first)
        expectNoDifference(stageLogo.role, .logo)
        expectNoDifference(stageLogo.renderKind, .transparent)
        expectNoDifference(stageLogo.materializationPolicy, .prefetchOnOpen)
        expectNoDifference(stageLogo.source, .file("images/meadow-logo.png"))

        let contributor = try #require(event.contributors?.first)
        let photo = try #require(contributor.data.images?.first)
        expectNoDifference(photo.role, .photo)
        expectNoDifference(photo.renderKind, .fullImage)
        expectNoDifference(photo.materializationPolicy, .lazy)
        expectNoDifference(photo.source, .url(URL(string: "https://example.com/artist-one.jpg")!))

        let outputURL = try temporaryRepositoryURL()
        _ = try OpenMusicEventSourceRepositoryFileTree().write(repository, to: outputURL)
        let roundTripped = try OpenMusicEventSourceRepositoryFileTree()
            .read(from: outputURL)
            .output
            .requiredValue
        expectNoDifference(roundTripped.calendar, repository.calendar)
    }

    @Test
    func contributorMarkdownWriteEmitsFrontMatterAndBody() throws {
        let contributor = try contributorFile(
            name: "Artist One",
            bio: "Artist One writes markdown."
        )

        let printed = try ContributorMarkdownConversion().unapply(contributor)
        let text = String(decoding: printed.data, as: UTF8.self)

        #expect(text.hasPrefix("---\n"))
        #expect(text.contains("name: Artist One"))
        #expect(text.contains("Artist One writes markdown."))
        #expect(!text.contains("bio:"))

        let roundTripped = try ContributorMarkdownConversion().apply(printed)
        expectNoDifference(roundTripped, contributor)
    }

    @Test
    func contributorMarkdownFixtureRoundTripsThroughWriter() throws {
        let contributorURL = try fixtureURL("Organizer")
            .appending(path: "events", directoryHint: .isDirectory)
            .appending(path: "testival-2026", directoryHint: .isDirectory)
            .appending(path: "contributors", directoryHint: .isDirectory)
            .appending(path: "artist-one.md")
        let input = try FileContent(
            fileName: "artist-one",
            fileType: "md",
            data: Data(contentsOf: contributorURL)
        )
        let contributor = try ContributorMarkdownConversion().apply(input)

        let printed = try ContributorMarkdownConversion().unapply(contributor)
        let roundTripped = try ContributorMarkdownConversion().apply(printed)

        expectNoDifference(roundTripped, contributor)
        #expect(!String(decoding: printed.data, as: UTF8.self).contains("bio:"))
    }

    @Test
    func contributorMarkdownRewriteUpdatesBody() throws {
        let directoryURL = try temporaryRepositoryURL()
        try """
        ---
        name: Artist One
        ---
        Old biography.
        """
        .write(to: directoryURL.appending(path: "artist-one.md"), atomically: true, encoding: .utf8)

        let tree = File.Many(withExtension: "md")
            .map(ContributorMarkdownConversion())
        let contributor = try contributorFile(
            name: "Artist One",
            bio: "New biography."
        )

        _ = try tree.rewrite([contributor], at: directoryURL)

        let text = try String(contentsOf: directoryURL.appending(path: "artist-one.md"), encoding: .utf8)
        #expect(text.contains("name: Artist One"))
        #expect(text.contains("New biography."))
        #expect(!text.contains("Old biography."))
        #expect(!text.contains("bio:"))
    }

    @Test
    func contributorMarkdownRewriteWithMetadataChangeStaysReadable() throws {
        let directoryURL = try temporaryRepositoryURL()
        try """
        ---
        name: Old Artist
        ---
        Old biography.
        """
        .write(to: directoryURL.appending(path: "artist-one.md"), atomically: true, encoding: .utf8)

        let tree = File.Many(withExtension: "md")
            .map(ContributorMarkdownConversion())
        let contributor = try contributorFile(
            name: "Artist One",
            bio: "New biography."
        )

        _ = try tree.rewrite([contributor], at: directoryURL)
        let readResult = try tree.read(from: directoryURL)
        let roundTripped = try #require(readResult.output.requiredValue.first)

        expectNoDifference(roundTripped, contributor)
    }

    private func fixtureURL(_ name: String) throws -> URL {
        try #require(
            Bundle.module.url(
                forResource: name,
                withExtension: nil,
                subdirectory: "Fixtures"
            )
        )
    }

    private func temporaryRepositoryURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func contributorFile(
        name: String,
        bio: String?
    ) throws -> FileContent<ContributorDTO> {
        try FileContent(
            fileName: "artist-one",
            fileType: "md",
            data: ContributorDTO(
                name: name,
                bio: bio
            )
        )
    }

    private func writeImageFixtureRepository(at repositoryURL: URL) throws {
        try FileManager.default.createDirectory(
            at: repositoryURL.appending(path: "images", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        let eventURL = repositoryURL
            .appending(path: "events", directoryHint: .isDirectory)
            .appending(path: "image-event", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: eventURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: eventURL.appending(path: "stages", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: eventURL.appending(path: "contributors", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: eventURL.appending(path: "images", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )

        try """
        name: Image Calendar
        description: Calendar image fixture.
        images:
        - source:
            url: https://example.com/calendar-hero.jpg
          role: hero
          renderKind: fullImage
          materializationPolicy: lazy
        - source:
            file: images/calendar-logo.png
          role: logo
          renderKind: transparent
          materializationPolicy: prefetchOnOpen
        """
            .write(to: repositoryURL.appending(path: "calendar.yml"), atomically: true, encoding: .utf8)

        try """
        name: Image Event
        timeZone: America/Denver
        images:
        - source:
            url: https://example.com/event-hero.jpg
          role: hero
          renderKind: fullImage
          materializationPolicy: prefetchOnOpen
        """
            .write(to: eventURL.appending(path: "event.yml"), atomically: true, encoding: .utf8)

        try """
        name: Meadow
        color: "0x00aaee"
        images:
        - source:
            file: images/meadow-logo.png
          role: logo
          renderKind: transparent
          materializationPolicy: prefetchOnOpen
        """
            .write(
                to: eventURL
                    .appending(path: "stages", directoryHint: .isDirectory)
                    .appending(path: "meadow.yml"),
                atomically: true,
                encoding: .utf8
            )

        try """
        ---
        name: Artist One
        images:
        - source:
            url: https://example.com/artist-one.jpg
          role: photo
          renderKind: fullImage
          materializationPolicy: lazy
        ---
        Artist One fixture body.
        """
            .write(
                to: eventURL
                    .appending(path: "contributors", directoryHint: .isDirectory)
                    .appending(path: "artist-one.md"),
                atomically: true,
                encoding: .utf8
            )

        try Data("logo".utf8).write(
            to: eventURL
                .appending(path: "images", directoryHint: .isDirectory)
                .appending(path: "meadow-logo.png")
        )
        try Data("calendar-logo".utf8).write(
            to: repositoryURL
                .appending(path: "images", directoryHint: .isDirectory)
                .appending(path: "calendar-logo.png")
        )
    }
}
