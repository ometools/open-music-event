import ArgumentParser
import FileTree
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSource

@main
struct OpenMusicEventCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ome",
        abstract: "OpenMusicEvent source repository tools.",
        subcommands: [
            Source.self
        ]
    )
}

extension OpenMusicEventCommand {
    struct Source: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "source",
            abstract: "Work with organizer-owned OpenMusicEvent source repositories.",
            subcommands: [
                Validate.self
            ],
            defaultSubcommand: Validate.self
        )
    }
}

extension OpenMusicEventCommand.Source {
    struct Validate: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "validate",
            abstract: "Parse a local source repository and prepare database insertion rows."
        )

        @Argument(help: "Path to the local source repository root.")
        var path: String

        @Option(help: "Organizer DID used to scope imported event records.")
        var organizerID: String

        @Flag(name: .shortAndLong, help: "Print event-level details.")
        var verbose = false

        func run() throws {
            guard let organizerID = OME.Organizer.ID(organizerID)
            else {
                throw ValidationError("Invalid organizer ID: \(organizerID)")
            }

            let repositoryURL = URL(filePath: path).standardizedFileURL
            let source = try OpenMusicEventSourceRepositoryFileTree()
                .read(from: repositoryURL)
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
