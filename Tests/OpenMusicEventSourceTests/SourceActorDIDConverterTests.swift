import ATProto
import CustomDump
import Dependencies
import FileTree
import Foundation
import OpenMusicEventSource
import Testing

struct SourceActorDIDConverterTests {
    @Test
    func dryRunDiscoversResolvesOverridesAndUnresolvedHandles() async throws {
        let repositoryURL = try temporaryRepositoryURL()
        let scheduleURL = try writeActorFixture(
            at: repositoryURL,
            schedule: """
            date: 2026-08-01
            performances:
              main:
                - title: Actor Set
                  startTime: "18:00"
                  contributorActors:
                    - WOODY.FM
                    - did:plc:actor123
                    - woody.fm
                    - override.example
                    - unresolved.example
            """
        )
        let originalText = try String(contentsOf: scheduleURL, encoding: .utf8)
        let recorder = HandleResolutionRecorder()

        let result = try await withDependencies {
            $0[Atmosphere.Account.Client.self] = .testClient(
                dids: [
                    "woody.fm": "did:plc:woody123",
                ],
                recorder: recorder
            )
        } operation: {
            try await SourceActorDIDConverter().convert(
                SourceActorDIDConversionRequest(
                    repositoryURL: repositoryURL,
                    eventDirectory: "actor-event",
                    overrides: [
                        "override.example": "did:plc:override123",
                    ]
                )
            )
        }

        let resolvedHandles = await recorder.resolvedHandles
        expectNoDifference(
            resolvedHandles.sorted(),
            [
                "unresolved.example",
                "woody.fm",
            ]
        )
        expectNoDifference(
            result.replacements,
            [
                .init(
                    location: actorLocation(actorIndex: 0),
                    handle: "woody.fm",
                    did: "did:plc:woody123",
                    source: .resolved
                ),
                .init(
                    location: actorLocation(actorIndex: 2),
                    handle: "woody.fm",
                    did: "did:plc:woody123",
                    source: .resolved
                ),
                .init(
                    location: actorLocation(actorIndex: 3),
                    handle: "override.example",
                    did: "did:plc:override123",
                    source: .override
                ),
            ]
        )
        expectNoDifference(
            result.unchangedDIDReferences,
            [
                .init(
                    location: actorLocation(actorIndex: 1),
                    did: "did:plc:actor123"
                ),
            ]
        )
        expectNoDifference(
            result.unresolvedHandles.map { "\($0.location.description) \($0.handle)" },
            [
                "\(actorLocation(actorIndex: 4).description) unresolved.example",
            ]
        )
        expectNoDifference(
            result.touchedFiles,
            [
                "events/actor-event/schedules/saturday.yml",
            ]
        )
        #expect(!result.didWrite)
        #expect(try String(contentsOf: scheduleURL, encoding: .utf8) == originalText)
    }

    @Test
    func dryRunDiscoversActorsFromAtmosphereConfStyleScheduleYaml() async throws {
        let repositoryURL = try temporaryRepositoryURL()
        _ = try writeActorFixture(
            at: repositoryURL,
            schedule: """
            date: 2026-08-01
            performances:
              main:
              - title: Actor Set
                startTime: "18:00"
                contributorActors:
                - WOODY.FM
                - did:plc:actor123
              - title: Next Set
                startTime: "19:00"
            """
        )

        let result = try await withDependencies {
            $0[Atmosphere.Account.Client.self] = .testClient(
                dids: [
                    "woody.fm": "did:plc:woody123",
                ]
            )
        } operation: {
            try await SourceActorDIDConverter().convert(
                SourceActorDIDConversionRequest(
                    repositoryURL: repositoryURL,
                    eventDirectory: "actor-event"
                )
            )
        }

        expectNoDifference(
            result.replacements,
            [
                .init(
                    location: actorLocation(actorIndex: 0),
                    handle: "woody.fm",
                    did: "did:plc:woody123",
                    source: .resolved
                ),
            ]
        )
        expectNoDifference(
            result.unchangedDIDReferences,
            [
                .init(
                    location: actorLocation(actorIndex: 1),
                    did: "did:plc:actor123"
                ),
            ]
        )
        expectNoDifference(result.unresolvedHandles, [])
    }

