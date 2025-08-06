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

    @State var performance: PerformanceDetail?
    @State var performingArtists: [Artist] = []

    let isSelected: Bool = false

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

                        Text(performance.startTime..<performance.endTime, format: .performanceTime)
                            .font(.subheadline)
                    }

                    Spacer()
                }
                .padding(.top, 2)
            }
        }
        .omeContextMenu {
            ForEach(performingArtists) { artist in
                LabeledMenuButton(
                    title: "Go to Artist",
                    label: "\(artist.name)",
                    systemImage: "person"
                ) {
                    //
                }
            }
        }
        .id(id)
        .tag(id)
        .task(id: id) { await task() }
    }
}


//#if SKIP
//extension View {
//    func contextMenu<M: View>(@ViewBuilder _ menu: () -> M) -> some View {
//
//    }
//}
//#endif

