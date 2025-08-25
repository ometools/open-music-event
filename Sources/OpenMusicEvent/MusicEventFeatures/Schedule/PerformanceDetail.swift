//
//  PerformanceDetail.swift
//  open-music-event
//
//  Created by Woodrow Melling on 5/14/25.
//

import  SwiftUI; import SkipFuse
// import SharingGRDB
import Dependencies
import GRDB
import CoreModels

extension Artist {
//    @Selection
    struct Simple: Codable, FetchableRecord {
        var id: Artist.ID
        var name: String
        var imageURL: URL?
        var isFavorite: Bool


        init(row: Row) throws {
            id = OmeID(row["id"])
            name = row["name"]
            if let urlString: String = row["imageURL"] {
                imageURL = URL(string: urlString)
            } else {
                imageURL = nil
            }
            self.isFavorite = row["isFavorite"]
        }
    }


    // TODO: Replace with GRDB query
    // static let simple = Artist.select {
    //     Artist.Simple.Columns(
    //         id: $0.id,
    //         name: $0.name,
    //         imageURL: $0.imageURL
    //     )
    // }
}

//@Selection
struct PerformanceDetail: Identifiable, FetchableRecord {
    public typealias ID = OmeID<Performance>
    public let id: ID

    public let title: String
    public let stageID: Stage.ID

    public let startTime: Date
    public let endTime: Date
    public let description: String?

    public let stageColor: OMEColor
    public let stageName: String
    public let stageIconImageURL: URL?
    public let isSeen: Bool

    init(
        id: ID,
        title: String,
        stageID: Stage.ID,
        startTime: Date,
        endTime: Date,
        description: String?,
        stageColor: OMEColor,
        stageName: String,
        stageIconImageURL: URL?,
        isSeen: Bool = false
    ) {
        self.id = id
        self.title = title
        self.stageID = stageID
        self.startTime = startTime
        self.endTime = endTime
        self.description = description
        self.stageColor = stageColor
        self.stageName = stageName
        self.stageIconImageURL = stageIconImageURL
        self.isSeen = isSeen
    }
    
    init(row: Row) throws {
        let stageImageURLString: String? = row["stageIconImageURL"]

        self.init(
            id: OmeID(row["id"]),
            title: row["title"],
            stageID: OmeID(row["stageID"]),
            startTime: row["startTime"],
            endTime: row["endTime"],
            description: row["description"],
            stageColor: OMEColor(rawValue: row["stageColor"]),
            stageName: row["stageName"],
            stageIconImageURL: stageImageURLString.flatMap(URL.init(string:)),
            isSeen: row["isSeen"] ?? false
        )
    }

    struct SimpleArtist: Codable {
        var id: Artist.ID
        var name: String
    }

    static let empty: Self = .init(
        id: "",
        title: "",
        stageID: "",
        startTime: Date(),
        endTime: Date(),
        description: nil,
        stageColor: .init(0),
        stageName: "",
        stageIconImageURL: nil,
        isSeen: false
    )


    static func find(id: Performance.ID) -> SQLRequest<PerformanceDetail> {
        let sql = """
            SELECT 
                p.id,
                p.title,
                p.stageID,
                p.startTime,
                p.endTime,
                p.description,
                s.color as stageColor,
                s.name as stageName,
                s.iconImageURL as stageIconImageURL,
                COALESCE(pp.seen, 0) as isSeen
            FROM performances p
            JOIN stages s ON p.stageID = s.id
            LEFT JOIN performancePreferences pp ON p.id = pp.performanceID
            WHERE p.id = ?
        """
        return SQLRequest<PerformanceDetail>(sql: sql, arguments: [id])
    }
    
    static func findPerformingArtists(performanceID: Performance.ID) -> SQLRequest<Artist> {
        let sql = """
            SELECT a.*
            FROM artists a
            JOIN performanceArtists pa ON a.id = pa.artistID
            WHERE pa.performanceID = ?
        """
        return SQLRequest<Artist>(sql: sql, arguments: [performanceID])
    }
    
    static func findPerformingArtistsWithFavorites(performanceID: Performance.ID) -> SQLRequest<Artist.Simple> {
        let sql = """
            SELECT 
                a.id,
                a.name,
                a.imageURL,
                COALESCE(ap.isFavorite, 0) as isFavorite
            FROM artists a
            JOIN performanceArtists pa ON a.id = pa.artistID
            LEFT JOIN artistPreferences ap ON a.id = ap.artistID
            WHERE pa.performanceID = ?
        """
        return SQLRequest<Artist.Simple>(sql: sql, arguments: [performanceID])
    }
}

extension PerformanceDetailRow {
    init(performance: PerformanceDetail) {
        self.init(
            performance: .init(
                id: performance.id,
                stageID: performance.stageID,
                startTime: performance.startTime,
                endTime: performance.endTime,
                title: performance.title,
                stageColor: performance.stageColor,
                isSeen: performance.isSeen
            )
        )
    }
}

