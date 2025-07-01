//
//  SwiftUIView.swift
//  
//
//  Created by Woody on 2/20/22.
//

import  SwiftUI; import SkipFuse
// import SharingGRDB
import GRDB

extension Performance {
    struct ScheduleCardView: View {
        init(performance: PerformanceDetail, performingArtists: [Artist]) {
            // TODO: Replace @FetchOne/@FetchAll with GRDB queries
            // self._performance = FetchOne(wrappedValue: performance)
            // self._performingArtists = FetchAll(wrappedValue: performingArtists)
            self.performance = performance
            self.performingArtists = performingArtists
        }

        init(id: Performance.ID) {
            // TODO: Replace @FetchOne/@FetchAll with GRDB queries
            // self._performance = FetchOne(wrappedValue: .empty, PerformanceDetail.find(id))
            // self._performingArtists = FetchAll(
            //     Performance.find(id)
            //         .join(Performance.Artists.all) { $0.id == $1.performanceID }
            //         .join(Artist.all) { $1.artistID.eq($2.id) }
            //         .select { $2 }
            // )
            self.performance = .empty
            self.performingArtists = []
        }

        // TODO: Replace @FetchOne with GRDB query
        var performance: PerformanceDetail

        // TODO: Replace @FetchAll with GRDB query
        var performingArtists: [Artist]

        let isSelected: Bool = false

        public var body: some View {
            ScheduleCardBackground(
                color: performance.stageColor.swiftUIColor,
                isSelected: isSelected
            ) {
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
            } preview: {
                Performance.ScheduleDetailView(performance: performance, performingArtists: performingArtists)
            }
            #endif
            .id(performance.id)
            .tag(performance.id)
        }
    }
}

