//
//  OrganizerLoader.swift
//  open-music-event
//
//  Created by Woodrow Melling on 5/7/25.
//

import OpenMusicEventParser
import Dependencies
import DependenciesMacros
import SwiftUI

@DependencyClient
struct DataFetchingClient {
    var fetchOrganizer: @Sendable (_ from: OrganizationReference) async throws -> OpenMusicEventParser.OrganizerConfiguration
}

struct FailedToLoadOrganizerError: Error {}
extension DataFetchingClient: DependencyKey {
    static let liveValue = DataFetchingClient { orgReference in
        let unzippedURL = URL.documentsDirectory
            .appending(path: "ome-zips")
            .appending(path: orgReference.zipURL.absoluteString)
        
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
        let contents = try fileManager.contentsOfDirectory(at: unzippedURL, includingPropertiesForKeys: nil)

        logger.info("Contents of \(unzippedURL): \(contents)")

        @Dependency(\.zipClient) var zipClient
        try zipClient.unzipFile(source: downloadURL, destination: unzippedURL)

        let finalDestination = try getUnzippedDirectory(from: unzippedURL)
        logger.info("Parsing organizer from directory: \(finalDestination)")

        var organizerData = try OrganizerConfiguration.fileTree.read(from: finalDestination)
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
    let fileURLs = try FileManager.default.contentsOfDirectory(
        at: zipURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: .skipsHiddenFiles
    )

    guard let directoryURL = fileURLs.first(where: { url in
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }) else {
        throw NSError(domain: "UnzipError", code: 1, userInfo: [NSLocalizedDescriptionKey: "No directory found in unzipped contents."])
    }

    return directoryURL
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

import Logging
import GRDB
extension Logger {
    init(subsystem: String, category: String) {
        self.init(label: subsystem + "." + category)
    }
}

private let logger = Logger(subsystem: "open-music-event.event-viewer", category: "OrganizerLoader")


extension String {
    var stableHash: Int {
        var result = UInt64 (5381)
        let buf = [UInt8](self.utf8)
        for b in buf {
            result = 127 * (result & 0x00ffffffffffffff) + UInt64(b)
        }
        return Int(result)
    }
}

extension OmeID where RawValue == Int {
    public init(stabilizedBy values: String...) {
        self.init(rawValue: values.joined(separator: "-").stableHash)
    }
}


func downloadAndStoreOrganizer(from reference: OrganizationReference) async throws {
    @Dependency(\.organizationFetchingClient) var dataFetchingClient
    @Dependency(\.defaultDatabase) var defaultDatabase
    let organizer: OrganizerConfiguration = try await dataFetchingClient.fetchOrganizer(reference)

    try await organizer.insert(url: reference.zipURL, into: defaultDatabase)
}

extension OrganizerConfiguration {
    func insert(url: URL, into database: any DatabaseWriter) async throws {
        var info = self.info
        info.url = url

        try await database.write { db in
            try Organizer.find(url)
                .delete()
                .execute(db)

            try Organizer.upsert { self.info }
                .execute(db)

            for event in self.events {

                var eventInfo = event.info
                eventInfo.organizerURL = url

                let eventID = try MusicEvent.insert { eventInfo }
                    .returning(\.id)
                    .fetchOne(db)!

                var artistNameIDMapping: [String: Artist.ID] = [:]

                for artist in event.artists {
                    let artistDraft = Artist.Draft(
                        id: OmeID(stabilizedBy: String(eventID.rawValue), artist.name),
                        musicEventID: eventID,
                        name: artist.name,
                        bio: artist.bio,
                        imageURL: artist.imageURL,
                        links: artist.links
                    )

                    let artistID = try Artist.upsert { artistDraft }
                        .returning(\.id)
                        .fetchOne(db)!

                    artistNameIDMapping[artist.name] = artistID
                }

                func getOrCreateArtist(withName artistName: Artist.Name) throws -> Artist.ID {
                    if let artistID = artistNameIDMapping[artistName] {
                        artistID
                    } else {
                        try Artist.upsert {
                            Artist.Draft(
                                id: OmeID(stabilizedBy: String(eventID.rawValue).lowercased(), artistName),
                                musicEventID: eventID,
                                name: artistName,
                                links: []
                            )
                        }
                        .returning(\.id)
                        .fetchOne(db)!
                    }

                }
                var stageNameIDMapping: [String: Stage.ID] = [:]


                for (index, stage) in event.stages.enumerated() {
                    let lineup = event.stageLineups?[stage.name]
                    let artistIDs = try lineup?.artists.compactMap { try getOrCreateArtist(withName: $0) }

                    let stage = Stage.Draft(
                        id: Stage.ID(rawValue: (String(eventID.rawValue) + stage.name).stableHash),
                        musicEventID: eventID,
                        name: stage.name,
                        sortIndex: index,
                        iconImageURL: stage.iconImageURL,
                        imageURL: stage.imageURL,
                        color: stage.color,
                        posterImageURL: stage.posterImageURL,
                        lineup: artistIDs
                    )

                    let stageID = try Stage.upsert { stage }
                        .returning(\.id)
                        .fetchOne(db)!

                    stageNameIDMapping[stage.name] = stageID
                }

                for schedule in event.schedule {
                    let draft = Schedule.Draft(
                        id: .init(
                            stabilizedBy: String(eventID.rawValue),
                            (schedule.metadata.customTitle ?? schedule.metadata.startTime?.description ?? UUID().uuidString)
                        ),
                        musicEventID: eventID,
                        startTime: schedule.metadata.startTime,
                        endTime: schedule.metadata.endTime,
                        customTitle: schedule.metadata.customTitle
                    )

                    let scheduleID = try Schedule.upsert { draft }
                        .returning(\.id)
                        .fetchOne(db)

                    for stageSchedule in schedule.stageSchedules {
                        for performance in stageSchedule.value {
                            let draft = Performance.Draft(
                                // Stable for each performance **BUT*** will fail if an artist has two performances on the same stage on the same day
                                // Maybe we increment a counter if there are multiple?
                                id: .init(
                                    stabilizedBy: scheduleID.map { String($0.rawValue) } ?? "",
                                    stageSchedule.key,
                                    performance.title
                                ),
                                stageID: stageNameIDMapping[stageSchedule.key]!,
                                scheduleID: scheduleID,
                                startTime: performance.startTime,
                                endTime: performance.endTime,
                                title: performance.title,
                                description: nil
                            )

                            let performanceID = try Performance.upsert { draft }
                                .returning(\.id)
                                .fetchOne(db)!

                            for artistName in performance.artistNames {
                                let artistID = try getOrCreateArtist(withName: artistName)

                                let draft = Performance.Artists.Draft(
                                    performanceID: performanceID,
                                    artistID: artistID
                                )

                                try Performance.Artists.insert { draft }
                                    .execute(db)
                            }
                        }
                    }
                }
            }
        }
    }
}
