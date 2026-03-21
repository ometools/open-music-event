//
//  SwiftUIView.swift
//  
//
//  Created by Woody on 2/21/22.
//

// import SharingGRDB
import GRDB
import SwiftUI
#if canImport(SkipFuse)
import SkipFuse
#endif
import IssueReporting

#if canImport(OSLog)
import OSLog
#elseif canImport(AndroidLogging)
import AndroidLogging
#endif

struct ManyStagesAtOnceView: View {
    var store: ScheduleFeature

    @ObservationIgnored
    @SharedShim(.selectedSchedule)
    var selectedSchedule = nil

    @State
    var performances: [PerformanceTimelineCard] = []

    @State
    var stages: [Stage] = []

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
        guard let selectedSchedule = selectedSchedule
        else { return }

        let musicEventID = store.musicEventID
        let category = store.category

        let query = ValueObservation.tracking { db in
            let performances = try SQLRequest<PerformanceTimelineCard>(
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

            let stages = try Stage
                .filter(Column("musicEventID") == musicEventID)
                .filter(Column("category") == category?.rawValue)
                .fetchAll(db)

            return (performances, stages)
        }
//
//        await withErrorReporting {
//            for try await (performances, stages) in query.values() {
//                self.performances = performances
//                self.stages = stages
//            }
//        }
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
        .navigationBarExtension {
            ScheduleStageSelector(
                stages: stages,
                selectedStage: .constant(nil)
            )
        }
        .task(id: selectedSchedule) {
            await withErrorReporting {
                await self.task()
            }
        }
    }
}
