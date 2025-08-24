//
//  Schedule.swift
//  open-music-event
//
//  Created by Woodrow Melling on 5/9/25.
//


//
//  Schedule.swift
//
//
//  Created by Woody on 2/17/2022.
//

import  SwiftUI; import SkipFuse
import Dependencies
import GRDB
// import SharingGRDB
import CoreModels


// TODO: Replace SharedKey extensions with proper state management
// extension SharedKey where Self == InMemoryKey<Stage.ID?> {
//     static var selectedStage: Self {
//         .inMemory("selectedStage")
//     }
// }

// TODO: Replace SharedKey extensions with proper state management
// extension SharedKey where Self == InMemoryKey<Schedule.ID?> {
//     static var selectedSchedule: Self {
//         .inMemory("selectedSchedule")
//     }
// }

private let logger = Logger(subsystem: "bundle.ome.OpenMusicEvent", category: "Schedule")

@MainActor
@Observable
public class ScheduleFeature {
    public init(category: Stage.Category?) {
        self.category = category

        let scheduleState = ScheduleState()
        self.scheduleState = ScheduleState()
        self.singleStageAtOnceFeature = .init(state: scheduleState, category: category)
    }

    var category: Stage.Category?
    var singleStageAtOnceFeature: ScheduleSingleStageAtOnceView.Store
    
    var globalScheduleState: GlobalScheduleState = .shared
    var scheduleState: ScheduleState

    public var schedules: [Schedule] = []


    var isFiltering: Bool {
        // For future filters
        return globalScheduleState.filteringFavorites
    }

    var showTimeIndicator: Bool {
        @Dependency(\.date) var date

        if let selectedDay = schedules.first(where: { $0.id == globalScheduleState.selectedSchedule }) {
            if let startTime = selectedDay.startTime, let endTime = selectedDay.endTime {
                return date() >= startTime && date() <= endTime
            } else {
                return false
            }
        } else {
            return false
        }
    }

    @ObservationIgnored
    @Dependency(\.musicEventID) var musicEventID

    public func task() async {
        let musicEventID = musicEventID

        let query = ValueObservation.tracking { db in
            try Schedule
                .filter(Column("musicEventID") == musicEventID)
                .order(Column("startTime"))
                .fetchAll(db)
        }

        await withErrorReporting {
            for try await schedules in query.values() {
                self.schedules = schedules
                logger.log("schedules: \(schedules)")

                if globalScheduleState.selectedSchedule == nil {
                    globalScheduleState.selectedSchedule = schedules.first?.id
                }
            }
        }
    }
}


public struct ScheduleView: View {
    @Bindable var store: ScheduleFeature

    public init(store: ScheduleFeature) {
        self.store = store
    }

    #if os(iOS)
    // TODO: Replace @SharedReader(.interfaceOrientation) with proper orientation tracking
    // @SharedReader(.interfaceOrientation)
    // var interfaceOrientation
    #endif



    public var body: some View {
        Group {
            switch store.globalScheduleState.scheduleKind {
            case .singleStageAtOnce:
                ScheduleSingleStageAtOnceView(store: store.singleStageAtOnceFeature)

            case .allStagesAtOnce:
                ManyStagesAtOnceView(store: self.store)
            }
        }
        .animation(.default, value: store.globalScheduleState.scheduleKind)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ScheduleKindMenu(store: store)

                FilterMenu(store: store)
            }
        }
        .modifier(
            ScheduleSelectorModifier(
                selectedScheduleID: $store.globalScheduleState.selectedSchedule,
                schedules: store.schedules
            )
        )
        .task { await store.task() }
        .environment(\.shouldShowTimeIndicator, store.showTimeIndicator)
    }

    struct ScheduleKindMenu: View {
        @Bindable var store: ScheduleFeature

        var body: some View {
            Picker(selection: $store.globalScheduleState.scheduleKind) {
                Label("Single Stage", image: Icons.singleStageSchedule)
                    .tag(GlobalScheduleState.ScheduleType.singleStageAtOnce)

                Label("Multi Stage", image: Icons.multiStageSchedule)
                    .tag(GlobalScheduleState.ScheduleType.allStagesAtOnce)
            } label: {
                Text("Schedule Kind")
            }
        }
    }


    struct FilterMenu: View {
        @Bindable var store: ScheduleFeature

        var body: some View {

            Menu {
                Section {
                    Button {
                        store.globalScheduleState.filteringFavorites.toggle()
                    } label: {
                        Label {
                            Text("Favorites")
                        } icon: {
                            store.globalScheduleState.filteringFavorites ? Icons.heartFill : Icons.heart
                        }
                    }
                } header: {
                    Text("Filters")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            } label: {
                Label {
                    Text("Filters")
                } icon: {
                    if store.isFiltering {
                        Icons.listFiltersOn
                            .foregroundStyle(Color.accentColor)
                    } else {
                        Icons.listFiltersOff
                    }
                }
            }
        }
    }

}

struct ScheduleSelectorModifier: ViewModifier {
    @Binding var selectedScheduleID: Schedule.ID?
    var schedules: [Schedule]

    func label(for day: Schedule) -> String {
        if let customTitle = day.customTitle {
            return customTitle
        } else if let startTime = day.startTime {
            logger.info("START TIME Determinng Title: \(startTime)")
            return startTime.formatted(.dateTime.weekday(.wide))
        } else {
            return String(day.id.rawValue)
        }
    }


    var selectedSchedule: Schedule? {
        schedules.first { $0.id == selectedScheduleID }
    }

    var title: String {
        if let selectedSchedule {
            label(for: selectedSchedule)
        } else {
            "Select a Schedule"
        }
    }

    func body(content: Content) -> some View {
        content
            .toolbarTitleMenu {
                ForEach(schedules) { schedule in
                    Button(label(for: schedule)) {
                        selectedScheduleID = schedule.id
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(title)
    }
}

//
//func determineDayScheduleAtLaunch(from schedule: Event.Schedule) -> Event.DailySchedule.ID? {
//    @Dependency(\.date) var date
//
//    if let todaysSchedule = schedule.first(where: { $0.metadata.date == CalendarDate(date()) }) {
//        return todaysSchedule.id
//    } else {
//        // TODO: maybe need to sort this
//        return schedule.first?.id
//    }
//}
//
//
//func determineLaunchStage(for event: Event, on day: Event.DailySchedule.ID) -> Stage.ID? {
//
//    return Stages.first?.id
//}

//#Preview {
//    try! prepareDependencies {
//        $0.defaultDatabase = try appDatabase()
//    }
//
//
//    return NavigationStack {
//        ScheduleView(store: ScheduleFeature())
//    }
//}
