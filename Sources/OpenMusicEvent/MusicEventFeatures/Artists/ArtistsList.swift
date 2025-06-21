//
//  Artists.swift
//  open-music-event
//
//  Created by Woodrow Melling on 5/3/25.
//

import SwiftUI
import SharingGRDB
import ImageCaching
import CoreModels

@MainActor
@Observable
public class ArtistsList {

    // MARK: Data
    @ObservationIgnored
    @FetchAll
    var artists: [Artist]

    @ObservationIgnored
    @Dependency(\.musicEventID)
    var musicEventID

    // MARK: State
    var searchText: String = ""

    func searchTextDidChange() async {
        let artistsSearchQuery = Current.artists
            .where {
                $0.name.collate(.nocase).contains(self.searchText)
            }
            .order(by: \.name)
            .group(by: \.id)


        await withErrorReporting {
            try await $artists.load(artistsSearchQuery)
        }
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

            let query = Performance.Artists
                .where { $0.artistID.eq(artist.id) }
                .join(Performance.all, on: { $0.performanceID.eq($1.id) })
                .join(Stage.all) { $1.stageID.eq($2.id) }
                .select { $2 }


            self._performanceStages = FetchAll(query)

        }

        var artist: Artist

        private var imageSize: CGFloat = 60

        @FetchAll
        var performanceStages: [Stage]


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

extension EnvironmentValues {
    @Entry var showArtistImages = true
}

extension View {
    func frame(square: CGFloat, alignment: Alignment = .center) -> some View {
        self.frame(width: square, height: square, alignment: alignment)
    }
}

#Preview {
    try! prepareDependencies {
        $0.defaultDatabase = try appDatabase()
    }

    return NavigationStack {
        ArtistsListView(store: .init())
    }
}
