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
    public init() {
        
    }

    var singleStageAtOnceFeature = ScheduleSingleStageAtOnceView.ViewModel()
    var scheduleState = ScheduleState.shared

    public var schedules: [Schedule] = []

    public var filteringFavorites: Bool = false
    var isFiltering: Bool {
        // For future filters
        return filteringFavorites
    }
//
//    var showTimeIndicator: Bool {
//        @Dependency(\.date) var date
//
//        if let selectedDay = event.schedule[day: selectedDay]?.metadata,
//           selectedDay.date == CalendarDate(date()) {
//            return true
//        } else {
//            return false
//        }
//    }

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

                if scheduleState.selectedSchedule == nil {
                    scheduleState.selectedSchedule = schedules.first?.id
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


    enum ScheduleType {
        case singleStageAtOnce
        case allStagesAtOnce
    }

    @State var visibleSchedule: ScheduleType = .singleStageAtOnce

    @Bindable var scheduleState = ScheduleState.shared
    
    public var body: some View {
        Group {
            switch visibleSchedule {
            case .singleStageAtOnce:
                ScheduleSingleStageAtOnceView(store: store.singleStageAtOnceFeature)
                    .modifier(
                        ScheduleSelectorModifier(
                            selectedScheduleID: $scheduleState.selectedSchedule,
                            schedules: store.schedules
                        )
                    )
            case .allStagesAtOnce:
                AllStagesAtOnceView(store: store)
            }
        }

//        .toolbar {
//            ToolbarItem {
//                FilterMenu(store: store)
//            }
//        }
        .task { await store.task() }
        .environment(store.scheduleState)
//        .environment(\.dayStartsAtNoon, true)
    }


    struct FilterMenu: View {
        @Bindable var store: ScheduleFeature

        var body: some View {
            Menu {
                Toggle(isOn: $store.filteringFavorites) {
                    Label(
                        "Favorites",
                        systemImage:  store.isFiltering ? "heart.fill" : "heart"
                    )
                }
            } label: {
                Label(
                    "Filter",
                    systemImage: store.isFiltering ?
                    "line.3.horizontal.decrease.circle.fill" :
                        "line.3.horizontal.decrease.circle"
                )
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
