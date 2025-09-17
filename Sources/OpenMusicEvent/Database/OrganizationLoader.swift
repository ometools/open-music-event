//
//  OrganizationLoader.swift
//  open-music-event
//
//  Created by Woodrow Melling on 5/7/25.
//
//  ORGANIZATION DATABASE INSERTION COMPLEXITY - CURRENT ASSUMPTIONS:
//
//  ## CRITICAL ASSUMPTIONS (These should be no user data stored in org tables):
//  1. Organization tables contain ONLY source data from organization configuration files
//  2. User preferences/state are stored in separate "Preferences" tables (artistPreferences, performancePreferences, etc.)
//  3. Any user-generated data must NOT be stored alongside organization data
//
//  ## CURRENT COMPLEXITY ISSUES:
//  1. Manual selective deletion for each entity level (events, artists, stages, schedules, performances, posts)
//  2. Complex ID generation using stabilizedBy pattern that's brittle and hard to debug
//  3. Nested loops with error-prone foreign key relationships
//  4. Preservation logic for user preferences scattered throughout insertion
//  5. No clear separation between user data and organization data
//  6. Inefficient: queries existing data multiple times for each entity type
//
//  ## PROPOSED SIMPLIFICATION STRATEGY:
//  1. Create clear separation between organization data and user data
//  2. Use transaction-based full replacement with preference preservation
//  3. Simplify ID generation with consistent, debuggable patterns
//  4. Extract insertion logic into dedicated service classes
//  5. Add comprehensive validation and error handling
//

import OpenMusicEventParser
import Dependencies
import DependenciesMacros
import  SwiftUI; import SkipFuse
import IssueReporting




@DependencyClient
struct DataFetchingClient {
    var fetchOrganizer: @Sendable (_ from: OrganizationReference) async throws -> OrganizerConfiguration
}


struct FailedToLoadOrganizerError: Error {}
extension DataFetchingClient: DependencyKey {
    static let liveValue = DataFetchingClient { orgReference in
        // Create a safe directory name using the URL's hash
        let urlHash = String(orgReference.zipURL.absoluteString.stableHash)
        
        #if os(iOS)
        let unzippedURL = URL.documentsDirectory
            .appending(path: "ome-zips")
            .appending(path: urlHash)
        
        #elseif os(Android)
        let unzippedURL = URL.applicationSupportDirectory
            .appending(path: "ome-zips")
            .appending(path: urlHash)
        #endif

        
        let targetZipURL = orgReference.zipURL
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: unzippedURL, withIntermediateDirectories: true)
        try fileManager.clearDirectory(unzippedURL)

        let (downloadURL, response) = try await URLSession.shared.download(from: targetZipURL)

        logger.info("Downloading from: \(targetZipURL)")
        logger.info("Response: \((response as! HTTPURLResponse).statusCode), to url: \(downloadURL)")

        if (response as! HTTPURLResponse).statusCode != 200 {
            reportIssue(response.debugDescription)
            struct BadRequest: Error {}
            throw BadRequest()
        }

        logger.info("Unzipping from \(downloadURL) to \(unzippedURL)")

        @Dependency(\.zipClient) var zipClient
        try zipClient.unzipFile(source: downloadURL, destination: unzippedURL)
        
        // Check contents AFTER unzipping
        let contents = try fileManager.contentsOfDirectory(at: unzippedURL, includingPropertiesForKeys: nil)
        logger.info("Contents of \(unzippedURL) after unzipping: \(contents)")

        let finalDestination = try getUnzippedDirectory(from: unzippedURL)
        logger.info("Parsing organizer from directory: \(finalDestination)")

        var organizerData = try withDependencies {
            var utcCalendar = Calendar.current
            utcCalendar.timeZone = TimeZone(identifier: "UTC")!
            $0.calendar = utcCalendar
        } operation: {
            try OrganizerConfiguration.fileTree.read(from: finalDestination)
        }
        organizerData.info.url = orgReference.zipURL

        logger.info("Clearing temporary directory")
        try FileManager.default.clearDirectory(unzippedURL)

        return organizerData
    }
}

extension DependencyValues {
    var organizationFetchingClient: DataFetchingClient {
        get { self[DataFetchingClient.self] }
        set { self[DataFetchingClient.self] = newValue }
    }

