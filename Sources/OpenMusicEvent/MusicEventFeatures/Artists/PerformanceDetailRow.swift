//
//  PerformanceRow.swift
//  open-music-event
//
//  Created by Woodrow Melling on 5/11/25.
//

import  SwiftUI; import SkipFuse
// import SharingGRDB
import GRDB
import CoreModels

public struct PerformanceDetailRow: View {

//    @Selection
//    @Table
    struct ArtistPerformance: Identifiable {
        public typealias ID = OmeID<Performance>
        public let id: ID
        public let stageID: Stage.ID

        public let startTime: Date
        public let endTime: Date

        public let title: String

        public let stageColor: OMEColor
    }

    init(performance: ArtistPerformance) {
        self.performance = performance
    }

    var performance: ArtistPerformance

    var timeIntervalLabel: String {
        (performance.startTime..<performance.endTime)
            .formatted(.performanceTime)
    }

    public var body: some View {
        HStack(spacing: 10) {
            StageIndicatorView(color: performance.stageColor)
                .frame(width: 5)

            Stage.IconView(stageID: performance.stageID)
                .frame(square: 60)

            VStack(alignment: .leading) {
                Text(performance.title)

                Text(timeIntervalLabel + " " + performance.startTime.formatted(.daySegment))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }


            Spacer()
        }
        .listRowBackground(
            AnimatedMeshView()

        )
        .padding(.horizontal, 5)
        .frame(height: 60)
        #if os(iOS)
        .contextMenu {
            Button("View in Schedule", systemImage: "calendar") { }
        }
        #endif
    }
}

