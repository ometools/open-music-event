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

    var destination: ArtistDetail?

    func didTapArtist(_ id: Artist.ID) {
        self.destination = ArtistDetail(artistID: id)
    }

    func searchTextDidChange() async {
        let id = self.musicEventID
        let searchText = self.searchText
        let query = ValueObservation.tracking { db in
            try Artist
                .filter(Column("musicEventID") == id)
                .filter(Column("name").collating(.nocase).like("%\(searchText)%"))
                .order(Column("name").collating(.nocase))
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
            Button {
                store.didTapArtist(artist.id)
            } label: {
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
        .navigationDestination(item: $store.destination) {
            ArtistDetailView(store: $0)
        }
    }

    struct Row: View {
        init(artist: Artist) {
            self.artist = artist
            self.id = artist.id
        }
        init(id: Artist.ID) {
            self.id = id
        }

        var id: Artist.ID

        @State var artist: Artist?

        @State var performanceStages: [Stage] = []
        @State var isFavorite: Bool = false

        private var imageSize: CGFloat = 60

        @Dependency(\.defaultDatabase) private var database

        @Environment(\.showArtistImages)
        var showArtistImages

        private func loadArtistData() async {
            let query = ValueObservation.tracking { db in
                let artist = try Artist.fetchOne(db, id: self.id)
                let stages = try Queries.fetchPerformanceStages(for: self.id, from: db)
                let isFavorite = try Artist.Preferences.fetchOne(db, key: self.id)?.isFavorite ?? false
                return (artist, stages, isFavorite)
            }

            await withErrorReporting {
                for try await (artist, stages, favorite) in query.values() {
                    self.artist = artist
                    self.performanceStages = stages
                    self.isFavorite = favorite
                }
            }
        }

        private func toggleFavorite() async {
            await withErrorReporting {
                try await database.write { db in
                    try Artist.Preferences.toggleFavorite(for: self.id, in: db)
                }
            }
        }

        var body: some View {

            HStack(spacing: 10) {
                Group {
                    if let imageURL = artist?.imageURL, showArtistImages {
                        CachedAsyncImage(url: imageURL) {
                            if let stage = performanceStages.first {
                                StageIconView(stageID: stage.id)
                            }
                        }
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

                Text(artist?.name ?? "")
                    .lineLimit(1)

                Spacer()

                if isFavorite {
                    Image(systemName: "heart.fill")
                        .resizable()
                        .renderingMode(.template)
                        .aspectRatio(contentMode: .fit)
                        .frame(square: 15)
                        .padding(.trailing)
                }
            }
            .foregroundStyle(.primary)
            .task {
                await loadArtistData()
            }
        }

    }
}

extension Artist.Preferences {
    static func toggleFavorite(for artistID: Artist.ID, in db: Database) throws {
        try db.execute(sql: """
            INSERT INTO artistPreferences (artistID, isFavorite)
            VALUES (?, 1)
            ON CONFLICT(artistID) DO UPDATE SET
            isFavorite = 1 - isFavorite
            """,
           arguments: [artistID]
        )
    }
}

extension Performance.Preferences {
    static func toggleSeen(for performanceID: Performance.ID, in db: Database) throws {
        try db.execute(sql: """
            INSERT INTO performancePreferences (performanceID, seen)
            VALUES (?, 1)
            ON CONFLICT(performanceID) DO UPDATE SET
            seen = 1 - seen
            """,
           arguments: [performanceID]
        )
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
