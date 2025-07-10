//
//  Schedule.swift
//
//
//  Created by Woody on 2/17/2022.
//

import  SwiftUI; import SkipFuse
import OrderedCollections
import Dependencies
import GRDB
import CoreModels

extension Performance: DateIntervalRepresentable {
    public var dateInterval: DateInterval {
        .init(start: startTime, end: endTime)
    }
}

// TODO: Replace with GRDB query
// extension Where<Performance> {
//     public func `for`(schedule scheduleID: Schedule.ID) -> Where<Performance> {
//         self.where { $0.scheduleID == scheduleID }
//     }
//
//     func `for`(schedule scheduleID: Schedule.ID, at stageID: Stage.ID) -> Where<Performance> {
//         self.where { $0.scheduleID == scheduleID && $0.stageID == stageID }
//     }
// }

public struct ScheduleSingleStageAtOnceView: View {

    @Observable @MainActor
    class ViewModel {
        init() { }

        var selectedStage: Stage.ID?
        var selectedSchedule: Schedule.ID?

        @ObservationIgnored
        @Dependency(\.musicEventID) var musicEventID

        var stages: [Stage] = []

        func task() async {
            let musicEventID = self.musicEventID
            let query = ValueObservation.tracking { db in
                try Stage.filter(Column("musicEventID") == musicEventID).fetchAll(db)
            }

            await withErrorReporting {
                for try await stages in query.values() {
                    self.stages = stages

                    if selectedStage == nil {
                        selectedStage = stages.first?.id
                    }
                }
            }
        }
    }

    @Bindable var store: ViewModel

    //        @Namespace var namespace
    @Environment(\.dayStartsAtNoon) var dayStartsAtNoon




    public var body: some View {
        GeometryReader { geo in
            ScrollView {
                HorizontalPageView(page: $store.selectedStage) {
                    ForEach(store.stages) { stage in
                        StageSchedulePage(id: stage.id)
                            .frame(width: geo.size.width)
                    }
                }
                .frame(height: 1500)
    #if os(iOS)
                .scrollClipDisabled()
                .scrollTargetLayout()
    #endif
            }
        }
        .navigationBarExtension {
            ScheduleStageSelector(
                stages: store.stages,
                selectedStage: $store.selectedStage
            )
        }
        .task { await store.task() }
        .environment(\.dayStartsAtNoon, true)
        //            .scrollPosition($store.highlightedPerformance) { id, size in
        //                // TODO: Replace @Shared(.event) with proper state management
        //                // @Shared(.event) var event
        //                // guard let performance = event.schedule[id: id]
        //                // else { return nil }
        //
        //                return CGPoint(
        //                    x: 0,
        //                    y: performance.startTime.toY(
        //                        containerHeight: size.height,
        //                        dayStartsAtNoon: dayStartsAtNoon
        //                    )
        //                )
        //            }
        //            .overlay {
        //                if store.showingComingSoonScreen {
        //                    ScheduleComingSoonView()
        //                }
        //            }

        //            .navigationBarTitleDisplayMode(.inline)
    }


    struct StageSchedulePage: View, Identifiable {
        var id: Stage.ID
        var selectedSchedule: Schedule.ID? = nil

        var performances: [PerformanceTimelineCard] = []

        //            @Selection
        struct PerformanceTimelineCard: Identifiable, TimelineCard, Codable {
            var id: Performance.ID

            var startTime: Date
            var endTime: Date

            var dateInterval: DateInterval {
                DateInterval(start: startTime, end: endTime)
            }
        }

        func loadPerformances() async throws {
            guard let selectedSchedule
            else { return }

            // TODO: Replace with GRDB query
            // let performancesQuery = Performance.all
            //     .for(schedule: selectedSchedule, at: self.id)
            //     .select {
            //         PerformanceTimelineCard.Columns(
            //             id: $0.id,
            //             startTime: $0.startTime,
            //             endTime: $0.endTime,
            //         )
            //     }

            // TODO: Replace $performances.load() with GRDB query
            // try await self.$performances.load(performancesQuery, animation: .snappy)

        }

        var body: some View {
            SchedulePageView(performances) { performance in
                Performance.ScheduleCardView(id: performance.id)
            }
            .tag(id)
            .task(id: selectedSchedule) {
                await withErrorReporting {
                    try await self.loadPerformances()
                }
            }
        }
    }
}