    @Test
    func reportsProgressEvents() async throws {
        let repositoryURL = try temporaryRepositoryURL()
        _ = try writeActorFixture(
            at: repositoryURL,
            schedule: """
            date: 2026-08-01
            performances:
              main:
                - title: Actor Set
                  startTime: "18:00"
                  contributorActors:
                    - woody.fm
                    - unresolved.example
            """
        )
        var progressEvents: [SourceActorDIDConversionProgress] = []

        _ = try await withDependencies {
            $0[Atmosphere.Account.Client.self] = .testClient(
                dids: [
                    "woody.fm": "did:plc:woody123",
                ]
            )
        } operation: {
            try await SourceActorDIDConverter().convert(
                SourceActorDIDConversionRequest(
                    repositoryURL: repositoryURL,
                    eventDirectory: "actor-event",
                    resolutionParallelism: 1,
                    resolutionTimeoutSeconds: 2
                ),
                progress: { progressEvents.append($0) }
            )
        }

        expectNoDifference(
            progressEvents,
            [
                .readingRepository(repositoryURL.standardizedFileURL),
                .repositoryRead(eventCount: 1),
                .validatingOverrides(count: 0),
                .discoveringActors(eventDirectory: "actor-event"),
                .actorsDiscovered(
                    actorReferenceCount: 2,
                    handleReferenceCount: 2,
                    didReferenceCount: 0,
                    uniqueHandleCount: 2,
                    scheduleFileCount: 1
                ),
                .resolvingHandles(
                    uniqueHandleCount: 2,
                    overrideCount: 0,
                    parallelism: 1,
                    timeoutSeconds: 2
                ),
                .resolvingHandle(handle: "unresolved.example", index: 1, total: 2),
                .handleResolutionFailed(
                    handle: "unresolved.example",
                    index: 1,
                    total: 2,
                    errorDescription: "Could not resolve unresolved.example"
                ),
                .resolvingHandle(handle: "woody.fm", index: 2, total: 2),
                .handleResolved(
                    handle: "woody.fm",
                    index: 2,
                    total: 2,
                    source: .resolved
                ),
                .buildingResult,
                .finished(didWrite: false),
            ]
        )
    }

    @Test
    func applyWritesResolvedActorsThroughFileTreeYaml() async throws {
        let repositoryURL = try temporaryRepositoryURL()
        _ = try writeActorFixture(
            at: repositoryURL,
            schedule: """
            # YAML formatting churn is accepted for apply.
            date: 2026-08-01
            performances:
              main:
                - title: Actor Set
                  startTime: "18:00"
                  contributorActors:
                    - WOODY.FM
                    - 'quoted.example'
            """
        )

        let result = try await withDependencies {
            $0[Atmosphere.Account.Client.self] = .testClient(
                dids: [
                    "woody.fm": "did:plc:woody123",
                    "quoted.example": "did:plc:quoted123",
                ]
            )
        } operation: {
            try await SourceActorDIDConverter().convert(
                SourceActorDIDConversionRequest(
                    repositoryURL: repositoryURL,
                    eventDirectory: "actor-event",
                    apply: true
                )
            )
        }

        #expect(result.didWrite)
        let schedule = try readScheduleFixture(at: repositoryURL)
        expectNoDifference(
            try actorDescriptions(in: schedule),
            [
                "did:plc:woody123",
                "did:plc:quoted123",
            ]
        )
    }

