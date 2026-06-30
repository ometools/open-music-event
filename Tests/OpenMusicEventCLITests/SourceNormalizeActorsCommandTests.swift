import ArgumentParser
import CustomDump
import OpenMusicEventSource
import Testing

@testable import OpenMusicEventCLI

struct SourceNormalizeActorsCommandTests {
    @Test
    func parsesNormalizeActorsOptions() throws {
        let command = try OpenMusicEventCommand.Source.NormalizeActors.parse(
            [
                "/tmp/source",
                "--event",
                "atmosphere-conf-2026",
                "--apply",
                "--allow-unresolved",
                "--override",
                "old.handle.example=did:plc:abc123",
                "--resolution-parallelism",
                "8",
                "--resolution-timeout-seconds",
                "3",
            ]
        )

        #expect(command.source == "/tmp/source")
        #expect(command.event == "atmosphere-conf-2026")
        #expect(command.apply)
        #expect(command.allowUnresolved)
        #expect(command.resolutionParallelism == 8)
        #expect(command.resolutionTimeoutSeconds == 3)
        expectNoDifference(
            try command.parsedOverrides(),
            [
                "old.handle.example": "did:plc:abc123",
            ]
        )
    }

    @Test
    func buildsNormalizeActorsOutputTables() {
        let replacementLocation = SourceActorDIDConversionLocation(
            file: "events/atmosphere-conf-2026/schedules/friday.yml",
            eventDirectory: "atmosphere-conf-2026",
            scheduleFileName: "friday.yml",
            stageID: "main",
            performanceIndex: 2,
            performanceTitle: "Opening Keynote",
            actorIndex: 1
        )
        let unresolvedLocation = SourceActorDIDConversionLocation(
            file: "events/atmosphere-conf-2026/schedules/saturday.yml",
            eventDirectory: "atmosphere-conf-2026",
            scheduleFileName: "saturday.yml",
            stageID: "side",
            performanceIndex: 4,
            performanceTitle: "Panel",
            actorIndex: 0
        )
        let result = SourceActorDIDConversionResult(
            replacements: [
                .init(
                    location: replacementLocation,
                    handle: "woody.fm",
                    did: "did:plc:woody123",
                    source: .resolved
                ),
                .init(
                    location: replacementLocation,
                    handle: "override.example",
                    did: "did:plc:override123",
                    source: .override
                ),
            ],
            unresolvedHandles: [
                .init(
                    location: unresolvedLocation,
                    handle: "missing.example",
                    errorDescription: "Could not resolve missing.example"
                ),
            ],
            unchangedDIDReferences: [
                .init(
                    location: replacementLocation,
                    did: "did:plc:existing123"
                ),
            ],
            touchedFiles: [
                "events/atmosphere-conf-2026/schedules/friday.yml",
            ],
            didWrite: false
        )

        let outputTables = OpenMusicEventCommand.Source.NormalizeActors.outputTables(for: result)

        expectNoDifference(
            outputTables.metrics,
            [
                ["Replacements", "2"],
                ["Unresolved handles", "1"],
                ["Existing DID references", "1"],
                ["Touched files", "1"],
            ]
        )
        expectNoDifference(
            outputTables.replacements,
            [
                [
                    "events/atmosphere-conf-2026/schedules/friday.yml",
                    "main",
                    "Opening Keynote",
                    "1",
                    "woody.fm",
                    "did:plc:woody123",
                    "resolved",
                ],
                [
                    "events/atmosphere-conf-2026/schedules/friday.yml",
                    "main",
                    "Opening Keynote",
                    "1",
                    "override.example",
                    "did:plc:override123",
                    "override",
                ],
            ]
        )
        expectNoDifference(
            outputTables.unresolvedHandles,
            [
                [
                    "events/atmosphere-conf-2026/schedules/saturday.yml",
                    "side",
                    "Panel",
                    "0",
                    "missing.example",
                    "Could not resolve missing.example",
                ],
            ]
        )
    }

    @Test
    func buildsNormalizeActorsProgressOutput() {
        let outputs = [
            OpenMusicEventCommand.Source.NormalizeActors.progressOutput(
                for: .readingRepository(URL(fileURLWithPath: "/tmp/source"))
            ),
            OpenMusicEventCommand.Source.NormalizeActors.progressOutput(
                for: .actorsDiscovered(
                    actorReferenceCount: 12,
                    handleReferenceCount: 8,
                    didReferenceCount: 4,
                    uniqueHandleCount: 5,
                    scheduleFileCount: 2
                )
            ),
            OpenMusicEventCommand.Source.NormalizeActors.progressOutput(
                for: .resolvingHandle(handle: "woody.fm", index: 3, total: 5)
            ),
            OpenMusicEventCommand.Source.NormalizeActors.progressOutput(
                for: .resolvingHandles(
                    uniqueHandleCount: 5,
                    overrideCount: 1,
                    parallelism: 8,
                    timeoutSeconds: 3
                )
            ),
            OpenMusicEventCommand.Source.NormalizeActors.progressOutput(
                for: .handleResolved(
                    handle: "woody.fm",
                    index: 3,
                    total: 5,
                    source: .resolved
                )
            ),
            OpenMusicEventCommand.Source.NormalizeActors.progressOutput(
                for: .writingScheduleFile("events/atmosphere-conf-2026/schedules/friday.yml")
            ),
        ]

        expectNoDifference(
            outputs,
            [
                .info("Reading source repository at /tmp/source."),
                .line("  Found 12 actor reference(s) in 2 schedule file(s): 8 handle(s), 4 DID(s), 5 unique handle(s)."),
                .line("  Resolving [3/5] woody.fm."),
                .info("Resolving 5 unique handle(s), including 1 override(s), with up to 8 concurrent request(s) and 3s timeout."),
                .line("    Resolved [3/5] woody.fm via resolved."),
                .line("  Writing events/atmosphere-conf-2026/schedules/friday.yml."),
            ]
        )
    }
}
