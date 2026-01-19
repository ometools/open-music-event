//
//  SwiftUIView.swift
//  
//
//  Created by Woody on 2/20/22.
//

import  SwiftUI; import SkipFuse
// import SharingGRDB
import CasePaths
import GRDB
import IssueReporting
import Dependencies


struct ScheduleCardView: View {
    init(id: Performance.ID) {
        self.id = id
    }

    let id: Performance.ID

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
        self.destination = .artistDetail(ArtistDetail(artistID: artistID))
    }

    func didTapGoToDetails() {
        guard let performance = performance
        else { reportIssue("Expected performance to be non-nil"); return }

        self.destination = .performanceDetail(performance)
    }
    
    func toggleSeen() async {
        await withErrorReporting {
            try await database.write { db in
                try Performance.Preferences.toggleSeen(for: id, in: db)
            }
        }
    }


@CasePathable
    enum Destination {
        case artistDetail(ArtistDetail)
        case performanceDetail(PerformanceDetail)
    }

    @State var destination: Destination?

    @State var isFavorite: Bool = false
    @State var performance: PerformanceDetail?
    @State var performingArtists: [Artist] = []

    let isSelected: Bool = false


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
                #if os(Android)
                switch scheduleState.scheduleKind {
                case .singleStageAtOnce:
                    LargePerformanceView(performance: performance, hasFavoriteArtist: self.isFavorite)
                case .allStagesAtOnce:
                    TinyPerformanceView(performance: performance)
                }

                #else
                ViewThatFits {
                    LargePerformanceView(performance: performance, hasFavoriteArtist: self.isFavorite)
                    TinyPerformanceView(performance: performance)
                }
                #endif
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
            
            NavigationLinkButton {
                self.didTapGoToDetails()
            } label: {
                Label("Go to Details", systemImage: "info.circle")
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
        } primaryAction: {
            self.didTapGoToDetails()
        }
        .animation(.default, value: isDimmed)
        .animation(.default, value: isSeen)
        .id(id)
        .tag(id)
        .task(id: id) { await task() }
        .navigationDestination(item: $destination.artistDetail) {
            ArtistDetailView(store: $0)
        }
        .navigationDestination(item: $destination.performanceDetail) {
            PerformanceDetailView(id: $0.id)
        }
    }
}

struct LargePerformanceView: View {
    var performance: PerformanceDetail
    var hasFavoriteArtist: Bool
    @Environment(\.calendar) var calendar

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading) {
                HStack {
                    Text(performance.title)
                        .font(.headline)
//                        .minimumScaleFactor(0.5)
                }

                Text(performance.startTime..<performance.endTime, format: .performanceTime(calendar: self.calendar))
                    .font(.subheadline)
//                    .minimumScaleFactor(0.5)
            }

            Spacer()

            icons
        }
        .padding(.top, 2)
    }


    @ViewBuilder
    var icons: some View {
        HStack(spacing: 4) {
            if performance.isSeen {
                IconView(image: Icons.seenOn)
            }

            if hasFavoriteArtist {
                IconView(image: Icons.heartFill)
            }

            ForEach(performance.performanceRecordings ?? [], id: \.url) { recording in
                IconView(image: recording.platform.icon?.resizable())
            }
        }
        .foregroundStyle(.secondary)
        .padding(.trailing)
    }

    struct IconView: View {
        let image: Image?
        var body: some View {
            if let image {
                image
                    .resizable()
                    .scaledToFit()
                    .frame(square: 20)
            }
        }
    }
}




struct TinyPerformanceView: View {
    var performance: PerformanceDetail

    @Environment(\.calendar) var calendar

    var body: some View {
        HStack(alignment: .top) {

            VStack(alignment: .leading) {
                HStack {
                    Text(performance.title)
                        .font(.caption)
                }

                Text(performance.startTime, format: Date.FormatStyle.dateTime.hour(.defaultDigits(amPM: .abbreviated)).minute())
                    .font(.caption2)
            }

            Spacer()
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

