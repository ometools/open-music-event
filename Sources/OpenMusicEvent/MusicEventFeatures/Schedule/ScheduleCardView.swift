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
        .omeContextMenu {

            ForEach(performingArtists) { artist in
                LabeledMenuButton(
                    title: "Go to Artist",
                    systemName: "person",
                    label: "\(artist.name)"
                ) {
                    //
                }
            }
        }

//#if os(iOS)
//        .contextMenu {
//
//        }
////        } preview: {
////            Performance.ScheduleDetailView(performance: performance, performingArtists: performingArtists)
////        }
//#endif
        .id(id)
        .tag(id)
        .task { await task() }
    }
}


//#if SKIP
//extension View {
//    func contextMenu<M: View>(@ViewBuilder _ menu: () -> M) -> some View {
//
//    }
//}
//#endif

struct LabeledMenuButton: View {
    init(
        title: LocalizedStringKey,
        systemName: String,
        label: String,
        action: @escaping () -> Void,

    ) {
        self.title = label
        self.action = action
        self.label = label
    }

    var action: () -> Void
    var label: String
    var title: String

    var body: some View {
        Button(action: action) {
            #if os(Android)
            HStack {
                Image(systemName: "person")

                VStack(alignment: .leading, spacing: 5) {
                    Text("Go to Artist")
                    Text(label)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            #else
            Label("Go to Artist", systemImage: "music.microphone")
            Text(label)
            #endif
        }
        .buttonStyle(.plain)
    }
}
