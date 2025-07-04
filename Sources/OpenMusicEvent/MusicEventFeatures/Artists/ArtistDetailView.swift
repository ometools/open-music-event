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
        id: .init(0),
        musicEventID: nil,
        name: "",
        bio: "",
        imageURL: nil,
        links: []
    )
}



@MainActor
@Observable
class ArtistDetail {
    init(artistID: Artist.ID) {
        self.artistID = artistID
        // TODO: Replace with GRDB query
        // self._artist = FetchOne(wrappedValue: .placeholder, Artist.find(artistID))
        // self._performances = FetchAll(ArtistDetail.performancesQuery(artistID))
    }


    @MainActor
    func onAppear() async {
        let combinedQuery = ValueObservation.tracking { db in
            let artist = try Artist.find(db, id: self.artistID)
            let performances = try self.fetchPerformances(db: db)
            return (artist, performances)
        }

        await withErrorReporting {
            for try await (artist, performances) in combinedQuery.values() {
                self.artist = artist
                self.performances = performances
            }
        }
    }

    let artistID: Artist.ID

    // TODO: Replace @FetchOne with GRDB query
    var artist: Artist = .placeholder


    var performances: [PerformanceDetailRow.ArtistPerformance] = []


    nonisolated private func fetchPerformances(db: Database) throws -> [PerformanceDetailRow.ArtistPerformance] {
        let sql = """
            SELECT 
                p.id as id,
                p.stageID as stageID,
                p.startTime as startTime,
                p.endTime as endTime,
                p.title as title,
                s.color as stageColor
            FROM performanceArtists pa
            JOIN performances p ON pa.performanceID = p.id
            JOIN stages s ON p.stageID = s.id
            WHERE pa.artistID = ?
            ORDER BY p.startTime ASC
        """
        
        return try Row.fetchAll(db, sql: sql, arguments: [artistID.rawValue]).map { row in
            let startTimeString: String = row["startTime"]
            let endTimeString: String = row["endTime"]
            
            return PerformanceDetailRow.ArtistPerformance(
                id: OmeID(row["id"]),
                stageID: OmeID(row["stageID"]),
                startTime: ISO8601DateFormatter().date(from: startTimeString) ?? Date(),
                endTime: ISO8601DateFormatter().date(from: endTimeString) ?? Date(),
                title: row["title"],
                stageColor: OMEColor(rawValue: row["stageColor"])
            )
        }
    }


//        static func performances(for artistID: Artist.ID) -> some StructuredQueriesCore.Statement<PerformanceDetail> {
//            fatalError()
////            Artist.performances(artistID)
//                .join(Stage.all) { $0.id.eq($0.stageID) }
//                .select {
//                    PerformanceDetail.Columns(
//                        id: $1.0.id,
//                        stageID: $1.0.stageID,
//                        startTime: $1.0.startTime,
//                        endTime: $1.0.endTime,
//                        customTitle: $1.0.customTitle,
//                        stageColor: $1.1.color
//                    )
//                }
//        }

}




struct ArtistDetailView: View {
    let store: ArtistDetail

    var bioMarkdown: AttributedString? {
        guard let bio = store.artist.bio, !bio.isEmpty
        else { return nil }

        #if os(Android)
        return nil
        #else
        return try? AttributedString(
            markdown: bio,
            options: .init(failurePolicy: .returnPartiallyParsedIfPossible)
        )
        #endif
    }

    var meshColors: [Color] {
        store.performances.map(\.stageColor.swiftUIColor)
    }

    var body: some View {
        StretchyHeaderList(
            title: Text(store.artist.name),
            stretchyContent: {
                ArtistImageView(artist: store.artist)
            },
            listContent: {
                ForEach(store.performances) { performance in
                    PerformanceDetailRow(performance: performance)
                }

                #if os(iOS)
                if let bio = bioMarkdown {
                    Text(bio)
                        .font(.body)
                } else if let bioString = store.artist.bio {
                    Text(bioString)
                }
                #elseif os(Android)
                if let bioString = store.artist.bio {
                    Text(bioString)
                }
                #endif

                // MARK: Socials
                if !store.artist.links.isEmpty {
                    Section("Links") {
                        ForEach(store.artist.links, id: \.url) { link in
                            Link(link.url.absoluteString, destination: link.url)
                                #if os(iOS)
                                .foregroundStyle(.tint)
                                #endif
                        }
                    }
                    
                }
            }
        )
        .listStyle(.plain)
        .onAppear { Task { await self.store.onAppear() }}

//        .toolbar {
//            Toggle("Favorite", isOn: $store.favoriteArtists[store.artist.id])
//                .frame(square: 20)
//                .toggleStyle(FavoriteToggleStyle())
//        }
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
