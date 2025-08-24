//
//  SwiftUIView.swift
//  
//
//  Created by Woody on 2/21/22.
//

// import SharingGRDB
import GRDB
import SwiftUI
import SkipFuse
import IssueReporting

struct ManyStagesAtOnceView: View {
    var store: ScheduleFeature
    var globalScheduleState: GlobalScheduleState = .shared

    @State
    var performances: [PerformanceTimelineCard] = []

    struct PerformanceTimelineCard: Identifiable, TimelineCard, Codable, FetchableRecord {
        var id: Performance.ID

        var startTime: Date
        var endTime: Date
        var sortIndex: Int

        var groupWidth: Range<Int> {
            sortIndex..<sortIndex
        }

        var dateInterval: DateInterval {
            DateInterval(start: startTime, end: endTime)
        }

        init(id: Performance.ID, startTime: Date, endTime: Date, sortIndex: Int) {
            self.id = id
            self.startTime = startTime
            self.endTime = endTime
            self.sortIndex = sortIndex
        }

        init(row: Row) throws {
            self.init(
                id: Performance.ID(row["id"]),
                startTime: row["startTime"],
                endTime: row["endTime"],
                sortIndex: row["sortIndex"]
            )
        }
    }

    let logger = Logger(subsystem: "bundle.ome.OpenMusicEvent", category: "StageSchedulePage")

    func task() async {
        guard let selectedSchedule = globalScheduleState.selectedSchedule
        else { return }

        let category = store.category
        let query = ValueObservation.tracking { db in
            try SQLRequest<PerformanceTimelineCard>(
                sql: """
                    SELECT 
                        p.id as id,
                        p.startTime as startTime,
                        p.endTime as endTime,
                        s.sortIndex as sortIndex
                    FROM performances p
                    JOIN stages s ON p.stageID = s.id
                    WHERE p.scheduleID = ? AND (? IS NULL AND s.category IS NULL OR s.category = ?) 
                """,
                arguments: [selectedSchedule.rawValue, category?.rawValue, category?.rawValue]
            )
            .fetchAll(db)
        }

        await withErrorReporting {
            for try await performances in query.values() {
                self.performances = performances
            }
        }
    }

    var body: some View {
        ScrollView {
            SchedulePageView(performances) { performance in
                ScheduleCardView(id: performance.id)
            } emptyContent: {
                EmptyView()
            }
            .frame(height: 1500)
        }
        .task(id: globalScheduleState.selectedSchedule) {
            await withErrorReporting {
                await self.task()
            }
        }
    }
}
