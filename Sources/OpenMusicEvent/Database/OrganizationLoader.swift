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
        switch orgReference {
        case .repository(let repository):
            return try await downloadAndParseZip(from: repository.zipURL, originalReference: orgReference)
        case .zipURL(let zipURL):
            return try await downloadAndParseZip(from: zipURL, originalReference: orgReference)
        case .bundledDirectory(let directoryURL):
            return try await parseOrganizerFromDirectory(directoryURL, originalReference: orgReference)
        }
    }
    
    private static func downloadAndParseZip(from zipURL: URL, originalReference: OrganizationReference) async throws -> OrganizerConfiguration {
        // Create a safe directory name using the URL's hash
        let urlHash = String(zipURL.absoluteString.stableHash)
        
        #if os(iOS)
        let unzippedURL = URL.documentsDirectory
            .appending(path: "ome-zips")
            .appending(path: urlHash)
        
        #elseif os(Android)
        let unzippedURL = URL.applicationSupportDirectory
            .appending(path: "ome-zips")
            .appending(path: urlHash)
        #endif

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: unzippedURL, withIntermediateDirectories: true)
        try fileManager.clearDirectory(unzippedURL)

        let (downloadURL, response) = try await URLSession.shared.download(from: zipURL)

        logger.info("Downloading from: \(zipURL)")
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
        
        defer {
            // Clean up temporary directory
            logger.info("Clearing temporary directory")
            try? FileManager.default.clearDirectory(unzippedURL)
        }
        
        return try await parseOrganizerFromDirectory(finalDestination, originalReference: originalReference)
    }
    
    private static func parseOrganizerFromDirectory(_ directoryURL: URL, originalReference: OrganizationReference) async throws -> OrganizerConfiguration {
        logger.info("Parsing organizer from directory: \(directoryURL)")

        var organizerData = try withDependencies {
            var utcCalendar = Calendar.current
            utcCalendar.timeZone = TimeZone(identifier: "UTC")!
            $0.calendar = utcCalendar
        } operation: {
            try OrganizerConfiguration.fileTree.read(from: directoryURL)
        }
        
        // Set the URL based on the original reference
        switch originalReference {
        case .repository(let repository):
            organizerData.info.url = repository.zipURL
        case .zipURL(let zipURL):
            organizerData.info.url = zipURL
        case .bundledDirectory:
            // For bundled directories, we might want to set a custom URL or leave it as is
            organizerData.info.url = directoryURL
        }

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
    case zipURL(URL)
    case bundledDirectory(URL)

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
        case .zipURL(let url):
            return url
        case .bundledDirectory(let url):
            return url // For bundled directories, we just return the directory URL
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
        case .zipURL(let url):
            return url.absoluteString
        case .bundledDirectory(let url):
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
    try await notificationManager.ensureTopicsAreSubscribed()
}

/// Downloads and stores organization using per-org database architecture
func downloadAndStoreOrganizationV2(from reference: OrganizationReference) async throws -> DatabaseQueue {
    @Dependency(\.organizationDatabaseManager) var dbManager

    // Download, parse, and get source files path
    let (config, sourceFilesPath) = try await downloadAndParseWithFiles(from: reference)

    guard let organizerID = config.info.id else {
        struct MissingOrganizerIDError: Error {}
        throw MissingOrganizerIDError()
    }

    // Create final organization folder path
    let orgPath = OrganizationDatabaseManager.organizationsDirectory
        .appendingPathComponent("\(organizerID.rawValue)")

    // Move downloaded files to final location
    let fileManager = FileManager.default

    // Ensure parent "Open Music Event" directory exists
    try fileManager.createDirectory(
        at: OrganizationDatabaseManager.organizationsDirectory,
        withIntermediateDirectories: true
    )

    // Remove existing org folder if it exists
    if fileManager.fileExists(atPath: orgPath.path()) {
        try fileManager.removeItem(at: orgPath)
    }

    // Move temp files to final location
    try fileManager.moveItem(at: sourceFilesPath, to: orgPath)
    // Open organization database (creates .ome/org.db)
    let orgDatabase = try dbManager.openDatabase(at: orgPath)

    // Insert configuration into org database
    try await OrganizationInsertionService.insert(config, into: orgDatabase)

    return orgDatabase
}

