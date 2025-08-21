//
//  SwiftUIView.swift
//  
//
//  Created by Woody on 2/20/22.
//

import  SwiftUI; import SkipFuse
// import SharingGRDB
import GRDB
import IssueReporting
import Dependencies


struct ScheduleCardView: View {
    init(id: Performance.ID) {
        self.id = id
    }

    let id: Performance.ID
    @State var selectedPerformance: Performance.ID?

    @Dependency(\.defaultDatabase) var database

    func task() async {
        let combinedQuery = ValueObservation.tracking { db in
            let performanceDetail = try Queries.performanceDetailQuery(for: self.id).fetchOne(db)
            let artists = try Queries.performanceArtistsQuery(for: self.id).fetchAll(db)
            let hasFavoriteArtists = try Bool.fetchOne(db, sql: """
                SELECT COUNT(*) > 0
                FROM performanceArtists pa
                JOIN artistPreferences ap ON pa.artistID = ap.artistID
                WHERE pa.performanceID = ? AND ap.isFavorite = 1
                """, arguments: [self.id]) ?? false
            return (performanceDetail, artists, hasFavoriteArtists)
        }

        await withErrorReporting {
            for try await (performanceDetail, artists, hasFavorite) in combinedQuery.values(in: database) {
                self.performance = performanceDetail
                self.performingArtists = artists
                self.isFavorite = hasFavorite
            }
        }
    }

    func didTapGoToArtist(_ artistID: Artist.ID) {
        self.artistDetail = ArtistDetail(artistID: artistID)
    }

    func didTapGoToDetails() {
        self.isShowingPerformanceDetail = true
    }
    
    func toggleSeen() async {
        await withErrorReporting {
            try await database.write { db in
                try Performance.Preferences.toggleSeen(for: id, in: db)
            }
        }
    }

    @State var artistDetail: ArtistDetail?
    @State var isShowingPerformanceDetail: Bool = false
    @State var isFavorite: Bool = false

    @State var performance: PerformanceDetail?
    @State var performingArtists: [Artist] = []

    let isSelected: Bool = false

    var hasDetails: Bool {
        guard let performance
        else { return false }

        if performance.description != nil {
            return true
        }

        // Show a detail if there's an artist that isn't in the title
        if !performingArtists.allSatisfy({ performance.title.contains($0.name) }) {
            return true
        }

        return false
    }

    @Environment(\.calendar) var calendar
    @Environment(\.colorScheme) var colorScheme

    let scheduleState = GlobalScheduleState.shared

    var isDimmed: Bool {
        scheduleState.filteringFavorites && !isFavorite
    }

    var isSeen: Bool {
        guard let performance
        else { return false }

        return performance.isSeen
    }

    public var body: some View {
        ScheduleCardBackground(
            color: performance?.stageColor.swiftUIColor ?? .clear,
            isSelected: isSelected
        ) {
            if let performance = performance {
                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        HStack {
                            Text(performance.title)
                                .font(.headline)
                        }

                        Text(performance.startTime..<performance.endTime, format: .performanceTime(calendar: self.calendar))
                            .font(.subheadline)
                    }

                    Spacer()

                    HStack {
                        if performance.isSeen {
                            Icons.seenOn
                        }
                        
                        if isFavorite {
                            Image(systemName: "heart.fill")
                        }
                    }
                    .foregroundStyle(.secondary)
                    .padding(.trailing)
                }
                .padding(.top, 2)
            }
        }
        .overlay {
            if isDimmed {
                switch colorScheme {
                case .dark:
                    Color.black.opacity(0.7)
                case .light:
                    Color.white.opacity(0.7)
                @unknown default:
                    Color.black.opacity(0.7)
                }
            }
        }
        .omeContextMenu {
            Button {
                Task { await toggleSeen() }
            } label: {
                Label(
                    isSeen ? "Mark as Not Seen" : "Mark as Seen",
                    image: isSeen ? Icons.seenToggleOff : Icons.seenOff
                )
            }
            
            if self.hasDetails {
                NavigationLinkButton {
                    self.didTapGoToDetails()
                } label: {
                    Label("Go to Details", systemImage: "info.circle")
                }
            }

            ForEach(performingArtists) { artist in
                LabeledMenuButton(
                    title: "Go to Artist",
                    label: "\(artist.name)",
                    systemImage: Icons.person
                ) {
                    self.didTapGoToArtist(artist.id)
                }
            }
        }
        .animation(.default, value: isDimmed)
        .animation(.default, value: isSeen)
        .id(id)
        .tag(id)
        .task(id: id) { await task() }
        .navigationDestination(item: $artistDetail) {
            ArtistDetailView(store: $0)
        }
        .navigationDestination(isPresented: $isShowingPerformanceDetail) {
            if let performance = self.performance {
                PerformanceDetailView(id: performance.id)
            }
        }
    }
}


//#if SKIP
//extension View {
//    func contextMenu<M: View>(@ViewBuilder _ menu: () -> M) -> some View {
//
//    }
//}
//#endif