    var zipClient: ZipClient {
        get { self[ZipClient.self] }
        set { self[ZipClient.self] = newValue }
    }
}

private func getUnzippedDirectory(from zipURL: URL) throws -> URL {
    return try findOrganizationInfoDirectory(startingFrom: zipURL, currentDepth: 0, maxDepth: 5)
}

private func findOrganizationInfoDirectory(startingFrom url: URL, currentDepth: Int, maxDepth: Int) throws -> URL {
    // Safety check: prevent infinite recursion
    guard currentDepth <= maxDepth else {
        struct MaxDepthReachedError: Error {}
        throw MaxDepthReachedError()
    }
    
    // Check both .yml and .yaml extensions in current directory
    let ymlPath = url.appendingPathComponent("organizer-info.yml")
    let yamlPath = url.appendingPathComponent("organizer-info.yaml")
    
    if FileManager.default.fileExists(atPath: ymlPath.path()) ||
       FileManager.default.fileExists(atPath: yamlPath.path()) {
        return url
    }
    
    // Get all subdirectories
    let fileURLs = try FileManager.default.contentsOfDirectory(
        at: url,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: .skipsHiddenFiles
    )
    
    // Recursively search subdirectories
    for fileURL in fileURLs {
        let isDirectory = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        
        if isDirectory {
            do {
                return try findOrganizationInfoDirectory(
                    startingFrom: fileURL,
                    currentDepth: currentDepth + 1,
                    maxDepth: maxDepth
                )
            } catch {
                // Continue searching other directories if this one fails
                continue
            }
        }
    }
    
    struct UnableToDeterminedDirectoryURL: Error {}
    throw UnableToDeterminedDirectoryURL()
}

extension FileManager {
    func clearDirectory(_ url: URL) throws {
        let contents = try contentsOfDirectory(atPath: url.path())
        try contents.forEach { file in
            let fileUrl = url.appendingPathComponent(file)
            try removeItem(atPath: fileUrl.path)
        }
    }
}

import GRDB
//extension Logger {
//    init(subsystem: String, category: String) {
//        self.init(label: subsystem + "." + category)
//    }
//}

private let logger = Logger(subsystem: "bundle.ome.OpenMusicEvent", category: "OrganizerLoader")


extension String {
    var stableHash: Int {
        var result = UInt64 (5381)
        let buf = [UInt8](self.utf8)
        for b in buf {
            result = 127 * (result & 0x00ffffffffffffff) + UInt64(b)
        }
        // I'm getting some weird mapping errors and I think it's due to Int's being different sizes across platforms?
        // Lets
        return Int(result)
    }
}

extension OmeID where RawValue == String {
    public init(stabilizedBy values: String...) {
        self.init(rawValue: values
            .map {
                $0.replacingOccurrences(of: " ", with: "-")
            }.joined(separator: "/"))
    }
}


public enum OrganizationReference: Hashable, Codable, Sendable, LosslessStringConvertible {
    case repository(Repository)
    case url(URL)

    public struct Repository: Hashable, Codable, Sendable {
        public init(baseURL: URL, version: Version) {
            self.baseURL = baseURL
            self.version = version
        }

        var baseURL: URL
        var version: Version

        public enum Version: Hashable, Codable, Sendable {
            case branch(String)
            case version(SemanticVersion)
        }

        public var zipURL: URL {
            switch version {
            case .branch(let name):
                return baseURL.appendingPathComponent("archive/heads/\(name).zip")
            case .version(let version):
                return baseURL.appendingPathComponent("archive/refs/tags/\(version).zip")
            }
        }
    }

    

    public var zipURL: URL {
        switch self {
        case .repository(let repository):
            return repository.zipURL
        case .url(let url):
            return url
        }
    }

    public init?(_ description: String) {
        guard let url = URL(string: description)
        else { return nil }

        let components = url.pathComponents
                let baseURL = URL(string: "https://\(url.host!)\(components[0...2].joined(separator: "/"))")!
        let refType = components[safe: 4]
        let refName = components[safe: 5]?.replacingOccurrences(of: ".zip", with: "")

        switch refType {
        case "heads":
            guard let branch = refName else { return nil }
            self = .repository(.init(baseURL: baseURL, version: .branch(branch)))
        case "tags":
            guard let tag = refName, let version = SemanticVersion(tag) else { return nil }
            self = .repository(.init(baseURL: baseURL, version: .version(version)))
        default:
            return nil
        }

        return nil
    }

