//
//  OrganizerLoader.swift
//  open-music-event
//
//  Created by Woodrow Melling on 5/7/25.
//

import OpenMusicEventParser
import Dependencies
import DependenciesMacros
import  SwiftUI; import SkipFuse
import IssueReporting

@DependencyClient
struct DataFetchingClient {
    var fetchOrganizer: @Sendable (_ from: OrganizationReference) async throws -> OpenMusicEventParser.OrganizerConfiguration
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
                return baseURL.appendingPathComponent("archive/refs/heads/\(name).zip")
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

    try await notificationManager.ensureTopicsAreSubscribed()
}

extension OrganizerConfiguration {
    func insert(url: URL, into database: any DatabaseWriter) async throws {
        var info = self.info
        info.url = url

        try await database.write { [info] db in
            // Upsert organizer (preserves any local organizer state)
            try info.upsert(db)

            guard let organizerID = info.id
            else {
                reportIssue("We must have an organizerID after upserting")
                return
            }

            // Handle selective deletion for events
            let sourceEventIDs = Set(self.events.map { event in
                OmeID<MusicEvent>(stabilizedBy: url.absoluteString, event.info.name)
            })
            
            // Find existing events that should be deleted (exist in DB but not in source)
            let existingEvents = try MusicEvent
                .filter(Column("organizerID") == url)
                .fetchAll(db)
            let eventsToDelete = existingEvents.filter { !sourceEventIDs.contains($0.id) }
            
            // Delete orphaned events (CASCADE will handle related data)
            if !eventsToDelete.isEmpty {
                try MusicEvent.deleteAll(db, ids: eventsToDelete.map(\.id))
            }

            for event in self.events {
                var eventInfo = event.info
                let eventID: MusicEvent.ID = OmeID(stabilizedBy: organizerID.rawValue, eventInfo.name)
                eventInfo.organizerID = organizerID
                eventInfo.id = eventID

                try eventInfo.upsert(db)
                
                // Handle selective deletion for artists within this event
                let sourceArtistIDs = Set(event.artists.map { artist in
                    Artist.ID(stabilizedBy: String(eventID.rawValue), artist.name)
                })
                let existingArtists = try Artist.filter(Column("musicEventID") == eventID).fetchAll(db)
                let artistsToDelete = existingArtists.filter { !sourceArtistIDs.contains($0.id) }
                if !artistsToDelete.isEmpty {
                    try Artist.deleteAll(db, ids: artistsToDelete.map(\.id))
                }
                
                var artistNameIDMapping: [String: Artist.ID] = [:]

                for artist in event.artists {
                    let artistID = Artist.ID(stabilizedBy: String(eventID.rawValue), artist.name)
                    let artistDraft = Artist.Draft(
                        id: artistID,
                        musicEventID: eventID,
                        name: artist.name,
                        bio: artist.bio,
                        imageURL: artist.imageURL,
                        links: artist.links
                    )

                    try artistDraft.upsert(db)

                    artistNameIDMapping[artist.name] = artistID
                }

                // Handle selective deletion for channels within this event
                let sourceChannelIDs = Set(event.channels.map { channel in
                    CommunicationChannel.ID(stabilizedBy: eventID.rawValue, channel.info.name)
                })
                let existingChannels = try CommunicationChannel.filter(Column("musicEventID") == eventID).fetchAll(db)
                let channelsToDelete = existingChannels.filter { !sourceChannelIDs.contains($0.id) }
                if !channelsToDelete.isEmpty {
                    try CommunicationChannel.deleteAll(db, ids: channelsToDelete.map(\.id))
                }

                for channel in event.channels {
                    var channelInfo = channel.info
                    let channelID = CommunicationChannel.ID(stabilizedBy: eventID.rawValue, channelInfo.name)
                    channelInfo.id = channelID
                    channelInfo.musicEventID = eventID
                    
                    // Preserve user notification state if channel already exists
                    if let existingChannel = try CommunicationChannel.fetchOne(db, id: channelID) {
                        channelInfo.userNotificationState = existingChannel.userNotificationState
                    }

                    // Ensure a default
                    if channelInfo.userNotificationState == nil {
                        channelInfo.userNotificationState = channelInfo.defaultNotificationState
                    }

                    try channelInfo.upsert(db)
                    
                    // Handle selective deletion for posts within this channel
                    let sourcePostIDs = Set(channel.posts.map { post in
                        CommunicationChannel.Post.ID(stabilizedBy: channelID.rawValue, post.title)
                    })
                    let existingPosts = try CommunicationChannel.Post.filter(Column("channelID") == channelID).fetchAll(db)
                    let postsToDelete = existingPosts.filter { !sourcePostIDs.contains($0.id) }
                    if !postsToDelete.isEmpty {
                        try CommunicationChannel.Post.deleteAll(db, ids: postsToDelete.map(\.id))
                    }

                    for post in channel.posts {
                        var post = post
                        post.id = OmeID(stabilizedBy: channelID.rawValue, post.title)
                        post.channelID = channelID
                        try post.upsert(db)
                    }
                }

                func getOrCreateArtist(withName artistName: Artist.Name) throws -> Artist.ID {
                    if let artistID = artistNameIDMapping[artistName] {
                        return artistID
                    } else {

                        let artistID = Artist.ID(stabilizedBy: eventID.rawValue.lowercased(), artistName)
                        let draft = Artist.Draft(
                            id: artistID,
                            musicEventID: eventID,
                            name: artistName,
                            links: []
                        )

                        try draft.upsert(db)
                        return artistID
                    }
                }

                // Handle selective deletion for stages within this event
                let sourceStageIDs = Set(event.stages.map { stage in
                    Stage.ID(stabilizedBy: eventID.rawValue, stage.name)
                })
                let existingStages = try Stage.filter(Column("musicEventID") == eventID).fetchAll(db)
                let stagesToDelete = existingStages.filter { !sourceStageIDs.contains($0.id) }
                if !stagesToDelete.isEmpty {
                    try Stage.deleteAll(db, ids: stagesToDelete.map(\.id))
                }

                var stageNameIDMapping: [String: Stage.ID] = [:]

                for (index, stage) in event.stages.enumerated() {
                    let lineup = event.stageLineups?[stage.name]
                    let artistIDs = try lineup?.artists.compactMap { try getOrCreateArtist(withName: $0) }
                    let stageID = Stage.ID(stabilizedBy: eventID.rawValue, stage.name)
                    let stage = Stage.Draft(
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

                    try stage.upsert(db)

                    stageNameIDMapping[stage.name] = stageID
                }

                // Handle selective deletion for schedules within this event
                let sourceScheduleIDs = Set(event.schedule.map { schedule in
                    Schedule.ID(
                        stabilizedBy: String(eventID.rawValue),
                        (schedule.metadata.customTitle ?? schedule.metadata.startTime.description)
                    )
                })

                let existingSchedules = try Schedule.filter(Column("musicEventID") == eventID).fetchAll(db)
                let schedulesToDelete = existingSchedules.filter { !sourceScheduleIDs.contains($0.id) }
                if !schedulesToDelete.isEmpty {
                    try Schedule.deleteAll(db, ids: schedulesToDelete.map(\.id))
                }

                for schedule in event.schedule {
                    let scheduleID = Schedule.ID(
                        stabilizedBy: String(eventID.rawValue),
                        (schedule.metadata.customTitle ?? schedule.metadata.startTime.formatted(.dateTime.weekday(.short)))
                    )

                    let scheduleDraft = Schedule.Draft(
                        id: scheduleID,
                        musicEventID: eventID,
                        startTime: schedule.metadata.startTime,
                        endTime: schedule.metadata.endTime,
                        customTitle: schedule.metadata.customTitle
                    )

                    try scheduleDraft.upsert(db)
                    
                    // Handle selective deletion for performances within this schedule
                    let sourcePerformanceIDs = Set(schedule.stageSchedules.flatMap { stageSchedule in
                        stageSchedule.value.map { performance in
                            Performance.ID(
                                stabilizedBy: String(scheduleID.rawValue),
                                stageSchedule.key,
                                performance.title
                            )
                        }
                    })
                    let existingPerformances = try Performance.filter(Column("scheduleID") == scheduleID).fetchAll(db)
                    let performancesToDelete = existingPerformances.filter { !sourcePerformanceIDs.contains($0.id) }
                    if !performancesToDelete.isEmpty {
                        try Performance.deleteAll(db, ids: performancesToDelete.map(\.id))
                    }

                    for stageSchedule in schedule.stageSchedules {
                        for performance in stageSchedule.value {
                            let performanceID = Performance.ID(
                                stabilizedBy: String(scheduleID.rawValue),
                                stageSchedule.key,
                                performance.title
                            )
                            let draft = Performance.Draft(
                                // Stable for each performance **BUT*** will fail if an artist has two performances on the same stage on the same day
                                // Maybe we increment a counter if there are multiple?
                                id: performanceID,
                                stageID: stageNameIDMapping[stageSchedule.key]!,
                                scheduleID: scheduleID,
                                startTime: performance.startTime,
                                endTime: performance.endTime,
                                title: performance.title,
                                description: nil
                            )

                            try draft.upsert(db)
                            
                            // Handle selective deletion for performance artists
                            let sourcePerformanceArtistIDs = Set(performance.artistNames.compactMap { artistName in
                                try? getOrCreateArtist(withName: artistName)
                            })
                            let existingPerformanceArtists = try Performance.Artists.filter(Column("performanceID") == performanceID).fetchAll(db)
                            let performanceArtistsToDelete = existingPerformanceArtists.filter { performanceArtist in
                                guard let artistID = performanceArtist.artistID else { return false }
                                return !sourcePerformanceArtistIDs.contains(artistID)
                            }
                            if !performanceArtistsToDelete.isEmpty {
                                for performanceArtist in performanceArtistsToDelete {
                                    try db.execute(
                                        sql: "DELETE FROM performanceArtists WHERE performanceID = ? AND artistID = ?",
                                        arguments: [performanceArtist.performanceID, performanceArtist.artistID]
                                    )
                                }
                            }

                            for artistName in performance.artistNames {
                                let artistID = try getOrCreateArtist(withName: artistName)
                                let draft = Performance.Artists.Draft(
                                    performanceID: performanceID,
                                    artistID: artistID
                                )

                                let _ = try draft.upsert(db)
                            }
                        }
                    }
                }
            }



        }
    }
}

extension Array {
    public subscript(safe index: Index) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
