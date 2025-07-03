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



@Observable
class ArtistDetail {
    init(artistID: Artist.ID) {
        self.artistID = artistID
        // TODO: Replace with GRDB query
        // self._artist = FetchOne(wrappedValue: .placeholder, Artist.find(artistID))
        // self._performances = FetchAll(ArtistDetail.performancesQuery(artistID))
    }

    let artistID: Artist.ID

    // TODO: Replace @FetchOne with GRDB query
    var artist: Artist = .placeholder


    // TODO: Replace @FetchAll with GRDB query
    var performances: [PerformanceDetailRow.ArtistPerformance] = []

    // TODO: Convert to GRDB query
    // static let performancesQuery = { @Sendable (artistID: Artist.ID) in
    //     Performance.Artists
    //         .where { $0.artistID == artistID }
    //         .join(Performance.all) { $0.performanceID.eq($1.id) }
    //         .join(Stage.all) { $1.stageID.eq($2.id) }
    //         .select {
    //             PerformanceDetailRow.ArtistPerformance.Columns(
    //                 id: $1.id,
    //                 stageID: $2.id,
    //                 startTime: $1.startTime,
    //                 endTime: $1.endTime,
    //                 title: $1.title,
    //                 stageColor: $2.color
    //             )
    //         }
    // }


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
                ArtistImage(artist: store.artist)

            },
            listContent: {
                ForEach(store.performances) { performance in
                    PerformanceDetailRow(performance: performance)
                }

                #if os(iOS)
                if let bio = bioMarkdown {
                    Text(bio)
                        .font(.body)
                }
                #endif

                // MARK: Socials
                if !store.artist.links.isEmpty {
                    Section("Links") {
                        ForEach(store.artist.links, id: \.url) { link in
//                            Text(link.url.absoluteString)
//                            NavigationLinkButton {
//                                store.send(.didTapURL(link.url))
//                            } label: {
//                                LinkView(link)
//                            }
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

//        .toolbar {
//            Toggle("Favorite", isOn: $store.favoriteArtists[store.artist.id])
//                .frame(square: 20)
//                .toggleStyle(FavoriteToggleStyle())
//        }
    }

    struct ArtistImage: View {
        let artist: Artist

        var body: some View {
            CachedAsyncImage(
                requests: [
                    ImageRequest(
                        url: artist.imageURL,
                        processors: [.resize(width: 440)]
                    )
                    .withPipeline(.images)
                ]
            ) {
                $0.resizable()
            } placeholder: {
                ProgressView().frame(square: 440)
            }
            .frame(maxWidth: .infinity)
        }
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
        fatalError()
        //        return Color(hex: self.rawValue)
    }
}