    public var description: String {
        switch self {
        case .repository(let repo):
            return repo.zipURL.absoluteString
        case .url(let url):
            return url.absoluteString
        }
    }
}

func downloadAndStoreOrganizer(from reference: OrganizationReference) async throws {
    @Dependency(\.organizationFetchingClient) var dataFetchingClient
    @Dependency(\.defaultDatabase) var defaultDatabase
    @Dependency(\.notificationManager) var notificationManager

    let organizer: OrganizerConfiguration = try await dataFetchingClient.fetchOrganizer(reference)

    try await organizer.insert(url: reference.zipURL, into: defaultDatabase)

    Task {
        try await notificationManager.ensureTopicsAreSubscribed()
    }
}

// MARK: - Simplified Organization Insertion Service
/// Service responsible for inserting organization data into the database
/// Follows the principle: NO USER DATA should be stored in organization tables
enum OrganizationInsertionService {

    /// Inserts organization configuration into database with simplified, more maintainable approach
    /// - Preserves user preferences by backing them up and restoring after insertion
    /// - Uses full replacement strategy within transactions for data integrity
    /// - Separates concerns between organization data and user preferences
    static func insert(_ config: OrganizerConfiguration, url: URL, into database: any DatabaseWriter) async throws {
        
        try await database.write { db in
            
            // STEP 1: Preserve all user preferences (the only user data we care about)
            let userPreferences = try preserveUserPreferences(from: db)
            
            // STEP 2: Clean insert of organization data (simple full replacement)
            try insertOrganizationData(config, url: url, into: db)
            
            // STEP 3: Restore user preferences that still have valid references
            try restoreUserPreferences(userPreferences, into: db)
        }
    }
    
    /// Preserves all user preference data before organization data replacement
    private static func preserveUserPreferences(from db: Database) throws -> UserPreferences {
        UserPreferences(
            artistPreferences: try Artist.Preferences.fetchAll(db),
            performancePreferences: try Performance.Preferences.fetchAll(db),
            channelPreferences: try CommunicationChannel.Preferences.fetchAll(db),
            postPreferences: try CommunicationChannel.Post.Preferences.fetchAll(db)
        )
    }
    
    /// Inserts organization data using simplified full-replacement approach
    private static func insertOrganizationData(_ config: OrganizerConfiguration, url: URL, into db: Database) throws {
        
        // Insert organizer info
        var organizerInfo = config.info
        organizerInfo.url = url
        
        guard let organizerID = organizerInfo.id else {
            struct MissingOrganizerIDError: Error {}
            throw MissingOrganizerIDError()
        }

        try Organizer.deleteOne(db, id: organizerID)
        try organizerInfo.upsert(db)

        // Insert all events and their related data
        for event in config.events {
            try insertEvent(event, organizerID: organizerID, into: db)
        }
    }
    
    /// Inserts a single event and all its related data
    private static func insertEvent(_ event: EventConfiguration, organizerID: Organizer.ID, into db: Database) throws {
        
        // Generate stable event ID
        let eventID = generateEventID(organizerID: organizerID, eventName: event.info.name)
        
        // Insert event
        var eventInfo = event.info
        eventInfo.id = eventID
        eventInfo.organizerID = organizerID
        try eventInfo.upsert(db)
        
        // Create artist mapping for later reference
        let artistMapping = try insertArtists(event.artists, eventID: eventID, into: db)
        
        // Insert other entities
        try insertChannels(event.channels, eventID: eventID, into: db)
        let stageMapping = try insertStages(event.stages, eventID: eventID, stageLineups: event.stageLineups, artistMapping: artistMapping, into: db)
        try insertSchedulesAndPerformances(event.schedule, eventID: eventID, stageMapping: stageMapping, artistMapping: artistMapping, into: db)
    }
    
    /// Inserts artists and returns name->ID mapping
    private static func insertArtists(
        _ artists: [Artist.Draft],
        eventID: MusicEvent.ID,
        into db: Database
    ) throws -> [String: Artist.ID] {
        var mapping: [String: Artist.ID] = [:]
        
        for artist in artists {
            let artistID = generateArtistID(eventID: eventID, artistName: artist.name)
            let artistDraft = Artist.Draft(
                id: artistID,
                musicEventID: eventID,
                name: artist.name,
                bio: artist.bio,
                imageURL: artist.imageURL,
                links: artist.links
            )
            
            try artistDraft.upsert(db)
            mapping[artist.name] = artistID
        }
        
        return mapping
    }
    
