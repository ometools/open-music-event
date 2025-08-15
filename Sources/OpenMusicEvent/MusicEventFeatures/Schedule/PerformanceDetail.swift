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
    struct Simple: Codable {
        var id: Artist.ID
        var name: String
        var imageURL: URL?
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

    init(
        id: ID,
        title: String,
        stageID: Stage.ID,
        startTime: Date,
        endTime: Date,
        description: String?,
        stageColor: OMEColor,
        stageName: String,
        stageIconImageURL: URL?
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
            stageIconImageURL: stageImageURLString.flatMap(URL.init(string:))
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
        stageIconImageURL: nil
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
                s.iconImageURL as stageIconImageURL
            FROM performances p
            JOIN stages s ON p.stageID = s.id
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
}

public struct PerformancePeekView: View {

    init(performance: PerformanceDetail, performingArtists: [Artist]) {
        self.performance = performance
        self.performingArtists = performingArtists
        self.performanceID = performance.id
    }

    init(id: Performance.ID) {
        self.performanceID = id
    }

    let performanceID: Performance.ID
    @State var performance: PerformanceDetail = .empty
    @State var performingArtists: [Artist] = []
    @Environment(\.calendar) var calendar

    var timeIntervalLabel: String {
        (performance.startTime..<performance.endTime)
            .formatted(.performanceTime(calendar: calendar))
    }

    public var body: some View {
        
        VStack {
            Text(performance.title)
                .scaledToFill()
#if os(iOS)
                .minimumScaleFactor(0.5)
#endif
                .frame(maxWidth: .infinity)
                .lineLimit(nil)
                .multilineTextAlignment(.center)
                .font(.largeTitle.weight(.bold))

            HStack {
                StageIconView(stageID: performance.stageID)
                    .frame(square: 60)
                    .background {
                        Circle()
                            .fill(performance.stageColor.swiftUIColor)
                            .shadow()
                    }


                VStack(alignment: .center, spacing: 16) {

                    VStack(alignment: .leading) {
                        Text(performance.startTime.formatted(.daySegment))
                        //                            .font(.thin)
                            .fontWeight(.thin)

                        Label {
                            Text(timeIntervalLabel)
                                .textCase(.lowercase)
                                .fontWeight(.bold)
                        } icon: {
                            Image(systemName: "clock")
                        }

                        Text(performance.stageName)
                            .fontWeight(.thin)
                    }

                    //                        .offset(x: 30)

                    //                            .font(.title)
                    //                            .font(.)
                    //                            .fontWeight(.thin)
                }

                //                Spacer(minLength: 24)



            }

            if let description = performance.description, !description.isEmpty {
                Text("Blah Blah Blah")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .task {
            @Dependency(\.defaultDatabase) var database
            
            do {
                let loadedPerformance = try await database.read { db in
                    try PerformanceDetail.find(id: performanceID).fetchOne(db)
                }
                let loadedArtists = try await database.read { db in
                    try PerformanceDetail.findPerformingArtists(performanceID: performanceID).fetchAll(db)
                }
                
                if let loadedPerformance {
                    performance = loadedPerformance
                }
                performingArtists = loadedArtists
            } catch {
                print("Error loading performance data: \(error)")
            }
        }
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
                stageColor: performance.stageColor
            )
        )
    }
}

public struct PerformanceDetailView: View {

    init(performance: PerformanceDetail, performingArtists: [Artist]) {
        self.performance = performance
        self.performingArtists = performingArtists
        self.performanceID = performance.id
    }

    init(id: Performance.ID) {
        self.performanceID = id
    }

    let performanceID: Performance.ID
    @State var performance: PerformanceDetail = .empty
    @State var performingArtists: [Artist] = []


    @Environment(\.calendar) var calendar
    var timeIntervalLabel: String {
        (performance.startTime..<performance.endTime)
            .formatted(.performanceTime(calendar: calendar))
    }

    @Environment(\.dismiss) var dismiss
    @State var artistDetail: ArtistDetail?

    func didTapGoToArtist(_ id: Artist.ID) {
        artistDetail = .init(artistID: id)
    }

    var hasUnnamedArtists: Bool {
        !performingArtists.allSatisfy {
            performance.title.contains($0.name)
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
                ForEach(performingArtists) { artist in
                    NavigationLinkButton {
                        didTapGoToArtist(artist.id)
                    } label: {
                        HStack(spacing: 10) {
                            ArtistImageView(artist: artist) {
                                Image(systemName: "person")
                            }
                            .frame(square: 60)
                            .clipped()

                            Text(artist.name)
                        }
                    }
                }
            }
        }
        .navigationDestination(item: $artistDetail) {
            ArtistDetailView(store: $0)
        }
        .task {
            @Dependency(\.defaultDatabase) var database

            do {
                let loadedPerformance = try await database.read { db in
                    try PerformanceDetail.find(id: performanceID).fetchOne(db)
                }
                let loadedArtists = try await database.read { db in
                    try PerformanceDetail.findPerformingArtists(performanceID: performanceID).fetchAll(db)
                }

                if let loadedPerformance {
                    performance = loadedPerformance
                }
                performingArtists = loadedArtists
            } catch {
                print("Error loading performance data: \(error)")
            }
        }
        .listStyle(.plain)

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
            stageIconImageURL: Stage.previewValues.first?.iconImageURL
        )
    }
}
