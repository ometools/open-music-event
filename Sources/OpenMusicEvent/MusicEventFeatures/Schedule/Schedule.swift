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
@MainActor
@Observable
public class ScheduleFeature {
    public init() {
        
    }

    var singleStageAtOnceFeature = ScheduleSingleStageAtOnceView.ViewModel()

    public var selectedStage: Stage.ID?
    public var selectedSchedule: Schedule.ID?

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

                if selectedSchedule == nil {
                    selectedSchedule = schedules.first?.id
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

    public var body: some View {
        Group {
            switch visibleSchedule {
            case .singleStageAtOnce:
                ScheduleSingleStageAtOnceView(store: store.singleStageAtOnceFeature)
                    .modifier(
                        ScheduleSelectorModifier(
                            selectedScheduleID: $store.selectedSchedule,
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
            #if os(iOS)
            .toolbarTitleMenu {
                ForEach(schedules) { schedule in
                    Button(label(for: schedule)) {
                        selectedScheduleID = schedule.id
                    }
                }
            }
            #endif
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(title)
    }
}

#if SKIP
struct ToolbarTitleMenu : ContentModifier {
    func modify(view: any View) -> any View {
        view.material3ColorScheme { colors, isDark in
            colors.copy(surface: isDark ? Color.purple.asComposeColor() : Color.yellow.asComposeColor())
        }
    }
}
#endif


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
