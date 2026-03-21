//
//  Artists.swift
//  open-music-event
//
//  Created by Woodrow Melling on 5/3/25.
//

import SwiftUI
#if canImport(SkipFuse)
import SkipFuse
#endif
// import SharingGRDB
import CoreModels
import Dependencies
import GRDB

@MainActor
@Observable
public class ArtistsList {

    struct Row: FetchableRecord, Identifiable {
        let id: Artist.ID
        let artistName: String
        let artistImageURL: URL?
        let isFavorite: Bool
//        let performancesStages: [(stageID: Stage.ID, stageName: String, color: Color)]

        init(row: GRDB.Row) {
            self.id = OmeID(rawValue: row["id"])
            self.artistName = row["artistName"]
            self.artistImageURL = row["artistImageURL"]
            self.isFavorite = row["isFavorite"]
//
//            // Parse concatenated stages: "stageID::stageName::color|||..."
//            if let stagesString: String = row["performanceStages"], !stagesString.isEmpty {
//                self.performancesStages = stagesString
//                    .split(separator: "|||")
//                    .compactMap { stage in
//                        let parts = stage.split(separator: "::")
//                        guard parts.count == 3 else { return nil }
//                        let stageID = OmeID<Stage>(rawValue: String(parts[0]))
//                        let stageName = String(parts[1])
//                        let colorRawValue = String(parts[2])
//                        let omeColor = OMEColor(rawValue: colorRawValue)
//                        return (stageID, stageName, Color(omeColor))
//                    }
//            } else {
//                self.performancesStages = []
//            }
        }
    }

    // MARK: Data
    var rows: [Row] = []

    // MARK: State
    var searchText: String = ""

    @ObservationIgnored
    @Dependency(\.defaultDatabase) var defaultDatabase

    @ObservationIgnored
    @Dependency(\.musicEventID) var musicEventID

    @ObservationIgnored
    @Dependency(\.organizerID) var organizerID

    var destination: ArtistDetail?

    func didTapArtist(_ id: Artist.ID) {
        withDependencies(from: self) {
            self.destination = ArtistDetail(artistID: id)
        }
    }

    func searchTextDidChange() async {
        let eventID = self.musicEventID
        let orgID = self.organizerID
        let searchText = self.searchText

        let observation = ValueObservation.tracking { db in
            try Queries.fetchArtistListRows(
                for: eventID,
                organizerID: orgID,
                searchText: searchText
            ).fetchAll(db)
        }

        await withErrorReporting {
            for try await rows in observation.values(in: defaultDatabase) {
                self.rows = rows
            }
        }
    }
}

struct ArtistsListView: View {
    @Bindable var store: ArtistsList

    var body: some View {
        List(store.rows) { row in
            Button {
                store.didTapArtist(row.id)
            } label: {
                RowView(row: row)
            }
            .buttonStyle(.plain)
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

    struct RowView: View {
        let row: ArtistsList.Row

        @Environment(\.showArtistImages) var showArtistImages

        var body: some View {
            HStack(spacing: 10) {
//                Group {
//                    if let imageURL = row.artistImageURL, showArtistImages {
//                        CachedAsyncImage(url: imageURL) {
//                            if let stage = row.performancesStages.first {
//                                StageIconView(stageID: stage.stageID)
//                            }
//                        }
//                        .frame(square: 60)
//                        .clipped()
//                    } else {
//                        ForEach(row.performancesStages, id: \.stageID) { stage in
//                            StageIconView(stageID: stage.stageID)
//                                .frame(square: 60)
//                        }
//                    }
//                }
//
//                StageIndicatorView(colors: row.performancesStages.map(\.color))
//                    .frame(width: 5, height: 60)

                Text(row.artistName)
                    .lineLimit(1)

                Spacer()

                if row.isFavorite {
                    Image(systemName: "heart.fill")
                        .resizable()
                        #if !os(Android)
                        .renderingMode(.template)
                        #endif
                        .aspectRatio(contentMode: .fit)
                        .frame(square: 15)
                        .padding(.trailing)
                }
            }
            .foregroundStyle(.primary)
        }
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
