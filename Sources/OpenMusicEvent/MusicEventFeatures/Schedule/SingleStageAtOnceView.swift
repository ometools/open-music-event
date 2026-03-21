//
//  Schedule.swift
//
//
//  Created by Woody on 2/17/2022.
//

import SwiftUI
#if canImport(SkipFuse)
import SkipFuse
#endif
import OrderedCollections
import Dependencies
import GRDB
import CoreModels

#if canImport(OSLog)
import OSLog
#elseif canImport(AndroidLogging)
import AndroidLogging
#endif

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

extension SharedKey where Self == AppStorageKey<Schedule.ID?> {
    static var selectedSchedule: Self {
        .appStorage("selectedSchedule")
    }
}

extension SharedKey where Self == AppStorageKey<Stage.ID?> {
    static func selectedStage(category: Stage.Category?) -> Self {
        .appStorage("\(category ?? "all")-selectedStage")
    }
}

@Observable
@MainActor
class GlobalScheduleState {


    var filteringFavorites: Bool = false

    enum ScheduleType: PickableValue {
        case singleStageAtOnce
        case allStagesAtOnce

        var label: LocalizedStringKey {
            switch self {
            case .singleStageAtOnce:
                "Single Stage At Once"
            case .allStagesAtOnce:
                "All Stages At Once"
            }
        }

        var icon: Image? {
            switch self {
            case .singleStageAtOnce: Icons.singleStageSchedule
            case .allStagesAtOnce: Icons.multiStageSchedule
            }
        }
    }

    var scheduleKind: ScheduleType = .singleStageAtOnce

    static let shared = GlobalScheduleState()
}


struct ScheduleState {
    var selectedStage: Stage.ID?
}

import Sharing


public struct ScheduleSingleStageAtOnceView: View {

    @Observable @MainActor
    class Store {
//        var globalScheduleState: GlobalScheduleState = .shared
        @ObservationIgnored
        @SharedShim(.selectedSchedule) var selectedSchedule = nil

        @ObservationIgnored
        @SharedShim var selectedStage: Stage.ID?

        @ObservationIgnored
        @Dependency(\.musicEventID) var musicEventID

        @ObservationIgnored
        @Dependency(\.defaultDatabase) var database


        let category: Stage.Category?
        var stages: [Stage] = []

        init(category: Stage.Category?) {
            self.category = category
            self._selectedStage = SharedShim(wrappedValue: nil, .selectedStage(category: category))
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
                for try await stages in query.values(in: database) {
                    self.stages = stages
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
                HorizontalPageView(page: Binding(store.$selectedStage)) {
                    ForEach(store.stages) { stage in
                        StageSchedulePage(
                            id: stage.id,
                            selectedSchedule: store.selectedSchedule
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
                selectedStage: Binding(store.$selectedStage)
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

    @Environment(\.defaultDatabase) var db


    func task() async {
        guard let selectedSchedule = selectedSchedule
        else { return }

        let query = ValueObservation.tracking { db in
            try Queries
                .performancesQuery(for: id, scheduleID: selectedSchedule)
                .fetchAll(db)
        }

        await withErrorReporting {
            for try await performances in query.values(in: db) {
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
