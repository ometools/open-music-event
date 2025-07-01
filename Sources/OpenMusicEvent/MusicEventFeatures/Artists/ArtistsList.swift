//
//  Artists.swift
//  open-music-event
//
//  Created by Woodrow Melling on 5/3/25.
//

import  SwiftUI; import SkipFuse
// import SharingGRDB
import CoreModels
import Dependencies

@MainActor
@Observable
public class ArtistsList {

    // MARK: Data
    // TODO: Replace @FetchAll with GRDB query
    var artists: [Artist] = []

    @ObservationIgnored
    @Dependency(\.musicEventID)
    var musicEventID

    // MARK: State
    var searchText: String = ""

    func searchTextDidChange() async {
        // TODO: Replace with GRDB query
        // let artistsSearchQuery = Current.artists
        //     .where {
        //         $0.name.collate(.nocase).contains(self.searchText)
        //     }
        //     .order(by: \.name)
        //     .group(by: \.id)
        //
        // await withErrorReporting {
        //     try await $artists.load(artistsSearchQuery)
        // }
    }

}



struct ArtistsListView: View {
    @Bindable var store: ArtistsList

    var body: some View {
        List(store.artists) { artist in
            NavigationLink(value: artist.id) {
                Row(artist: artist)
            }
        }
        .searchable(text: $store.searchText)
        .task(id: store.searchText) {
            await withDependencies(from: store) { @Sendable in
                await store.searchTextDidChange()
            }
        }
        .autocorrectionDisabled()
        #if os(iOS)
        .textInputAutocapitalization(.never)
        #endif
        .navigationTitle("Artists")
        .listStyle(.plain)
        .navigationDestination(for: Artist.ID.self) {
            ArtistDetailView(store: .init(artistID: $0))
        }

    }

    struct Row: View {
        init(artist: Artist) {
            self.artist = artist

            // TODO: Replace with GRDB query
            // let query = Performance.Artists
            //     .where { $0.artistID.eq(artist.id) }
            //     .join(Performance.all, on: { $0.performanceID.eq($1.id) })
            //     .join(Stage.all) { $1.stageID.eq($2.id) }
            //     .select { $2 }
            //
            // self._performanceStages = FetchAll(query)

        }

        var artist: Artist

        private var imageSize: CGFloat = 60

        // TODO: Replace @FetchAll with GRDB query
        var performanceStages: [Stage] = []


        @Environment(\.showArtistImages)
        var showArtistImages

        var body: some View {
            HStack(spacing: 10) {
                Group {
                    if artist.imageURL == nil && showArtistImages {
                        Artist.ImageView(artistID: artist.id)
                            .frame(square: 60)
                    } else {
                        ForEach(performanceStages) {
                            Stage.IconView(stageID: $0.id)
                                .frame(square: 60)
                        }
                    }
                }

                Stage.IndicatorView(colors: performanceStages.map(\.color))
                    .frame(width: 5, height: 60)

                Text(artist.name)
                    .lineLimit(1)

                Spacer()

//                if favoriteArtists[artist.id] {
//                    Image(systemName: "heart.fill")
//                        .resizable()
//                        .renderingMode(.template)
//                        .aspectRatio(contentMode: .fit)
//                        .frame(square: 15)
//                        .foregroundColor(.accentColor)
//                        .padding(.trailing)
//                }
            }
            .foregroundStyle(.primary)
        }
    }
}

private struct ShowArtistImagesKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var showArtistImages: Bool {
        get { self[ShowArtistImagesKey.self] }
        set { self[ShowArtistImagesKey.self] = newValue }
    }
}

extension View {
    func frame(square: CGFloat, alignment: Alignment = .center) -> some View {
        self.frame(width: square, height: square, alignment: alignment)
    }
}

//#Preview {
//    try! prepareDependencies {
//        $0.defaultDatabase = try appDatabase()
//    }
//
//    return NavigationStack {
//        ArtistsListView(store: .init())
//    }
//}
