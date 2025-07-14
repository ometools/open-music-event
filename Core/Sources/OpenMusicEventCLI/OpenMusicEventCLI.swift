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
import CustomDump


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
            abstract: "Parse OpenFestival data from a YAML file, print statistics, and find and fix orphaned performances. An orphaned performance is a performance that has no associated artist, and an orphaned artist has no associated performance"
        )

        @Argument(help: "The path to the openFestival directory to parse")
        var path: String
//
        @Flag(name: .shortAndLong, help: "Enable verbose debug logging")
        var verbose: Bool = false

        @Flag(help: "Fix similar orphans, the Artist profile will be the source of truth")
        var fixOrphans = false

        @Flag(help: "Don't make changes to files")
        var dryRun: Bool = false



        @Option(name: .shortAndLong, help: "Validate a specific event")
        var event: String?

        func run() throws {
            try $eventName.withValue(event) {
                do {
                    let config = try OrganizerConfiguration.fileTree.read(from: URL(filePath: path))
                    print("✅ Parsed successfully! This data can be used in the OpenFestival app 🎉")


                    let breakdown = OrganizerBreakdown.from(config: config)
                    if fixOrphans {
                        self.fixOrphans(from: breakdown)
                    }

                    if verbose {
                        print("\n📊 Summary Statistics:")
                        let _ = customDump(breakdown)
                    }
                } catch {
                    print("❌ Failed to parse: \(error.localizedDescription)")
                    throw error
                }
            }
        }
        
        private func fixOrphans(from breakdown: OrganizerBreakdown) {
            print("\n🔧 Fixing orphaned performances...")
            
            var totalFixesApplied = 0
            
            for eventBreakdown in breakdown.eventBreakdowns {
                guard !eventBreakdown.similarOrphans.isEmpty else { continue }
                
                print("\n📝 Event: \(eventBreakdown.eventName)")
                print("Schedule names must exactly match the name on the artist profile.")
                print("  • 'name on schedule' → ': 'Name on Artist Profile'")
                print("Found \(eventBreakdown.similarOrphans.count) potential fixes:")
                print("---")

                for similarOrphan in eventBreakdown.similarOrphans {
                    print("  • '\(similarOrphan.performance)' → ': \(similarOrphan.artist)' (similarity: \(String(format: "%.1f", similarOrphan.similarity * 100))%)")
                }

                if dryRun {
                    print("Dry run mode enabled, no actual changes will be made.")
                    return
                }
                do {
                    let fixesApplied = try applyFixes(
                        eventName: eventBreakdown.eventName,
                        similarOrphans: eventBreakdown.similarOrphans,
                        basePath: path
                    )
                    totalFixesApplied += fixesApplied
                    print("✅ Applied \(fixesApplied) fixes for \(eventBreakdown.eventName)")
                } catch {
                    print("❌ Error fixing orphans for \(eventBreakdown.eventName): \(error)")
                }
            }
            
            if totalFixesApplied > 0 {
                print("\n🎉 Successfully applied \(totalFixesApplied) fixes!")
                print("💡 Re-run the validate command to verify the fixes.")
            } else {
                print("\n🤷 No fixes were applied.")
            }
        }
        
        private func applyFixes(eventName: String, similarOrphans: [SimilarOrphan], basePath: String) throws -> Int {
            var fixesApplied = 0
            
            // Map performance names to their correct artist names
            let performanceToArtistMap = Dictionary(
                uniqueKeysWithValues: similarOrphans.map { ($0.performance, $0.artist) }
            )
            
            // Find the event directory
            let baseURL = URL(filePath: basePath)
            let eventURL = baseURL.appendingPathComponent("2025")
            let schedulesURL = eventURL.appendingPathComponent("schedules")

            // Get all schedule files
            let scheduleFiles = try FileManager.default.contentsOfDirectory(at: schedulesURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "yml" }
            
            for scheduleFile in scheduleFiles {
                let fixesInFile = try fixScheduleFile(
                    scheduleFile: scheduleFile,
                    performanceToArtistMap: performanceToArtistMap
                )
                fixesApplied += fixesInFile
                
                if fixesInFile > 0 {
                    print("  📄 Fixed \(fixesInFile) performances in \(scheduleFile.lastPathComponent)")
                }
            }
            
            return fixesApplied
        }
        
        private func fixScheduleFile(scheduleFile: URL, performanceToArtistMap: [String: String]) throws -> Int {
            let originalContent = try String(contentsOf: scheduleFile)
            var modifiedContent = originalContent
            var fixesApplied = 0
            
            // Process each performance mapping
            for (performanceName, artistName) in performanceToArtistMap {
                let patterns = [
                    "artist: \(performanceName)",
                    "- \(performanceName)"
                ]
                
                for pattern in patterns {
                    let replacement = pattern.replacingOccurrences(of: performanceName, with: artistName)
                    let occurrences = modifiedContent.components(separatedBy: pattern).count - 1
                    
                    if occurrences > 0 {
                        modifiedContent = modifiedContent.replacingOccurrences(of: pattern, with: replacement)
                        fixesApplied += occurrences
                    }
                }
            }
            
            // Only write if changes were made
            if modifiedContent != originalContent {
                if dryRun {
                    print(scheduleFile)
                } else {
                    try modifiedContent.write(to: scheduleFile, atomically: true, encoding: .utf8)
                }
            }
            
            return fixesApplied
        }
    }

    struct OrganizerBreakdown {
        static func from(config: OrganizerConfiguration) -> Self {
            OrganizerBreakdown(
                organizerName: config.info.name,
                eventBreakdowns: config.events.filter {
                    if let eventName {
                        return $0.info.name == eventName
                    } else {
                        return true
                    }
                }.map { event in
                    EventBreakdown.from(event: event)
                }
            )
        }

        let organizerName: String
        let eventBreakdowns: [EventBreakdown]

        struct EventBreakdown {
            static func from(event: EventConfiguration) -> Self {
                let scheduleBreakdowns = event.schedule.map { schedule in
                    let performanceCount = schedule.stageSchedules.values.map(\.count).reduce(0, +)
                    return ScheduleBreakdown(
                        scheduleTitle: schedule.metadata.customTitle ?? "Schedule",
                        performanceCount: performanceCount
                    )
                }
                
                let totalPerformanceCount = scheduleBreakdowns.map(\.performanceCount).reduce(0, +)


                let allPerformanceArtistNames = Set(event.schedule.flatMap { $0.stageSchedules.flatMap(\.value) }.flatMap { $0.artistNames })
                let allArtistNames = Set(event.artists.map { $0.name })

                let orphanedArtists = allArtistNames.subtracting(allPerformanceArtistNames)
                let orphanedPerformances = allPerformanceArtistNames.subtracting(allArtistNames)

                let similarOrphans = findSimilarOrphans(
                    orphanedArtists: orphanedArtists,
                    orphanedPerformances: orphanedPerformances
                )


                return EventBreakdown(
                    eventName: event.info.name,
                    artistCount: event.artists.count,
                    performanceCount: totalPerformanceCount,
                    stageCount: event.stages.count,
                    orphanedArtistCount: orphanedArtists.count,
                    orphanedPerformanceCount: orphanedPerformances.count,
                    similarOrphans: similarOrphans,
                    scheduleBreakdowns: scheduleBreakdowns
                )
            }
            
            var eventName: String
            var artistCount: Int
            var performanceCount: Int
            var stageCount: Int

            var orphanedArtistCount: Int
            var orphanedPerformanceCount: Int
            var similarOrphans: [SimilarOrphan]

            let scheduleBreakdowns: [ScheduleBreakdown]

            struct ScheduleBreakdown {
                let scheduleTitle: String
                let performanceCount: Int
            }
        }
    }

}