/// Downloads and parses organization, returning config and source files path
/// Caller is responsible for moving/cleaning up the source files
private func downloadAndParseWithFiles(from reference: OrganizationReference) async throws -> (OrganizerConfiguration, URL) {
    let urlHash = String(reference.zipURL.absoluteString.stableHash)

    #if os(iOS)
    let unzippedURL = URL.documentsDirectory
        .appending(path: "ome-zips")
        .appending(path: urlHash)
    #elseif os(Android)
    let unzippedURL = URL.applicationSupportDirectory
        .appending(path: "ome-zips")
        .appending(path: urlHash)
    #endif

    let fileManager = FileManager.default
    try fileManager.createDirectory(at: unzippedURL, withIntermediateDirectories: true)
    try fileManager.clearDirectory(unzippedURL)

    // Download zip
    let (downloadURL, response) = try await URLSession.shared.download(from: reference.zipURL)

    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
        struct BadRequest: Error {}
        throw BadRequest()
    }

    // Unzip
    @Dependency(\.zipClient) var zipClient
    try zipClient.unzipFile(source: downloadURL, destination: unzippedURL)

    // Find directory containing organizer-info
    let sourceFilesPath = try findOrganizationInfoDirectory(startingFrom: unzippedURL, currentDepth: 0, maxDepth: 5)

    // Parse configuration
    var config = try withDependencies {
        var utcCalendar = Calendar.current
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        $0.calendar = utcCalendar
    } operation: {
        try OrganizerConfiguration.fileTree.read(from: sourceFilesPath)
    }

    // Set URL from reference
    switch reference {
    case .repository(let repository):
        config.info.url = repository.zipURL
    case .zipURL(let zipURL):
        config.info.url = zipURL
    case .bundledDirectory(let directoryURL):
        config.info.url = directoryURL
    }

    return (config, sourceFilesPath)
}

func loadAndStoreLocalOrganizer(from folderURL: URL) async throws {
    @Dependency(\.defaultDatabase) var defaultDatabase
    @Dependency(\.notificationManager) var notificationManager

    var organizerData = try withDependencies {
        var utcCalendar = Calendar.current
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        $0.calendar = utcCalendar
    } operation: {
        try OrganizerConfiguration.fileTree.read(from: folderURL)
    }

    // Use a local file URL as the organizer URL
    organizerData.info.url = folderURL
    try await organizerData.insert(url: folderURL, into: defaultDatabase)

    Task {
        try await notificationManager.ensureTopicsAreSubscribed()
    }
}

enum OrganizationInsertionService {

     /// Inserts organization configuration into database with simplified, more maintainable approach
    /// - Preserves user preferences by backing them up and restoring after insertion
    /// - Uses full replacement strategy within transactions for data integrity
    /// - Separates concerns between organization data and user preferences
    static func insert(_ config: OrganizerConfiguration, url: URL, into database: any DatabaseWriter) async throws {

        try await database.write { db in
            let userPreferences = try preserveUserPreferences(from: db)

            // STEP 2: Clean insert of organization data (simple full replacement)
            try insertOrganizationData(config, url: url, into: db)

            // STEP 3: Restore user preferences that still have valid references
            try restoreUserPreferences(userPreferences, into: db)
        }
    }

    /// Inserts organization data into a per-org database (no user preferences handling)
    static func insert(_ config: OrganizerConfiguration, into database: any DatabaseWriter) async throws {
        try await database.write { db in
            try insertOrganizationDataOnly(config, into: db)
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

    /// Inserts organization data into per-org database (no URL needed, no preferences)
    private static func insertOrganizationDataOnly(_ config: OrganizerConfiguration, into db: Database) throws {

        guard let organizerID = config.info.id else {
            struct MissingOrganizerIDError: Error {}
            throw MissingOrganizerIDError()
        }

        // Insert organizer info (URL already set from parsing)
        try Organizer.deleteOne(db, id: organizerID)
        try config.info.upsert(db)

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
        let artistMapping = try insertArtists(
            event.artists,
            eventID: eventID,
            into: db
        )

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
            description: performance.description,
            performanceRecordings: performance.performanceRecordings ?? []
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
