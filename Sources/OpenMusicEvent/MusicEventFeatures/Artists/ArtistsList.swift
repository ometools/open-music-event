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
import GRDB

@MainActor
@Observable
public class ArtistsList {

    // MARK: Data
    // TODO: Replace @FetchAll with GRDB query
    var artists: [Artist] = []


    // MARK: State
    var searchText: String = ""

    @ObservationIgnored
    @Dependency(\.defaultDatabase) var defaultDatabase

    @ObservationIgnored
    @Dependency(\.musicEventID) var musicEventID

    func searchTextDidChange() async {
        let id = self.musicEventID
        let searchText = self.searchText
        let query = ValueObservation.tracking { db in
            try Artist
                .filter(Column("musicEventID") == id)
                .filter(Column("name").collating(.nocase).like("%\(searchText)%"))
                .order(Column("name"))
                .fetchAll(db)
        }

        await withErrorReporting {
            for try await artists in query.values() {
                self.artists = artists
            }
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
        .task(id: store.searchText) { await store.searchTextDidChange() }
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
        }

        var artist: Artist
        
        @State var performanceStages: [Stage] = []

        private var imageSize: CGFloat = 60

        @Dependency(\.defaultDatabase) private var database

        @Environment(\.showArtistImages)
        var showArtistImages

        var body: some View {
            HStack(spacing: 10) {
                Group {
                    if artist.imageURL != nil && showArtistImages {
                        ArtistImageView(artist: artist)
                            .frame(square: 60)
                            .clipped()
                    } else {
                        ForEach(performanceStages) {
                            StageIconView(stageID: $0.id)
                                .frame(square: 60)
                        }
                    }
                }

                StageIndicatorView(colors: performanceStages.map(\.color))
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
            .task {
                await loadPerformanceStages()
            }
        }
        
        private func loadPerformanceStages() async {
            let artistID = artist.id
            let query = ValueObservation.tracking { db in
                try ArtistQueries.fetchPerformanceStages(for: artistID, from: db)
            }
            
            await withErrorReporting {
                for try await stages in query.values() {
                    self.performanceStages = stages
                    print("Artist \(artist.name): \(stages.count) stages")
                    print("Colors: \(stages.map(\.color))")
                }
            }
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
