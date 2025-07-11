//
//  OpenMusicEvent.swift
//  open-music-event
//
//  Created by Woodrow Melling on 6/9/25.
//


import ArgumentParser
import OpenMusicEventParser
import Dependencies
import Foundation
import OSLog


extension Logger {
    static let cli = Logger(subsystem: "bundle.ome.OpenMusicEvent", category: "CLI")
}

//extension Logger {
//    init(subsystem: String, category: String) {
//        self.init(label: subsystem + "." + category)
//    }
//}

@main
struct OpenMusicEvent: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ome",
        abstract: "A Swift command-line tool to parse OpenFestival data",
        subcommands: [Validate.self, FestivalProImport.self]
    )

    struct Validate: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "validate",
            abstract: "Parse OpenFestival data from a YAML file"
        )

        @Argument(help: "The path to the openFestival directory to parse")
        var path: String
//
        @Flag(name: .shortAndLong, help: "Enable verbose debug logging")
        var verbose: Bool = false

        func run() throws {
//            if verbose {
//                Logger.cli.debug("Verbose mode enabled")
//            }

            print("Validating OME data at path: \(path)")

            do {
                let config = try OrganizerConfiguration.fileTree.read(from: URL(filePath: path))
                print("✅ Parsed successfully! This data can be used in the OpenFestival app 🎉")
                
                printStatistics(config: config)
            } catch {
                Logger.cli.error("❌ Failed to parse: \(error.localizedDescription)")
                throw error
            }
        }
        
        private func printStatistics(config: OrganizerConfiguration) {
            print("\n📊 Summary Statistics:")
            print("Organizer: \(config.info.name)")
            print("Events: \(config.events.count)")

            if config.events.count > 1 {
                print("\nPer Event Breakdown:")
                for (index, event) in config.events.enumerated() {
                    let eventPerformances = event.schedule.reduce(0) { $0 + $1.stageSchedules.values.map(\.count).reduce(0, +) }
                    print("  Event \(index + 1) (\(event.info.name)): \(event.artists.count) artists, \(event.stages.count) stages, \(eventPerformances) performances")
                }
            }
        }

    }

}
