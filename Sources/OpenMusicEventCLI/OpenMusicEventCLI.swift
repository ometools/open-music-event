import ArgumentParser
import Dependencies
import FileTree
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSourceClone
import OpenMusicEventSource

@main
struct OpenMusicEventCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ome",
        abstract: "OpenMusicEvent source repository tools.",
        subcommands: [
            Source.self
        ]
    )
}

extension OpenMusicEventCommand {
    struct Source: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "source",
            abstract: "Work with organizer-owned OpenMusicEvent source repositories.",
            subcommands: [
                TangledSourceCloneCommand.self,
                Validate.self
            ],
            defaultSubcommand: Validate.self
        )
    }
}

extension OpenMusicEventCommand.Source {
    struct Validate: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "validate",
            abstract: "Parse a source repository and prepare database insertion rows."
        )

        @Argument(help: "Path to a local source repository root or a Tangled repository reference.")
        var source: String

        @Option(help: "Organizer DID used to scope imported event records.")
        var organizerID: String

        @Option(help: "Git ref to download when source is a Tangled repository reference.")
        var ref = "HEAD"

        @Option(help: "Destination directory for a downloaded Tangled source tree. If omitted, a temporary directory is used and removed.")
        var output: String?

        @Flag(name: .shortAndLong, help: "Print event-level details.")
        var verbose = false

        func run() async throws {
            guard let organizerID = OME.Organizer.ID(organizerID)
            else {
                throw ValidationError("Invalid organizer ID: \(organizerID)")
            }

            let (repositoryURL, cleanupURL) = try await resolvedRepositoryURL()
            defer {
                if let cleanupURL {
                    try? FileManager.default.removeItem(at: cleanupURL)
                }
            }

            let source = try OpenMusicEventSourceRepositoryFileTree().read(from: repositoryURL)
            let insertion = try OME.SourceDatabaseInsertion(
                .init(source: source, organizerID: organizerID)
            )
            let summary = SourceValidationSummary(
                source: source,
                insertion: insertion
            )

            print(summary.description)

            if verbose {
                print()
                for event in summary.events {
                    print("- \(event.eventID): \(event.name)")
                }
            }
        }

        private func resolvedRepositoryURL() async throws -> (repositoryURL: URL, cleanupURL: URL?) {
            switch try SourceRepositoryLocation(parsing: source) {
            case let .local(repositoryURL):
                guard output == nil else {
                    throw ValidationError("--output can only be used when validating a Tangled repository reference.")
                }
                return (repositoryURL, nil)

            case let .tangled(repository):
                let outputURL: URL
                let cleanupURL: URL?
                if let output {
                    outputURL = try TangledSourceCloneCommand.resolvedOutputURL(output)
                    cleanupURL = nil
                } else {
                    @Dependency(\.uuid) var uuid
                    outputURL = TangledSourceCloneCommand.temporaryOutputURL(uuid: uuid())
                    cleanupURL = outputURL
                }

                try TangledSourceArchiveExtractor.validateOutputDoesNotExist(outputURL)
                do {
                    try await TangledSourceCloner(
                        repository: repository,
                        ref: ref,
                        outputURL: outputURL
                    )
                    .clone()
                } catch {
                    if let cleanupURL {
                        try? FileManager.default.removeItem(at: cleanupURL)
                    }
                    throw error
                }
                return (outputURL, cleanupURL)
            }
        }
    }
}

struct SourceValidationSummary: CustomStringConvertible {
    struct Event {
        var eventID: String
        var name: String
    }

    var events: [Event]
    var stageCount: Int
    var scheduleCount: Int
    var participantCount: Int
    var channelCount: Int
    var posterCount: Int
    var performanceCount: Int
    var performanceParticipantCount: Int

    init(
        source: OpenMusicEventSourceRepository,
        insertion: OME.SourceDatabaseInsertion
    ) {
        self.events = source.events.map {
            Event(
                eventID: $0.directoryName,
                name: $0.components.event.name
            )
        }
        self.stageCount = insertion.stages.count
        self.scheduleCount = insertion.schedules.count
        self.participantCount = insertion.participants.count
        self.channelCount = insertion.channels.count
        self.posterCount = insertion.posters.count
        self.performanceCount = insertion.performances.count
        self.performanceParticipantCount = insertion.performanceParticipants.count
    }

    var description: String {
        """
        Source repository is valid.
        Events: \(events.count)
        Stages: \(stageCount)
        Schedules: \(scheduleCount)
        Participants: \(participantCount)
        Channels: \(channelCount)
        Posters: \(posterCount)
        Performances: \(performanceCount)
        Performance participants: \(performanceParticipantCount)
        """
    }
}