@TaskLocal var eventName: String?

struct SimilarOrphan: Sendable {
    let artist: String
    let performance: String
    let similarity: Double
}

private func findSimilarOrphans(
    orphanedArtists: Set<String>,
    orphanedPerformances: Set<String>
) -> [SimilarOrphan] {
    let threshold = 0.6
    var similarOrphans: [SimilarOrphan] = []
    
    for artist in orphanedArtists {
        for performance in orphanedPerformances {
            let similarity = calculateSimilarity(artist, performance)
            if similarity >= threshold {
                similarOrphans.append(SimilarOrphan(
                    artist: artist,
                    performance: performance,
                    similarity: similarity
                ))
            }
        }
    }
    
    return similarOrphans.sorted { $0.similarity > $1.similarity }
}

private func calculateSimilarity(_ str1: String, _ str2: String) -> Double {
    let s1 = str1.lowercased().trimmingCharacters(in: .whitespacesAndPunctuationCharacters)
    let s2 = str2.lowercased().trimmingCharacters(in: .whitespacesAndPunctuationCharacters)
    
    if s1 == s2 { return 1.0 }
    if s1.isEmpty || s2.isEmpty { return 0.0 }
    
    let distance = levenshteinDistance(s1, s2)
    let maxLength = max(s1.count, s2.count)
    
    return 1.0 - (Double(distance) / Double(maxLength))
}

private func levenshteinDistance(_ str1: String, _ str2: String) -> Int {
    let s1 = Array(str1)
    let s2 = Array(str2)
    let m = s1.count
    let n = s2.count
    
    if m == 0 { return n }
    if n == 0 { return m }
    
    var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
    
    for i in 0...m {
        dp[i][0] = i
    }
    
    for j in 0...n {
        dp[0][j] = j
    }
    
    for i in 1...m {
        for j in 1...n {
            let cost = s1[i - 1] == s2[j - 1] ? 0 : 1
            dp[i][j] = min(
                dp[i - 1][j] + 1,      // deletion
                dp[i][j - 1] + 1,      // insertion
                dp[i - 1][j - 1] + cost // substitution
            )
        }
    }
    
    return dp[m][n]
}

extension Character {
    var isWhitespaceOrPunctuation: Bool {
        return self.isWhitespace || self.isPunctuation
    }
}

extension String {
    func trimmingCharacters(in characterSet: CharacterSet) -> String {
        return self.unicodeScalars.filter { !characterSet.contains($0) }.map(Character.init).map(String.init).joined()
    }
}

extension CharacterSet {
    static let whitespacesAndPunctuationCharacters = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
}
