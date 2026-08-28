import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventComponents
import ScheduleComponents
import Sharing
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
            self.eventID = eventID
            self._timeZone = FetchOne(
                OMERecord.Event.timeZoneQuery(eventID: eventID)
            )
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
        @FetchOne public var timeZone: TimeZone?
        var eventTimePresentation: EventTimePresentation? {
            timeZone.map { EventTimePresentation(timeZone: $0) }
        }
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
            guard let schedule = selectedSchedule(selectedScheduleID: selectedScheduleID),
                  let timeZone
            else { return "Select Schedule" }
            return ScheduleViewer.scheduleTitle(schedule, in: timeZone)
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
        case newUserScheduleButtonTapped(OMERecord.ID<OMERecord.Performance>)
        case scheduleDivisionButtonTapped(ScheduleViewer.ScheduleDivision)
        case userScheduleMembershipButtonTapped(
            OMERecord.ID<OMERecord.Performance>,
            UserSchedule.ID
        )
    }

    public var body: some Feature {
        Update { _, action in
            switch action {
            case let .newUserScheduleButtonTapped(performanceID):
                store.addTask {
                    let task = try store.post(
                        key: SchedulePerformanceNewUserScheduleRequested.self,
                        value: performanceID
                    )
                    await task?.value
                }

            case let .scheduleDivisionButtonTapped(division):
                store.addTask {
                    let task = try store.post(
                        key: ScheduleDivisionRequested.self,
                        value: division
                    )
                    await task?.value
                }

            case let .userScheduleMembershipButtonTapped(performanceID, scheduleID):
                store.addTask {
                    let task = try store.post(
                        key: SchedulePerformanceUserScheduleMembershipRequested.self,
                        value: SchedulePerformanceUserScheduleMembershipRequest(
                            performanceID: performanceID,
                            scheduleID: scheduleID
                        )
                    )
                    await task?.value
                }
            }
        }
    }
}

public struct SchedulePerformanceListView: View {
    @Environment(\.dateTimeRangeResolutionPolicy) var dateTimeRangeResolutionPolicy
    @Environment(\.eventTimePresentation) var eventTimePresentation
    @Environment(\.scheduleNowScrollRequest) var scheduleNowScrollRequest
    @Environment(\.performanceReactionMenuContext) var reactionMenuContext
    @Bindable var store: StoreOf<SchedulePerformanceList>
    let selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?
    let userScheduleOverlay: UserScheduleOverlay
    let showsAuthoringControls: Bool
    let performanceButtonTapped: (OMERecord.ID<OMERecord.Performance>) -> Void

    public init(
        store: StoreOf<SchedulePerformanceList>,
        selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?,
        userScheduleOverlay: UserScheduleOverlay,
        showsAuthoringControls: Bool,
        performanceButtonTapped: @escaping (OMERecord.ID<OMERecord.Performance>) -> Void
    ) {
        self.store = store
        self.selectedScheduleID = selectedScheduleID
        self.userScheduleOverlay = userScheduleOverlay
        self.showsAuthoringControls = showsAuthoringControls
        self.performanceButtonTapped = performanceButtonTapped
    }

    public var body: some View {
        let rows = store.state.visiblePerformanceRows(selectedScheduleID: selectedScheduleID)
        if rows.isEmpty {
            List {}
                .listStyle(.plain)
                .overlay {
                    ScheduleEmptyView(
                        title: ScheduleViewer.emptyScheduleTitle(
                            scheduleDivision: store.scheduleDivision,
                            scheduleTitle: store.state.selectedScheduleTitle(
                                selectedScheduleID: selectedScheduleID
                            )
                        ),
                        otherScheduleDivisions: otherScheduleDivisions,
                        onScheduleDivisionTapped: { division in
                            store.send(.scheduleDivisionButtonTapped(division))
                        }
                    )
                    .padding()
                }
        } else if let eventTimePresentation {
            PeriodicTimelineView(every: 1) { currentDate in
                ScrollViewReader { proxy in
                    List(rows) { row in
                        Button {
                            performanceButtonTapped(row.performanceID)
                        } label: {
                            SchedulePerformanceRow(
                                row: row,
                                timeRangeText: eventTimePresentation.performanceRowTimeRange(
                                    for: row.performance
                                ),
                                daySegmentText: eventTimePresentation.daySegment(
                                    for: row.performance.startTime,
                                    policy: dateTimeRangeResolutionPolicy
                                ),
                                userScheduleOverlay: userScheduleOverlay,
                                now: currentDate
                            )
                        }
                        .id(row.performanceID)
                        .accessibilityIdentifier(
                            "button.performance.\(row.performanceID.rawValue.rawValue)"
                        )
                        .navigationLinkListRowStyle()
                        .contextMenu {
                            PerformanceReactionMenuContent(
                                performanceID: row.performance.id,
                                context: reactionMenuContext
                            )

                            if let selectedSchedule = userScheduleOverlay.selectedSchedule {
                                membershipButton(
                                    row: row,
                                    schedule: selectedSchedule
                                )
                                Divider()
                            }

                            ForEach(userScheduleOverlay.schedules) { schedule in
                                membershipButton(
                                    row: row,
                                    schedule: schedule
                                )
                            }

                            Button {
                                store.send(.newUserScheduleButtonTapped(row.performanceID))
                            } label: {
                                Label("Add to a new schedule", systemImage: "plus")
                            }
                        }
                    }
                    .listStyle(.plain)
                    .onChange(of: scheduleNowScrollRequest) { _, request in
                        guard let request else { return }
                        if request.animated {
                            withAnimation {
                                proxy.scrollTo(request.performanceID, anchor: .center)
                            }
                        } else {
                            proxy.scrollTo(request.performanceID, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    var otherScheduleDivisions: [ScheduleViewer.ScheduleDivision] {
        ScheduleViewer.scheduleDivisions(stages: store.stages)
            .filter { $0 != store.scheduleDivision }
    }

    @ViewBuilder
    func membershipButton(
        row: PerformanceRow,
        schedule: UserSchedule
    ) -> some View {
        let isMember = userScheduleOverlay.contains(
            performanceID: row.performanceID,
            in: schedule.id
        )
        Button {
            store.send(
                .userScheduleMembershipButtonTapped(
                    row.performanceID,
                    schedule.id
                )
            )
        } label: {
            Label(
                "\(isMember ? "Remove from" : "Add to") \(schedule.title)",
                mappedSystemImage: userScheduleSystemImage
            )
        }
    }
}
