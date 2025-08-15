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
            let performanceDetail = try Queries.performanceDetailQuery(for: id).fetchOne(db)
            let artists = try Queries.performanceArtistsQuery(for: id).fetchAll(db)
            return (performanceDetail, artists)
        }

        await withErrorReporting {
            for try await (performanceDetail, artists) in combinedQuery.values(in: database) {
                self.performance = performanceDetail
                self.performingArtists = artists
            }
        }
    }

    func didTapGoToArtist(_ artistID: Artist.ID) {
        self.artistDetail = ArtistDetail(artistID: artistID)
    }

    func didTapGoToDetails() {
        self.isShowingPerformanceDetail = true
    }

    @State var artistDetail: ArtistDetail?
    @State var isShowingPerformanceDetail: Bool = false

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

    public var body: some View {
        ScheduleCardBackground(
            color: performance?.stageColor.swiftUIColor ?? .clear,
            isSelected: isSelected
        ) {
            if let performance = performance {
                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        Text(performance.title)
                            .font(.headline)

                        Text(performance.startTime..<performance.endTime, format: .performanceTime(calendar: self.calendar))
                            .font(.subheadline)
                    }

                    Spacer()
                }
                .padding(.top, 2)
            }
        }
        .omeContextMenu {
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
        .id(id)
        .tag(id)
        .task(id: id) { await task() }
        .navigationDestination(item: $artistDetail) {
            ArtistDetailView(store: $0)
        }
        .navigationDestination(isPresented: $isShowingPerformanceDetail) {
            if let performance = self.performance {
                PerformanceDetailView(performance: performance, performingArtists: self.performingArtists)
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

