import ArgumentParser
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
            abstract: "Parse, validate, and insert a source repository."
        )

        @Argument(help: "Path to a local source repository root or a Tangled repository reference.")
        var source: String

        @Option(help: "Organizer DID used to scope imported event records. If omitted for a Tangled repository, the owner DID is resolved from the repository reference.")
        var organizerID: String?

        @Option(help: "Git ref to download when source is a Tangled repository reference.")
        var ref = "HEAD"

        @Option(help: "Destination directory for a downloaded Tangled source tree. If omitted, a temporary directory is used and removed.")
        var output: String?

        @Flag(name: .shortAndLong, help: "Print event-level details.")
        var verbose = false

        func run() async throws {
            let organizerID = try parsedOrganizerID()
            let outputURL = try output.map(TangledSourceCloneCommand.resolvedOutputURL)
            let result = try await OpenMusicEventSourceValidator(
                OpenMusicEventSourceValidationRequest(
                    source: source,
                    organizerID: organizerID,
                    ref: ref,
                    outputURL: outputURL
                )
            )
            .validateAndInsertIntoDefaultDatabase()

            print(result.summary.description)

            if verbose {
                print()
                for event in result.summary.events {
                    print("- \(event.eventID): \(event.name)")
                }
            }
        }

        private func parsedOrganizerID() throws -> OME.Organizer.ID? {
            guard let organizerID else { return nil }
            guard let parsedOrganizerID = OME.Organizer.ID(organizerID) else {
                throw ValidationError(OpenMusicEventSourceValidationError.invalidOrganizerID(organizerID).localizedDescription)
            }
            return parsedOrganizerID
        }
    }
}