public struct PerformanceDetailView: View {

    init(performance: PerformanceDetail, performingArtists: [Artist.Simple]) {
        self.performance = performance
        self.performingArtists = performingArtists
        self.performanceID = performance.id
    }

    init(id: Performance.ID) {
        self.performanceID = id
    }

    let performanceID: Performance.ID
    @State var performance: PerformanceDetail = .empty
    @State var performingArtists: [Artist.Simple] = []


    @Environment(\.calendar) var calendar
    var timeIntervalLabel: String {
        (performance.startTime..<performance.endTime)
            .formatted(.performanceTime(calendar: calendar))
    }

    @Environment(\.dismiss) var dismiss
    @State var artistDetail: ArtistDetail?
    
    @Dependency(\.defaultDatabase) var database

    func didTapGoToArtist(_ id: Artist.ID) {
        artistDetail = .init(artistID: id)
    }
    
    func toggleSeen() async {
        await withErrorReporting {
            try await database.write { db in
                try Performance.Preferences.toggleSeen(for: performanceID, in: db)
            }
        }
    }

    var hasUnnamedArtists: Bool {
        !performingArtists.allSatisfy {
            performance.title.contains($0.name)
        }
    }
    
    var hasFavoriteArtists: Bool {
        performingArtists.contains { $0.isFavorite }
    }

    func task() async {
        let query = ValueObservation.tracking { db in
            let loadedPerformance = try PerformanceDetail.find(id: self.performanceID).fetchOne(db)
            let loadedArtists = try PerformanceDetail.findPerformingArtistsWithFavorites(performanceID: self.performanceID).fetchAll(db)
            return (loadedPerformance, loadedArtists)
        }
        
        await withErrorReporting {
            for try await (loadedPerformance, loadedArtists) in query.values() {
                if let loadedPerformance {
                    performance = loadedPerformance
                }
                performingArtists = loadedArtists
            }
        }
    }

    public var body: some View {
        StretchyHeaderList(title: Text(performance.title)) {
            if let performerImageURL = performingArtists.first?.imageURL, performingArtists.count == 1 {
                CachedAsyncImage(url: performerImageURL)
            } else {
                CachedAsyncImage(url: performance.stageIconImageURL)
            }
        } listContent: {
            Section {
                if let description = performance.description, !description.isEmpty {
                    Section {
                        MarkdownText(description)
                            .font(.body)
                    }
                }

                HStack(spacing: 10) {
                    // Stage Icon
                    StageIconView(stageID: performance.stageID)
                        .frame(square: 60)
                        .foregroundStyle(Color.white)
                        .background {
                            Circle()
                                .fill(performance.stageColor.swiftUIColor)
                                .shadow(radius: 3)
                        }

                    Text(performance.stageName)
                }

                HStack(spacing: 10) {
                    Image(systemName: "clock")
                        .frame(square: 60)

                    VStack(alignment: .leading) {
                        Text(timeIntervalLabel)
                            .font(.body)
                        Text(performance.startTime.formatted(.daySegment))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section {
                ForEach(performingArtists, id: \.id) { artist in
                    NavigationLinkButton {
                        didTapGoToArtist(artist.id)
                    } label: {
                        ArtistsListView.Row(id: artist.id)
                    }
                }
            }
        }
        .navigationDestination(item: $artistDetail) {
            ArtistDetailView(store: $0)
        }
        .task { await task() }
        .listStyle(.plain)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await toggleSeen() }
                } label: {
                    performance.isSeen ? Icons.seenOn : Icons.seenOff
                }
            }
        }
    }



}


//
//#Preview("Context Menu") {
//    try! prepareDependencies {
//        $0.defaultDatabase = try appDatabase()
//    }
//
//    return Performance.ScheduleDetailView(
//        performance: .preview,
//        performingArtists: []
//    )
//        
//}
//
//#Preview("Material Popover") {
//    ZStack {
//        Color.black.opacity(0.2).ignoresSafeArea()
//        PerformancePeekView(
//            performance: .preview,
//            performingArtists: []
//        )
//            .padding()
//            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
//            .padding()
//    }
//}

extension PerformanceDetail {
    static var preview: PerformanceDetail {
        PerformanceDetail(
            id: "",
            title: "Overgrow",
            stageID: "1",
            startTime: Date(hour: 22, minute: 30)!,
            endTime: Date(hour: 23, minute: 30)!,
            description: "An immersive electronic music experience blending organic soundscapes with cutting-edge production. Prepare for a journey through dense sonic forests where every beat pulses with life.",
            stageColor: 0,
            stageName: "The Hallow",
            stageIconImageURL: Stage.previewValues.first?.iconImageURL,
            isSeen: false
        )
    }
}