    @Test
    func applyFailsWithoutWritingWhenUnresolvedHandlesRemain() async throws {
        let repositoryURL = try temporaryRepositoryURL()
        let scheduleURL = try writeActorFixture(
            at: repositoryURL,
            schedule: """
            date: 2026-08-01
            performances:
              main:
                - title: Actor Set
                  startTime: "18:00"
                  contributorActors:
                    - woody.fm
                    - unresolved.example
            """
        )
        let originalText = try String(contentsOf: scheduleURL, encoding: .utf8)

        do {
            _ = try await withDependencies {
                $0[Atmosphere.Account.Client.self] = .testClient(
                    dids: [
                        "woody.fm": "did:plc:woody123",
                    ]
                )
            } operation: {
                try await SourceActorDIDConverter().convert(
                    SourceActorDIDConversionRequest(
                        repositoryURL: repositoryURL,
                        eventDirectory: "actor-event",
                        apply: true
                    )
                )
            }
            Issue.record("Expected unresolved handles to block apply.")
        } catch SourceActorDIDConversionError.unresolvedHandles(let unresolvedHandles) {
            expectNoDifference(
                unresolvedHandles.map(\.handle),
                ["unresolved.example"]
            )
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(try String(contentsOf: scheduleURL, encoding: .utf8) == originalText)
    }

    @Test
    func allowUnresolvedAppliesResolvedHandlesOnly() async throws {
        let repositoryURL = try temporaryRepositoryURL()
        _ = try writeActorFixture(
            at: repositoryURL,
            schedule: """
            date: 2026-08-01
            performances:
              main:
                - title: Actor Set
                  startTime: "18:00"
                  contributorActors:
                    - woody.fm
                    - unresolved.example
            """
        )

        let result = try await withDependencies {
            $0[Atmosphere.Account.Client.self] = .testClient(
                dids: [
                    "woody.fm": "did:plc:woody123",
                ]
            )
        } operation: {
            try await SourceActorDIDConverter().convert(
                SourceActorDIDConversionRequest(
                    repositoryURL: repositoryURL,
                    eventDirectory: "actor-event",
                    apply: true,
                    allowUnresolved: true
                )
            )
        }

        #expect(result.didWrite)
        expectNoDifference(
            result.unresolvedHandles.map(\.handle),
            ["unresolved.example"]
        )
        let schedule = try readScheduleFixture(at: repositoryURL)
        expectNoDifference(
            try actorDescriptions(in: schedule),
            [
                "did:plc:woody123",
                "unresolved.example",
            ]
        )
    }

    private func actorDescriptions(in schedule: ScheduleDTO) throws -> [String] {
        let contributors = try #require(schedule.scheduleItems["main"]?.first?.contributors)
        return contributors.compactMap { contributor in
            guard case let .actor(actor) = contributor.subject else { return nil }
            return actor.description
        }
    }

    private func writeActorFixture(
        at repositoryURL: URL,
        schedule: String
    ) throws -> URL {
        let eventURL = repositoryURL
            .appending(path: "events", directoryHint: .isDirectory)
            .appending(path: "actor-event", directoryHint: .isDirectory)
        let schedulesURL = eventURL.appending(path: "schedules", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: schedulesURL,
            withIntermediateDirectories: true
        )
        try """
        name: Actor Event
        timeZone: America/Denver
        """
        .write(
            to: eventURL.appending(path: "event.yml"),
            atomically: true,
            encoding: .utf8
        )

        let scheduleURL = schedulesURL.appending(path: "saturday.yml")
        try schedule.write(to: scheduleURL, atomically: true, encoding: .utf8)
        return scheduleURL
    }

    private func readScheduleFixture(at repositoryURL: URL) throws -> ScheduleDTO {
        let repository = try OpenMusicEventSourceRepositoryFileTree()
            .read(from: repositoryURL)
            .output
            .requiredValue
        let event = try #require(repository.events.first { $0.directoryName == "actor-event" })
        let schedule = try #require(event.components.schedules?.first { $0.fileName == "saturday" })
        return schedule.data
    }

    private func actorLocation(
        actorIndex: Int,
        stageID: String = "main",
        performanceIndex: Int = 0,
        performanceTitle: String = "Actor Set"
    ) -> SourceActorDIDConversionLocation {
        SourceActorDIDConversionLocation(
            file: "events/actor-event/schedules/saturday.yml",
            eventDirectory: "actor-event",
            scheduleFileName: "saturday.yml",
            stageID: stageID,
            performanceIndex: performanceIndex,
            performanceTitle: performanceTitle,
            actorIndex: actorIndex
        )
    }

    private func temporaryRepositoryURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private actor HandleResolutionRecorder {
    private var handles: [String] = []

    var resolvedHandles: [String] {
        handles
    }

    func record(_ handle: String) {
        handles.append(handle)
    }
}

private enum TestResolutionError: Error, CustomStringConvertible {
    case unresolved(String)

    var description: String {
        switch self {
        case let .unresolved(handle):
            return "Could not resolve \(handle)"
        }
    }
}

private extension Atmosphere.Account.Client {
    static func testClient(
        dids: [String: String],
        recorder: HandleResolutionRecorder? = nil
    ) -> Self {
        Self(
            resolveHandle: { handle in
                await recorder?.record(handle.rawValue)
                guard let did = dids[handle.rawValue],
                      let parsedDID = DID(did)
                else {
                    throw TestResolutionError.unresolved(handle.rawValue)
                }
                return (
                    Atmosphere.Account(id: .init(parsedDID), handle: handle),
                    try didDocument(did: parsedDID, handle: handle)
                )
            },
            resolveDID: { did in
                (
                    Atmosphere.Account(id: .init(did), handle: Atmosphere.Account.Handle("example.com")),
                    try didDocument(did: did, handle: Atmosphere.Account.Handle("example.com"))
                )
            }
        )
    }
}

private func didDocument(
    did: DID,
    handle: Atmosphere.Account.Handle
) throws -> DID.Document {
    try JSONDecoder().decode(
        DID.Document.self,
        from: Data(
            """
            {
              "id": "\(did.description)",
              "alsoKnownAs": ["at://\(handle.rawValue)"],
              "verificationMethod": [],
              "service": []
            }
            """
            .utf8
        )
    )
}
