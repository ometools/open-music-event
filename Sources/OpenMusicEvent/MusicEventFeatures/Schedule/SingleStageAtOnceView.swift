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


private let logger = Logger(
    subsystem: "bundle.ome.OpenMusicEvent",
    category: "Schedule"
)

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

@Observable
@MainActor
class GlobalScheduleState {
    var selectedSchedule: Schedule.ID?

    static let shared = GlobalScheduleState()
}

@Observable
@MainActor
class ScheduleState {
    var selectedStage: Stage.ID?
}


public struct ScheduleSingleStageAtOnceView: View {

    @Observable @MainActor
    class Store {
        var scheduleState: ScheduleState
        var globalScheduleState: GlobalScheduleState = .shared

        @ObservationIgnored
        @Dependency(\.musicEventID) var musicEventID

        let category: Stage.Category?
        var stages: [Stage] = []

        init(state: ScheduleState, category: Stage.Category?) {
            self.category = category
            self.scheduleState = state
        }

        func task() async {
            let musicEventID = self.musicEventID
            let query = ValueObservation.tracking { db in
                try Stage
                    .filter(Column("musicEventID") == musicEventID)
                    .filter(Column("category") == self.category?.rawValue)
                    .fetchAll(db)
            }

            await withErrorReporting {
                for try await stages in query.values() {
                    self.stages = stages

                    if scheduleState.selectedStage == nil {
                        scheduleState.selectedStage = stages.first?.id
                    }
                }
            }
        }
    }

    @Bindable var store: Store
    //        @Namespace var namespace
    @Environment(\.dayStartsAtNoon) var dayStartsAtNoon
    @Environment(\.scheduleHeight) var scheduleHeight

    public var body: some View {
        GeometryReader { geo in
            ScrollView {
                HorizontalPageView(page: $store.scheduleState.selectedStage) {
                    ForEach(store.stages) { stage in
                        StageSchedulePage(
                            id: stage.id,
                            selectedSchedule: store.globalScheduleState.selectedSchedule
                        )
                        .frame(width: geo.size.width)
                        .tag(stage.id)
                    }
                }
                .frame(height: scheduleHeight)
    #if os(iOS)
                .scrollClipDisabled()
                .scrollTargetLayout()
    #endif
            }
        }
        .navigationBarExtension {
            ScheduleStageSelector(
                stages: store.stages,
                selectedStage: $store.scheduleState.selectedStage
            )
        }
        .task(id: store.category) { await store.task() }
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
}

struct StageSchedulePage: View, Identifiable {
    var id: Stage.ID
    var selectedSchedule: Schedule.ID?
    var globalScheduleState: GlobalScheduleState = .shared

    @State
    var performances: [PerformanceTimelineCard] = []

    struct PerformanceTimelineCard: Identifiable, TimelineCard, Codable {
        var id: Performance.ID

        var startTime: Date
        var endTime: Date

        var dateInterval: DateInterval {
            DateInterval(start: startTime, end: endTime)
        }
    }

    let logger = Logger(subsystem: "bundle.ome.OpenMusicEvent", category: "StageSchedulePage")

    func task() async {
        guard let selectedSchedule = globalScheduleState.selectedSchedule
        else { return }

        let query = ValueObservation.tracking { db in
            try Queries
                .performancesQuery(for: id, scheduleID: selectedSchedule)
                .fetchAll(db)
        }

        await withErrorReporting {
            for try await performances in query.values() {
                self.performances = performances.map {
                    PerformanceTimelineCard(
                        id: $0.id,
                        startTime: $0.startTime,
                        endTime: $0.endTime
                    )
                }
                logger.log("PerformancesCount: \(performances.count)")
            }
        }
    }

    var body: some View {
        SchedulePageView(performances) { performance in
            ScheduleCardView(id: performance.id)
        } emptyContent: {
            EmptyView()
        }
        .tag(id)
        .task(id: selectedSchedule) {
            await withErrorReporting {
                await self.task()
            }
        }
    }
}
