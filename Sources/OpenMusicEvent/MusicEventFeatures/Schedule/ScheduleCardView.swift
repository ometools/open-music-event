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
                        Text(performance.startTime..<performance.endTime, format: .performanceTime)
                            .font(.caption)
                    }

                    Spacer()
                }
                .padding(.top, 2)
            }
        }
#if os(iOS)
        .contextMenu {
            ForEach(performingArtists) { artist in
                Section {
                    Button {

                    } label: {
                        Label("Go to Artist", systemImage: "music.microphone")
                        Text(artist.name)
                    }
                }
            }
        }
//        } preview: {
//            Performance.ScheduleDetailView(performance: performance, performingArtists: performingArtists)
//        }
#endif
        .id(id)
        .tag(id)
        .task { await task() }
    }
}