    /// Inserts communication channels and their posts
    private static func insertChannels(_ channels: [EventConfiguration.ChannelConfiguration], eventID: MusicEvent.ID, into db: Database) throws {
        for channel in channels {
            let channelID = generateChannelID(eventID: eventID, channelName: channel.info.name)
            
            var channelInfo = channel.info
            channelInfo.id = channelID
            channelInfo.musicEventID = eventID
            try channelInfo.upsert(db)
            
            // Insert posts
            for post in channel.posts {
                var postDraft = post
                postDraft.id = generatePostID(channelID: channelID, postTitle: post.title)
                postDraft.channelID = channelID
                try postDraft.upsert(db)
            }
        }
    }
    
    /// Inserts stages and returns name->ID mapping
    private static func insertStages(
        _ stages: [StageConfiguration], 
        eventID: MusicEvent.ID, 
        stageLineups: [String: StageLineupConfiguration]?, 
        artistMapping: [String: Artist.ID], 
        into db: Database
    ) throws -> [String: Stage.ID] {
        var mapping: [String: Stage.ID] = [:]
        
        for (index, stage) in stages.enumerated() {
            let stageID = generateStageID(eventID: eventID, stageName: stage.name)
            
            // Get lineup artist IDs
            let lineup = stageLineups?[stage.name]
            let artistIDs = lineup?.artists.compactMap { artistMapping[$0] }
            
            let stageDraft = Stage.Draft(
                id: stageID,
                musicEventID: eventID,
                name: stage.name,
                category: stage.category,
                sortIndex: index,
                iconImageURL: stage.iconImageURL,
                imageURL: stage.imageURL,
                posterImageURL: stage.posterImageURL,
                color: stage.color,
                lineup: artistIDs
            )
            
            try stageDraft.upsert(db)
            mapping[stage.name] = stageID
        }
        
        return mapping
    }
    
    /// Inserts schedules and their performances
    private static func insertSchedulesAndPerformances(
        _ schedules: [ScheduleConfiguration],
        eventID: MusicEvent.ID,
        stageMapping: [String: Stage.ID],
        artistMapping: [String: Artist.ID],
        into db: Database
    ) throws {
        
        for schedule in schedules {
            let scheduleID = generateScheduleID(eventID: eventID, schedule: schedule)
            
            let scheduleDraft = Schedule.Draft(
                id: scheduleID,
                musicEventID: eventID,
                startTime: schedule.metadata.startTime,
                endTime: schedule.metadata.endTime,
                customTitle: schedule.metadata.customTitle
            )
            
            try scheduleDraft.upsert(db)
            
            // Insert performances for this schedule
            for (stageName, performances) in schedule.stageSchedules {
                guard let stageID = stageMapping[stageName] else {
                    reportIssue("Missing stage ID for stage: \(stageName)")
                    continue
                }
                
                for performance in performances {
                    try insertPerformance(
                        performance,
                        eventID: eventID,
                        scheduleID: scheduleID,
                        stageID: stageID,
                        artistMapping: artistMapping,
                        into: db
                    )
                }
            }
        }
    }
    
    /// Inserts a single performance and its artist relationships
    private static func insertPerformance(
        _ performance: PerformanceConfiguration,
        eventID: MusicEvent.ID,
        scheduleID: Schedule.ID,
        stageID: Stage.ID,
        artistMapping: [String: Artist.ID],
        into db: Database
    ) throws {
        
        let performanceID = generatePerformanceID(scheduleID: scheduleID, stageID: stageID, performance: performance)
        
        let performanceDraft = Performance.Draft(
            id: performanceID,
            stageID: stageID,
            scheduleID: scheduleID,
            startTime: performance.startTime,
            endTime: performance.endTime,
            title: performance.title,
            description: performance.description
        )
        
        try performanceDraft.upsert(db)
        
        // Insert performance-artist relationships
        for artistName in performance.artistNames {
            if let artistID = artistMapping[artistName] {
                let performanceArtistDraft = Performance.Artists.Draft(
                    performanceID: performanceID,
                    artistID: artistID
                )
                try performanceArtistDraft.upsert(db)
            } else {
                // Create missing artist on-the-fly
                let artistID = generateArtistID(eventID: eventID, artistName: artistName)
                let artistDraft = Artist.Draft(
                    id: artistID,
                    musicEventID: eventID,
                    name: artistName,
                    links: []
                )
                try artistDraft.upsert(db)
                
                let performanceArtistDraft = Performance.Artists.Draft(
                    performanceID: performanceID,
                    artistID: artistID
                )
                try performanceArtistDraft.upsert(db)
            }
        }
    }
    
