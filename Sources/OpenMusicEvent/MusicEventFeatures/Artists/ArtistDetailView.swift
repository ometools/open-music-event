//
//  ArtistDetailView.swift
//  event-viewer
//
//  Created by Woodrow Melling on 2/21/25.
//

import  SwiftUI; import SkipFuse
// import SharingGRDB
import GRDB
import CoreModels
import Dependencies

extension Artist {
    static let placeholder = Artist(
        id: .init(""),
        musicEventID: nil,
        name: "",
        bio: "",
        imageURL: nil,
        logoURL: nil,
        kind: nil,
        links: []
    )
}


@MainActor
@Observable
class ArtistDetail {
    init(artistID: Artist.ID) {
        self.artistID = artistID
    }

    let logger = Logger(subsystem: "bundle.ome.OpenMusicEvent", category: "ArtistDetailPage")

    @ObservationIgnored
    @Dependency(\.defaultDatabase) var db

    @ObservationIgnored
    @Dependency(\.organizerID) var organizerID

    func task() async {
        let artistID = self.artistID
        let organizerID = self.organizerID

        let combinedQuery = ValueObservation.tracking { db in
            // Fetch artist
            let artist = try Artist.find(db, id: artistID)

            // Fetch artist preference from userprefs
            let isFavorite = try Bool.fetchOne(db, sql: """
                SELECT COALESCE(isFavorite, 0)
                FROM userprefs.artistPreferences
                WHERE organizerID = ? AND artistID = ?
                """, arguments: [organizerID.rawValue, artistID.rawValue]) ?? false

            // Fetch performances with stage and performance preferences
            let performances = try Row.fetchAll(db, sql: """
                SELECT
                    p.id as id,
                    p.stageID as stageID,
                    p.startTime as startTime,
                    p.endTime as endTime,
                    p.title as title,
                    s.color as stageColor,
                    COALESCE(pp.seen, 0) as isSeen
                FROM performanceArtists pa
                JOIN performances p ON pa.performanceID = p.id
                JOIN stages s ON p.stageID = s.id
                LEFT JOIN userprefs.performancePreferences pp
                    ON p.id = pp.performanceID AND pp.organizerID = ?
                WHERE pa.artistID = ?
                ORDER BY p.startTime ASC
                """, arguments: [organizerID.rawValue, artistID.rawValue]
            ).map { row in
                PerformanceDetailRow.ArtistPerformance(
                    id: OmeID(row["id"]),
                    stageID: OmeID(row["stageID"]),
                    startTime: row["startTime"] as Date,
                    endTime: row["endTime"] as Date,
                    title: row["title"],
                    stageColor: OMEColor(rawValue: row["stageColor"]),
                    isSeen: row["isSeen"] ?? false
                )
            }

            return (artist, performances, isFavorite)
        }

        await withErrorReporting {
            for try await (artist, performances, isFavorite) in combinedQuery.values(in: db) {
                logger.info("Selected Artist: \(artist.name) with: \(performances)")
                self.artist = artist
                self.performances = performances
                self.isFavorite = isFavorite
            }
        }
    }

    @ObservationIgnored
    @Dependency(\.defaultDatabase) var database

    func toggleFavorite() async {
        let organizerID = self.organizerID

        await withErrorReporting {
            try await database.write { db in
                try Artist.Preferences.toggleFavorite(for: self.artistID, organizerID: organizerID, in: db)
            }
        }
    }

    let artistID: Artist.ID
    var artist: Artist = .placeholder
    var performances: [PerformanceDetailRow.ArtistPerformance] = []
    var isFavorite: Bool = false
}


extension Artist.Preferences {
    static func toggleFavorite(for artistID: Artist.ID, organizerID: Organizer.ID, in db: Database) throws {
        try db.execute(sql: """
            INSERT INTO userprefs.artistPreferences (organizerID, artistID, isFavorite)
            VALUES (?, ?, 1)
            ON CONFLICT(organizerID, artistID) DO UPDATE SET
            isFavorite = 1 - isFavorite
            """,
           arguments: [organizerID.rawValue, artistID.rawValue]
        )
    }
}



struct ArtistDetailView: View {
    var store: ArtistDetail

    var meshColors: [Color] {
        store.performances.map(\.stageColor.swiftUIColor)
    }

    var body: some View {
        
        StretchyHeaderList(
            title: Text(store.artist.name),
            stretchyContent: {
                CachedAsyncImage(url: store.artist.imageURL)
//                ArtistImageView(artist: store.artist) {
//                    if let stage = store.performances.compactMap(\.stageID).first {
//                        StageImageView(stageID: stage)
//                    }
//                }
            },
            listContent: {
                ForEach(store.performances) { performance in
                    PerformanceDetailRow(performance: performance)
                }

                if let bioString = store.artist.bio {
                    MarkdownText(bioString)
                }

                // MARK: Socials
                if !store.artist.links.isEmpty {
                    Section("Links") {
                        ForEach(store.artist.links, id: \.url) { link in
                            ArtistLinkView(link: link)
                        }
                    }
                }
            }
        )
        .listStyle(.plain)
        .task(id: store.artist.id) { await self.store.task() }
        .id(store.artist.id)
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await store.toggleFavorite() }
                } label: {
                    Image(systemName: store.isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(store.isFavorite ? .red : .primary)
                }
            }
        }
    }
}


struct ArtistLinkView: View {
    var link: ExternalPlatform.Link
    @Environment(\.openURL) var openURL

    var body: some View {
        Button {
            var urlToOpen = link.url
            if urlToOpen.scheme == nil {
                urlToOpen = URL(string: "https://\(urlToOpen.absoluteString)")!
            }
            self.openURL(urlToOpen)
        } label: {
            HStack(spacing: 12) {
                if let platform = link.platform {
                    platform.icon?
                        .resizable()
                        .frame(width: 24, height: 24)
                        .foregroundStyle(.secondary)

                    Text(platform.name)
                        .foregroundStyle(.primary)
                }

                Spacer()

                Icons.externalLink
                    .font(.caption)
                    .foregroundStyle(.secondary)
//                    .foregroundStyle(.tertiary)
            }
            #if !os(Android)
            .contentShape(Rectangle())
            #endif
        }
        .buttonStyle(.plain)
//        .contentShape(Rectangle())
    }
}
//
//#Preview {
//    try! prepareDependencies {
//        $0.defaultDatabase = try appDatabase()
//    }
//
//    return ArtistDetailView(store: .init(artistID: 0))
//}

public extension OMEColor {
    var swiftUIColor: SwiftUI.Color {
        return Color(
            red: Double((self.rawValue >> 16) & 0xFF) / 255.0,
            green: Double((self.rawValue >> 8) & 0xFF) / 255.0,
            blue: Double(self.rawValue & 0xFF) / 255.0
        )
    }
}

public extension Artist.Kind {
    var symbol: some View {
        switch self.type {
        case "dj": Image(systemName: "person")
        default:
            Image(systemName: "person")
        }
    }
}


struct MarkdownText: View {
    init(_ text: String) {
        self.text = text
    }
    var text: String

    var body: some View {
        #if os(Android)
        // Skip seems to render markdown rather nicely without having to go through AttributedString,
        Text(text)
        #else
        if let bioMarkdown = try? AttributedString(
            markdown: text,
            options: .init(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            Text(bioMarkdown)
        } else {
            Text(text)
        }
        #endif
    }
}
