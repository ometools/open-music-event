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

        let channels = try #require(testival.channels)
        expectNoDifference(
            channels.map(\.fileName),
            [
                "general",
                "safety-info",
            ]
        )

        let channel = try #require(channels.first)
        #expect(channel.fileName == "general")
        #expect(channel.data.id == nil)
        #expect(channel.data.defaultNotificationState == .subscribed)

        let legacyChannel = try #require(channels.first { $0.fileName == "safety-info" })
        #expect(legacyChannel.data.id == nil)
        #expect(legacyChannel.data.name == "Safety Info")
        #expect(legacyChannel.data.iconImageURL?.absoluteString == "https://example.com/safety.png")
        #expect(legacyChannel.data.defaultNotificationState == .unsubscribed)
        #expect(legacyChannel.data.notificationsRequired == false)

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
        expectNoDifference(
            performances[0].contributors,
            [
                ScheduleDTO.Performance.Contributor(
                    subject: .id(OME.ID<OME.Contributor>(.init("artist-one")))
                )
            ]
        )
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
        expectNoDifference(
            performances[1].contributors,
            [
                ScheduleDTO.Performance.Contributor(
                    subject: .name("Guest Artist")
                )
            ]
        )

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
    func readsLegacyCommunicationMarkdownPosts() throws {
        let repositoryURL = try temporaryRepositoryURL()
        let communicationURL = repositoryURL
            .appending(path: "events", directoryHint: .isDirectory)
            .appending(path: "postival-2026", directoryHint: .isDirectory)
            .appending(path: "communications", directoryHint: .isDirectory)
            .appending(path: "general", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: communicationURL,
            withIntermediateDirectories: true
        )
        try """
        name: Postival
        timeZone: America/Denver
        """
        .write(
            to: communicationURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: "event.yml"),
            atomically: true,
            encoding: .utf8
        )
        try """
        name: General
        description: Official updates.
        defaultNotificationState: subscribed
        """
        .write(
            to: communicationURL.appending(path: "channel-info.yaml"),
            atomically: true,
            encoding: .utf8
        )
        try """
        ---
        title: Welcome to Postival
        isPinned: true
        sendPush: true
        headerImageURL: https://example.com/header.png
        ---

        Welcome to the event.
        """
        .write(
            to: communicationURL.appending(path: "welcome.md"),
            atomically: true,
            encoding: .utf8
        )
        try """
        ---
        title: Empty Header
        headerImageURL:
        ---

        Blank header should become nil.
        """
        .write(
            to: communicationURL.appending(path: "empty-header.md"),
            atomically: true,
            encoding: .utf8
        )

        let repository = try OpenMusicEventSourceRepositoryFileTree()
            .read(from: repositoryURL)
            .output
            .requiredValue
        let event = try #require(repository.events.first?.components)
        let posts = try #require(event.communicationPosts?.first?.components)

        expectNoDifference(posts.map(\.fileName), ["empty-header", "welcome"])
        expectNoDifference(posts[0].data.title, "Empty Header")
        expectNoDifference(posts[0].data.headerImageURL, nil)
        expectNoDifference(posts[0].data.isPinned, false)
        expectNoDifference(posts[1].data.title, "Welcome to Postival")
        expectNoDifference(posts[1].data.headerImageURL, URL(string: "https://example.com/header.png")!)
        expectNoDifference(posts[1].data.isPinned, true)
        expectNoDifference(posts[1].data.contents, "Welcome to the event.")
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
        #expect(!contributorText.contains("kind:"))
    }

    @Test
    func inlineSingletonScheduleRoundTripsInEventYAML() throws {
        let tree = OpenMusicEventSourceRepositoryFileTree()
        let eventDate = try #require(LocalDate("2026-08-01"))
        let repository = OpenMusicEventSourceRepository(
            events: [
                DirectoryContent(
                    directoryName: "one-night",
                    components: OpenMusicEventSourceEvent(
                        event: EventDTO(
                            id: nil,
                            name: "One Night",
                            description: nil,
                            startDate: eventDate,
                            endDate: nil,
                            status: .known(.scheduled),
                            mode: .known(.inPerson),
                            locations: nil,
                            uris: nil,
                            timeZone: try #require(TimeZone(identifier: "America/Denver")),
                            images: nil,
                            contactNumbers: nil,
                            categoryConfigs: nil,
                            schedule: InlineScheduleDTO(
                                performances: [
                                    "main": [
                                        ScheduleDTO.Performance(
                                            title: "Opening Set",
                                            startTime: "20:00",
                                            endTime: "21:00"
                                        )
                                    ]
                                ]
                            )
                        )
                    )
                )
            ]
        )
        let outputURL = try temporaryRepositoryURL()

        _ = try tree.write(repository, to: outputURL)
        let writtenRepository = try tree.read(from: outputURL).output.requiredValue

        expectNoDifference(writtenRepository, repository)
        let eventText = try String(
            contentsOf: outputURL
                .appending(path: "events", directoryHint: .isDirectory)
                .appending(path: "one-night", directoryHint: .isDirectory)
                .appending(path: "event.yml"),
            encoding: .utf8
        )
        #expect(eventText.contains("schedule:"))
        #expect(eventText.contains("performances:"))
        #expect(!eventText.contains("  date:"))
        #expect(
            !FileManager.default.fileExists(
                atPath: outputURL
                    .appending(path: "events", directoryHint: .isDirectory)
                    .appending(path: "one-night", directoryHint: .isDirectory)
                    .appending(path: "schedules", directoryHint: .isDirectory)
                    .path()
            )
        )
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
              contributors:
                - actor: WOODY.FM
                - actor: did:plc:actor123
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
            performance.contributors?.map(\.subject),
            [
                .actor(try #require(OME.Contributor.Actor("woody.fm"))),
                .actor(try #require(OME.Contributor.Actor("did:plc:actor123"))),
            ]
        )

        let outputURL = try temporaryRepositoryURL()
        _ = try tree.write(repository, to: outputURL)
        let roundTripped = try tree.read(from: outputURL).output.requiredValue

        expectNoDifference(roundTripped, repository)
    }

    @Test
    func performanceContributorCreditsRoundTripThroughYAML() throws {
        let repositoryURL = try temporaryRepositoryURL()
        let eventURL = repositoryURL
            .appending(path: "events", directoryHint: .isDirectory)
            .appending(path: "credits-event", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: eventURL.appending(path: "stages", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: eventURL.appending(path: "schedules", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )

        try """
        name: Credits Event
        timeZone: America/Denver
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
            - title: Mixed Credits
              startTime: "18:00"
              endTime: "19:00"
              contributors:
                - id: headliner
                - actor: HEADLINER.BSKY.SOCIAL
                  role: dj
                - name: Dance Crew
                  billing: supporting
                  role: dancer
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
        let performance = try #require(
            repository.events.first?.components.schedules?.first?.data.performances["main"]?.first
        )

        expectNoDifference(
            performance.contributors,
            [
                ScheduleDTO.Performance.Contributor(
                    subject: .id(OME.ID<OME.Contributor>(.init("headliner")))
                ),
                ScheduleDTO.Performance.Contributor(
                    subject: .actor(try #require(OME.Contributor.Actor("headliner.bsky.social"))),
                    role: "dj"
                ),
                ScheduleDTO.Performance.Contributor(
                    subject: .name("Dance Crew"),
                    billing: .supporting,
                    role: "dancer"
                ),
            ]
        )

        let outputURL = try temporaryRepositoryURL()
        _ = try tree.write(repository, to: outputURL)
        let roundTripped = try tree.read(from: outputURL).output.requiredValue
        let scheduleText = try String(
            contentsOf: outputURL
                .appending(path: "events", directoryHint: .isDirectory)
                .appending(path: "credits-event", directoryHint: .isDirectory)
                .appending(path: "schedules", directoryHint: .isDirectory)
                .appending(path: "saturday.yml"),
            encoding: .utf8
        )

        expectNoDifference(roundTripped, repository)
        #expect(scheduleText.contains("billing: supporting"))
        #expect(scheduleText.contains("role: dancer"))
        #expect(!scheduleText.contains("billing: primary"))
    }

    @Test
    func legacyPerformanceContributorKeysReadAsCredits() throws {
        let repositoryURL = try temporaryRepositoryURL()
        let eventURL = repositoryURL
            .appending(path: "events", directoryHint: .isDirectory)
            .appending(path: "legacy-credits-event", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: eventURL.appending(path: "stages", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: eventURL.appending(path: "schedules", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )

        try """
        name: Legacy Credits Event
        timeZone: America/Denver
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
            - title: Legacy Credits
              startTime: "18:00"
              endTime: "19:00"
              contributorIDs:
                - headliner
              contributorNames:
                - Dance Crew
              contributorActors:
                - HEADLINER.BSKY.SOCIAL
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
        let performance = try #require(
            repository.events.first?.components.schedules?.first?.data.performances["main"]?.first
        )

        expectNoDifference(
            performance.contributors,
            [
                ScheduleDTO.Performance.Contributor(
                    subject: .id(OME.ID<OME.Contributor>(.init("headliner")))
                ),
                ScheduleDTO.Performance.Contributor(
                    subject: .name("Dance Crew")
                ),
                ScheduleDTO.Performance.Contributor(
                    subject: .actor(try #require(OME.Contributor.Actor("headliner.bsky.social")))
                ),
            ]
        )

        let outputURL = try temporaryRepositoryURL()
        _ = try tree.write(repository, to: outputURL)
        let scheduleText = try String(
            contentsOf: outputURL
                .appending(path: "events", directoryHint: .isDirectory)
                .appending(path: "legacy-credits-event", directoryHint: .isDirectory)
                .appending(path: "schedules", directoryHint: .isDirectory)
                .appending(path: "saturday.yml"),
            encoding: .utf8
        )

        #expect(scheduleText.contains("contributors:"))
        #expect(!scheduleText.contains("contributorIDs:"))
        #expect(!scheduleText.contains("contributorNames:"))
        #expect(!scheduleText.contains("contributorActors:"))
    }

    @Test
    func eventReportingLinkRoundTripsThroughYAML() throws {
        let repositoryURL = try temporaryRepositoryURL()
        let eventURL = repositoryURL
            .appending(path: "events", directoryHint: .isDirectory)
            .appending(path: "reporting-event", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: eventURL,
            withIntermediateDirectories: true
        )

        try """
        name: Reporting Event
        timeZone: America/Denver
        reportingLink:
          name: Report an Incident
          url: https://example.org/report
          description: Use this form to report an event safety concern.
        """
        .write(to: eventURL.appending(path: "event.yml"), atomically: true, encoding: .utf8)

        let tree = OpenMusicEventSourceRepositoryFileTree()
        let repository = try tree.read(from: repositoryURL).output.requiredValue
        let event = try #require(repository.events.first?.components.event)

        expectNoDifference(
            event.reportingLink,
            OME.Event.ReportingLink(
                name: "Report an Incident",
                url: URL(string: "https://example.org/report")!,
                description: "Use this form to report an event safety concern."
            )
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
        expectNoDifference(calendarHero.dimensions, OME.ImageAsset.Dimensions(width: 1600, height: 900))
        expectNoDifference(calendarHero.focalPoint, OME.ImageAsset.FocalPoint(x: 0.35, y: 0.45))
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

    func sourceImagesNormalizeIncompleteAppearancePairs() throws {
        let lightHero = SourceImageAsset(
            source: .url(try #require(URL(string: "https://example.com/light.png"))),
            role: .hero,
            renderKind: .fullImage,
            appearance: .light,
            materializationPolicy: .lazy
        )
        let darkHero = SourceImageAsset(
            source: .url(try #require(URL(string: "https://example.com/dark.png"))),
            role: .hero,
            renderKind: .fullImage,
            appearance: .dark,
            materializationPolicy: .lazy
        )
        let loneDarkLogo = SourceImageAsset(
            source: .url(try #require(URL(string: "https://example.com/logo-dark.png"))),
            role: .logo,
            renderKind: .transparent,
            appearance: .dark,
            materializationPolicy: .lazy
        )

        let normalized = [lightHero, darkHero, loneDarkLogo]
            .normalizingIncompleteAppearancePairs()

        expectNoDifference(
            normalized.map(\.appearance),
            [.light, .dark, nil]
        )
    }

    @Test
    func readsBundledAppearanceSourceImageAssets() throws {
        let repositoryURL = try temporaryRepositoryURL()
        try FileManager.default.createDirectory(
            at: repositoryURL.appending(path: "events", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try """
        name: Appearance Calendar
        images:
        - role: logo
          renderKind: transparent
          materializationPolicy: lazy
          appearances:
            light:
              source:
                file: images/logo-light.png
            dark:
              source:
                file: images/logo-dark.png
        """
            .write(to: repositoryURL.appending(path: "calendar.yml"), atomically: true, encoding: .utf8)

        let repository = try OpenMusicEventSourceRepositoryFileTree()
            .read(from: repositoryURL)
            .output
            .requiredValue
        let calendar = try #require(repository.calendar)
        let logo = try #require(calendar.images?.first)
        let appearances = try #require(logo.appearances)

        expectNoDifference(appearances.light.source, .file("images/logo-light.png"))
        expectNoDifference(appearances.dark.source, .file("images/logo-dark.png"))

        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let draft = calendar.recordDraft(ownerID: organizerID)
        expectNoDifference(
            draft.images?.map(\.appearance),
            [.light, .dark]
        )
        expectNoDifference(draft.images?.count, 2)

        let outputURL = try temporaryRepositoryURL()
        _ = try OpenMusicEventSourceRepositoryFileTree().write(repository, to: outputURL)
        let roundTripped = try OpenMusicEventSourceRepositoryFileTree()
            .read(from: outputURL)
            .output
            .requiredValue
        expectNoDifference(roundTripped.calendar, repository.calendar)
    }

    @Test
    func readsLegacyFlatAppearanceImagePairsAsBundledSourceImageAssets() throws {
        let repositoryURL = try temporaryRepositoryURL()
        try FileManager.default.createDirectory(
            at: repositoryURL.appending(path: "events", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try """
        name: Legacy Appearance Calendar
        images:
        - role: logo
          renderKind: transparent
          appearance: light
          materializationPolicy: lazy
          source:
            file: images/logo-light.png
        - role: logo
          renderKind: transparent
          appearance: dark
          materializationPolicy: lazy
          source:
            file: images/logo-dark.png
        """
            .write(to: repositoryURL.appending(path: "calendar.yml"), atomically: true, encoding: .utf8)

        let repository = try OpenMusicEventSourceRepositoryFileTree()
            .read(from: repositoryURL)
            .output
            .requiredValue
        let calendar = try #require(repository.calendar)
        let bundledImages = try #require(calendar.images?.bundlingAppearancePairs())
        let logo = try #require(bundledImages.first)
        let appearances = try #require(logo.appearances)

        expectNoDifference(bundledImages.count, 1)
        expectNoDifference(appearances.light.source, .file("images/logo-light.png"))
        expectNoDifference(appearances.dark.source, .file("images/logo-dark.png"))
    }

    @Test
    func sourceImagesBundleFlatRuntimeAppearancePairs() throws {
        let lightURL = try #require(URL(string: "https://example.com/logo-light.png"))
        let darkURL = try #require(URL(string: "https://example.com/logo-dark.png"))
        let sourceImages = [
            OME.ImageAsset(
                source: .url(lightURL),
                role: .logo,
                renderKind: .transparent,
                appearance: .light,
                materializationPolicy: .lazy
            ),
            OME.ImageAsset(
                source: .url(darkURL),
                role: .logo,
                renderKind: .transparent,
                appearance: .dark,
                materializationPolicy: .lazy
            ),
        ]
        .sourceImageAssets()

        let sourceImage = try #require(sourceImages.first)
        let appearances = try #require(sourceImage.appearances)
        expectNoDifference(sourceImages.count, 1)
        expectNoDifference(appearances.light.source, .url(lightURL))
        expectNoDifference(appearances.dark.source, .url(darkURL))
    }

    @Test
    func incompleteAppearanceSourceImageFallsBackToStandard() throws {
        let sourceImages = [
            SourceImageAsset(
                source: .url(try #require(URL(string: "https://example.com/logo-light.png"))),
                role: .logo,
                renderKind: .transparent,
                appearance: .light,
                materializationPolicy: .lazy
            )
        ]

        let image = try #require(sourceImages.recordImageAssets().first)
        expectNoDifference(image.appearance, nil)
    }

    @Test
    func contributorMarkdownWriteEmitsFrontMatterAndBody() throws {
        let contributor = try contributorFile(
            name: "Artist One",
            did: try #require(DID("did:plc:artist123")),
            bio: "Artist One writes markdown."
        )

        let printed = try ContributorMarkdownConversion().unapply(contributor)
        let text = String(decoding: printed.data, as: UTF8.self)

        #expect(text.hasPrefix("---\n"))
        #expect(text.contains("name: Artist One"))
        #expect(text.contains("did: did:plc:artist123"))
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
        let printedText = String(decoding: printed.data, as: UTF8.self)
        #expect(!printedText.contains("bio:"))
        #expect(!printedText.contains("kind:"))
    }

    @Test
    func contributorMarkdownRewriteKeepsUnchangedSourceBytes() throws {
        let directoryURL = try temporaryRepositoryURL()
        let original = """
        ---
        name: Artist One
        images:
        - source:
            url: https://example.com/artist-one.png?alt=media&token=fixture
          role: photo
          renderKind: fullImage
          materializationPolicy: lazy
        ---
        Artist One keeps hand-wrapped markdown.
        """
        try original.write(
            to: directoryURL.appending(path: "artist-one.md"),
            atomically: true,
            encoding: .utf8
        )

        let tree = File.Many(withExtension: "md")
            .map(ContributorMarkdownConversion())
        let readResult = try tree.read(from: directoryURL)
        let contributor = try #require(readResult.output.requiredValue.first)

        _ = try tree.rewrite([contributor], at: directoryURL)

        let rewritten = try String(
            contentsOf: directoryURL.appending(path: "artist-one.md"),
            encoding: .utf8
        )
        expectNoDifference(rewritten, original)
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
        did: DID? = nil,
        bio: String?
    ) throws -> FileContent<ContributorDTO> {
        try FileContent(
            fileName: "artist-one",
            fileType: "md",
            data: ContributorDTO(
                name: name,
                did: did,
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
          dimensions:
            width: 1600
            height: 900
          focalPoint:
            x: 0.35
            y: 0.45
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
