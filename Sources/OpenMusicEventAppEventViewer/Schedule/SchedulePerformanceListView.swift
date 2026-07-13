import ComposableArchitecture2
import Dependencies
import Foundation
import SQLiteData
import SwiftUI

@Feature
public struct SchedulePerformanceList {
    public init() {}

    public struct State {
        public init(
            eventID: OMERecord.Event.ID,
            scheduleDivision: ScheduleViewer.ScheduleDivision
        ) {
            @Dependency(\.defaultEventTimeZone) var defaultEventTimeZone

            self.eventID = eventID
            self.timeZone = defaultEventTimeZone
            self.scheduleDivision = scheduleDivision
            _performanceRows = FetchAll(
                PerformanceRow.all(eventID: eventID)
            )
            _schedules = FetchAll(
                ScheduleViewer.schedulesQuery(eventID: eventID)
            )
            _stages = FetchAll(
                ScheduleViewer.stagesQuery(eventID: eventID)
            )
        }

        public let eventID: OMERecord.Event.ID
        @DebugSnapshotIgnored
        public var timeZone: TimeZone
        public let scheduleDivision: ScheduleViewer.ScheduleDivision

        @FetchAll public var performanceRows: [PerformanceRow]
        @FetchAll public var schedules: [OMERecord.Schedule]
        @FetchAll public var stages: [OMERecord.Stage]

        public func selectedSchedule(
            selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?
        ) -> OMERecord.Schedule? {
            guard let selectedScheduleID = resolvedSelectedScheduleID(selectedScheduleID) else {
                return nil
            }
            return schedules.first { $0.id.scheduleID == selectedScheduleID }
        }

        public func selectedScheduleTitle(
            selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?
        ) -> String {
            selectedSchedule(selectedScheduleID: selectedScheduleID)
                .map(ScheduleViewer.scheduleTitle) ?? "Select Schedule"
        }

        public func visiblePerformanceRows(
            selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?
        ) -> [PerformanceRow] {
            ScheduleViewer.visiblePerformances(
                performanceRows: performanceRows,
                scheduleID: resolvedSelectedScheduleID(selectedScheduleID),
                stages: visibleStages
            )
        }

        public func resolvedSelectedScheduleID(
            _ selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?
        ) -> OMERecord.ID<OMERecord.Schedule>? {
            ScheduleViewer.resolvedSelectedScheduleID(
                selectedScheduleID,
                schedules: schedules
            )
        }

        public var visibleStages: [OMERecord.Stage] {
            ScheduleViewer.visibleStages(
                stages: stages,
                division: scheduleDivision
            )
        }
    }

    public enum Action {
        case performanceButtonTapped(OMERecord.ID<OMERecord.Performance>)
    }

    public var body: some Feature {
        Update { _, action in
            switch action {
            case let .performanceButtonTapped(performanceID):
                store.addTask {
                    let task = try store.post(
                        key: SchedulePerformanceDetailRequested.self,
                        value: performanceID
                    )
                    await task?.value
                }
            }
        }
    }
}

public struct SchedulePerformanceListView: View {
    @Environment(\.dateTimeRangeResolutionPolicy) var dateTimeRangeResolutionPolicy
    @Bindable var store: StoreOf<SchedulePerformanceList>
    let selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?
    let showsAuthoringControls: Bool

    public init(
        store: StoreOf<SchedulePerformanceList>,
        selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?,
        showsAuthoringControls: Bool
    ) {
        self.store = store
        self.selectedScheduleID = selectedScheduleID
        self.showsAuthoringControls = showsAuthoringControls
    }

    public var body: some View {
        let rows = store.state.visiblePerformanceRows(selectedScheduleID: selectedScheduleID)
        if rows.isEmpty {
            ViewerPlaceholderView(
                title: store.state.selectedScheduleTitle(selectedScheduleID: selectedScheduleID),
                systemImage: "calendar",
                description: "No performances have been added to this schedule division yet."
            )
        } else {
            TimelineView(.periodic(from: Date.now, by: 1)) { context in
                List(rows) { row in
                    Button {
                        store.send(.performanceButtonTapped(row.performanceID))
                    } label: {
                        SchedulePerformanceRow(
                            row: row,
                            subtitle: ScheduleViewer.performanceRowSubtitle(
                                for: row.performance,
                                timeZone: store.timeZone,
                                policy: dateTimeRangeResolutionPolicy
                            ),
                            now: context.date
                        )
                    }
                    .navigationLinkListRowStyle()
                }
                .listStyle(.plain)
            }
        }
    }
}