    /// Restores user preferences that still have valid entity references
    private static func restoreUserPreferences(_ preferences: UserPreferences, into db: Database) throws {
        
        // Restore artist preferences
        for pref in preferences.artistPreferences {
            // Only restore if artist still exists
            if try Artist.fetchOne(db, id: pref.artistID) != nil {
                try Artist.Preferences.Draft(pref).upsert(db)
            }
        }
        
        // Restore performance preferences  
        for pref in preferences.performancePreferences {
            // Only restore if performance still exists
            if try Performance.fetchOne(db, id: pref.performanceID) != nil {
                try Performance.Preferences.Draft(pref).upsert(db)
            }
        }
        
        // Restore channel preferences
        for pref in preferences.channelPreferences {
            // Only restore if channel still exists
            if try CommunicationChannel.fetchOne(db, id: pref.channelID) != nil {
                try CommunicationChannel.Preferences.Draft(pref).upsert(db)
            }
        }
        
        // Restore post preferences
        for pref in preferences.postPreferences {
            // Only restore if post still exists
            if try CommunicationChannel.Post.fetchOne(db, id: pref.postID) != nil {
                try CommunicationChannel.Post.Preferences.Draft(pref).upsert(db)
            }
        }
    }
}

// MARK: - ID Generation Utilities
/// Centralized, consistent ID generation with clear debugging information
extension OrganizationInsertionService {
    
    static func generateEventID(organizerID: Organizer.ID, eventName: String) -> MusicEvent.ID {
        MusicEvent.ID(stabilizedBy: organizerID.rawValue, eventName)
    }
    
    static func generateArtistID(eventID: MusicEvent.ID, artistName: String) -> Artist.ID {
        Artist.ID(stabilizedBy: eventID.rawValue, artistName)
    }
    
    static func generateChannelID(eventID: MusicEvent.ID, channelName: String) -> CommunicationChannel.ID {
        CommunicationChannel.ID(stabilizedBy: eventID.rawValue, channelName)
    }
    
    static func generatePostID(channelID: CommunicationChannel.ID, postTitle: String) -> CommunicationChannel.Post.ID {
        CommunicationChannel.Post.ID(stabilizedBy: channelID.rawValue, postTitle)
    }
    
    static func generateStageID(eventID: MusicEvent.ID, stageName: String) -> Stage.ID {
        Stage.ID(stabilizedBy: eventID.rawValue, stageName)
    }
    
    static func generateScheduleID(eventID: MusicEvent.ID, schedule: ScheduleConfiguration) -> Schedule.ID {
        let identifier = schedule.metadata.customTitle ?? schedule.metadata.startTime.formatted(.dateTime.weekday(.short))
        return Schedule.ID(stabilizedBy: eventID.rawValue, identifier)
    }
    
    static func generatePerformanceID(scheduleID: Schedule.ID, stageID: Stage.ID, performance: PerformanceConfiguration) -> Performance.ID {
        // Extract stage name from stage ID for uniqueness
        let stageIdentifier = stageID.rawValue.components(separatedBy: "/").last ?? "unknown-stage"
        return Performance.ID(stabilizedBy: scheduleID.rawValue, stageIdentifier, performance.title)
    }
}

// MARK: - User Preferences Data Structure
/// Container for all user preference data that needs to be preserved during organization updates
private struct UserPreferences {
    let artistPreferences: [Artist.Preferences]
    let performancePreferences: [Performance.Preferences]
    let channelPreferences: [CommunicationChannel.Preferences]
    let postPreferences: [CommunicationChannel.Post.Preferences]
}

// MARK: - Updated Extension Using New Service
extension OrganizerConfiguration {
    func insert(url: URL, into database: any DatabaseWriter) async throws {
        try await OrganizationInsertionService.insert(self, url: url, into: database)
    }
}

extension Array {
    public subscript(safe index: Index) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
