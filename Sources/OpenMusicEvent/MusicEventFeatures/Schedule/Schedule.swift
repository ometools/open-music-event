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

import CoreGraphics
import SwiftUI
import Dependencies
import SharingGRDB
import CoreModels


extension SharedKey where Self == InMemoryKey<Stage.ID?> {
    static var selectedStage: Self {
        .inMemory("selectedStage")
    }
}

extension SharedKey where Self == InMemoryKey<Schedule.ID?> {
    static var selectedSchedule: Self {
        .inMemory("selectedSchedule")
    }
}
@MainActor
@Observable
public class ScheduleFeature {
    public init() {
        
    }


    var singleStageAtOnceFeature = ScheduleView.SingleStageAtOnceView.ViewModel()

    @ObservationIgnored
    @Shared(.selectedStage)
    public var selectedStage: Stage.ID?

    @ObservationIgnored
    @Shared(.selectedSchedule)
    public var selectedSchedule: Schedule.ID?


    @ObservationIgnored
    @FetchAll(Current.stages)
    public var stages: [Stage]

    @ObservationIgnored
    @FetchAll(Current.schedules.order(by: \.startTime))
    public var schedules

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

    public func task() async {
        if self.selectedStage == nil || !stages.contains(where: { $0.id == self.selectedStage }) {
            self.$selectedStage.withLock { $0 = stages.first?.id }
        }

        if self.selectedSchedule == nil || !schedules.contains(where: { $0.id == self.selectedSchedule }) {
            self.$selectedSchedule.withLock { $0 = schedules.first?.id }
        }
    }
}

public struct ScheduleView: View {
    @Bindable var store: ScheduleFeature

    public init(store: ScheduleFeature) {
        self.store = store
    }

    #if os(iOS)
    @SharedReader(.interfaceOrientation)
    var interfaceOrientation
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
                SingleStageAtOnceView(store: store.singleStageAtOnceFeature)
            case .allStagesAtOnce:
                AllStagesAtOnceView(store: store)
            }
        }
//        .scrollPosition(id: $scrolledEvent)
        .modifier(
            ScheduleSelectorModifier(
                selectedScheduleID: Binding(store.$selectedSchedule),
                schedules: store.schedules
            )
        )
        .toolbar {
            ToolbarItem {
                FilterMenu(store: store)
            }
        }
        .task { await store.task() }

//        .environment(\.dayStartsAtNoon, true)
    }


    struct FilterMenu: View {
        @Bindable var store: ScheduleFeature

        var body: some View {
            Menu {
                Toggle(isOn: $store.filteringFavorites.animation()) {
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

        func body(content: Content) -> some View {
            content
                .toolbarTitleMenu {
                    ForEach(schedules) { schedule in
                        Button(label(for: schedule)) {
                            selectedScheduleID = schedule.id
                        }
                    }
                }
                .navigationTitle(selectedSchedule.map { label(for: $0) } ?? "")
                #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
        }
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

#Preview {
    try! prepareDependencies {
        $0.defaultDatabase = try appDatabase()
    }


    return NavigationStack {
        ScheduleView(store: ScheduleFeature())
    }
}
