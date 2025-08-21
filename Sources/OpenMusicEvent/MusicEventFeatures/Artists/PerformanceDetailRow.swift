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
import Dependencies

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
        public let isSeen: Bool
    }

    init(performance: ArtistPerformance) {
        self.performance = performance
    }

    var performance: ArtistPerformance

    @Environment(\.calendar) var calendar
    @Dependency(\.defaultDatabase) var database

    var timeIntervalLabel: String {
        (performance.startTime..<performance.endTime)
            .formatted(.performanceTime(calendar: calendar))
    }
    
    func toggleSeen() async {
        await withErrorReporting {
            try await database.write { db in
                try Performance.Preferences.toggleSeen(for: performance.id, in: db)
            }
        }
    }

    public var body: some View {
        HStack(spacing: 10) {
            StageIndicatorView(color: performance.stageColor)
                .frame(width: 5)

            StageIconView(stageID: performance.stageID)
                .frame(square: 60)
                .foregroundStyle(.primary)

            VStack(alignment: .leading) {
                Text(performance.title)

                Text(timeIntervalLabel + " " + performance.startTime.formatted(.daySegment))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
            
            if performance.isSeen {
                Icons.seenOn
                    .foregroundColor(.secondary)
                    .padding(.trailing)
            }
        }
        .listRowBackground(
            AnimatedMeshView()
        )
        .padding(.horizontal, 5)
        .frame(height: 60)
        .foregroundStyle(Color.primary)
        .omeContextMenu {
            Button {
                Task { await toggleSeen() }
            } label: {
                Label(
                    performance.isSeen ? "Mark as Not Seen" : "Mark as Seen",
                    image: performance.isSeen ? Icons.seenToggleOff : Icons.seenOff
                )
            }
        }
    }
}

