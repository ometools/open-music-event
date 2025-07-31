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

    public let stageColor: OMEColor
    public let stageName: String
    public let stageImageURL: URL?
    
    init(
        id: ID,
        title: String,
        stageID: Stage.ID,
        startTime: Date,
        endTime: Date,
        stageColor: OMEColor,
        stageName: String,
        stageImageURL: URL?
    ) {
        self.id = id
        self.title = title
        self.stageID = stageID
        self.startTime = startTime
        self.endTime = endTime
        self.stageColor = stageColor
        self.stageName = stageName
        self.stageImageURL = stageImageURL
    }
    
    init(row: Row) throws {
        let stageImageURLString: String? = row["stageImageURL"]
        
        self.init(
            id: OmeID(row["id"]),
            title: row["title"],
            stageID: OmeID(row["stageID"]),
            startTime: row["startTime"],
            endTime: row["endTime"],
            stageColor: OMEColor(rawValue: row["stageColor"]),
            stageName: row["stageName"],
            stageImageURL: stageImageURLString.flatMap(URL.init(string:))
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
        stageColor: .init(0),
        stageName: "",
        stageImageURL: nil
    )


    // TODO: Replace with GRDB query
    // static let find = { @Sendable (id: Performance.ID) in
    //     Performance
    //         .find(id)
    //         .join(Stage.all) { $0.stageID.eq($1.id) }
    //         .select {
    //             PerformanceDetail.Columns(
    //                 id: $0.id,
    //                 title: $0.title,
    //                 stageID: $0.stageID,
    //                 startTime: $0.startTime,
    //                 endTime: $0.endTime,
    //                 stageColor: $1.color,
    //                 stageName: $1.name,
    //                 stageImageURL: $1.iconImageURL
    //             )
    //         }
    // }
}

public struct PerformanceScheduleDetailView: View {

    init(performance: PerformanceDetail, performingArtists: [Artist]) {
        self.performance = performance
        self.performingArtists = performingArtists
    }

    init(id: Performance.ID) {
        // TODO: Replace with GRDB queries
        // self._performance = FetchOne(wrappedValue: .empty, PerformanceDetail.find(id))
        // self._performingArtists = FetchAll(
        //     Performance.find(id)
        //         .join(Performance.Artists.all) { $0.id == $1.performanceID }
        //         .join(Artist.all) { $1.artistID.eq($2.id) }
        //         .select { $2 }
        // )
    }

    // TODO: Replace @FetchOne with GRDB query
    var performance: PerformanceDetail = .empty


    // TODO: Replace @FetchAll with GRDB query
    var performingArtists: [Artist] = []

    var timeIntervalLabel: String {
        (performance.startTime..<performance.endTime)
            .formatted(.performanceTime)
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

                if performingArtists.count == 1, let firstArtist = performingArtists.first {
                    ArtistImageView(artist: firstArtist) {
                        ProgressView()
                    }
                    .frame(square: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .center, spacing: 16) {

                    VStack {
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


                StageIconView(stageID: performance.stageID)
                    .frame(square: 60)
                    .background {
                        Circle()
                            .fill(performance.stageColor.swiftUIColor)
                            .shadow()
                    }
            }
        }
        .padding()
        .background(
            AnimatedMeshView()
            //                .overlay(Material.thinMaterial)
                .opacity(0.25)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
//        Performance.ScheduleDetailView(
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
            title: "Overgrowth",
            stageID: "1",
            startTime: Date(hour: 22, minute: 30)!,
            endTime: Date(hour: 23, minute: 30)!,
            stageColor: 0,
            stageName: "The Hallow",
            stageImageURL: Stage.previewValues.first?.iconImageURL
        )
    }
}
