import ComposableArchitecture2
import Dependencies
import OpenMusicEventComponents
import OpenMusicEventLexicon
import Sharing
import SwiftUI

struct ScheduleNowScrollRequest: Equatable {
    let sequence: Int
    let performanceID: ProgramItem.ID
    let animated: Bool
}

enum ScheduleNowScrollRequestEnvironmentKey: EnvironmentKey {
    static let defaultValue: ScheduleNowScrollRequest? = nil
}

extension EnvironmentValues {
    var scheduleNowScrollRequest: ScheduleNowScrollRequest? {
        get { self[ScheduleNowScrollRequestEnvironmentKey.self] }
        set { self[ScheduleNowScrollRequestEnvironmentKey.self] = newValue }
    }
}

public struct ScheduleAddMenu: View {
    @Bindable var store: StoreOf<ScheduleViewer>
    let selectedScheduleID: Schedule.ID?

    public init(
        store: StoreOf<ScheduleViewer>,
        selectedScheduleID: Schedule.ID?
    ) {
        self.store = store
        self.selectedScheduleID = selectedScheduleID
    }

    public var body: some View {
        Menu {
            Button {
                store.send(.addScheduleButtonTapped)
            } label: {
                Label("Add Schedule", systemImage: "calendar.badge.plus")
            }

            Button {
                store.send(.addPerformanceButtonTapped(selectedScheduleID))
            } label: {
                Label("Add Performance", systemImage: "music.mic")
            }
            .disabled(
                !ScheduleViewer.canAddPerformance(
                    selectedScheduleID: selectedScheduleID,
                    schedules: store.schedules,
                    stages: store.stages,
                    event: store.event
                )
            )

            Divider()

            Button {
                store.send(.programsButtonTapped)
            } label: {
                Label("Programs…", systemImage: "calendar")
            }
        } label: {
            Label("Add", systemImage: "plus")
                .labelStyle(.iconOnly)
        }
    }
}

public struct ScheduleKindMenu: View {
    @Bindable var store: StoreOf<ScheduleViewer>

    public init(store: StoreOf<ScheduleViewer>) {
        self.store = store
    }

    public var body: some View {
        Menu {
            Section("Mode") {
                ForEach(ScheduleViewer.ScheduleKind.allCases, id: \.self) { scheduleKind in
                    scheduleKindButton(scheduleKind)
                }
            }

        } label: {
            selectedModeLabel
                .labelStyle(.iconOnly)
        }
        .accessibilityIdentifier("menu.schedule-kind")
    }

    @ViewBuilder
    func scheduleKindButton(_ scheduleKind: ScheduleViewer.ScheduleKind) -> some View {
        Button {
            store.send(.scheduleKindButtonTapped(scheduleKind))
        } label: {
            modeLabel(
                title: scheduleKind.title,
                systemImage: scheduleKind.systemImage,
                isSelected: store.scheduleKind == scheduleKind
            )
        }
        .accessibilityIdentifier("button.schedule-kind.\(scheduleKind.rawValue)")
    }

    @ViewBuilder
    func modeLabel(
        title: String,
        systemImage: String?,
        isSelected: Bool
    ) -> some View {
        if isSelected {
            Label {
                Text(title)
            } icon: {
                Image(systemName: "checkmark")
            }
        } else if let systemImage {
            Label(title, mappedSystemImage: systemImage)
        } else {
            Text(title)
        }
    }

    @ViewBuilder
    var selectedModeLabel: some View {
        if let systemImage = store.scheduleKind.systemImage {
            Label(
                store.scheduleKind.title,
                mappedSystemImage: systemImage
            )
        } else {
            Text(store.scheduleKind.title)
        }
    }
}

public struct UserScheduleFilterMenu: View {
    @Bindable var store: StoreOf<ScheduleViewer>

    public init(store: StoreOf<ScheduleViewer>) {
        self.store = store
    }

    public var body: some View {
        Menu {
            Button {
                store.send(.userScheduleButtonTapped(nil))
            } label: {
                selectionLabel(
                    title: "Event Schedule",
                    isSelected: store.state.userScheduleOverlay.selectedSchedule == nil
                )
            }

            ForEach(store.userSchedules) { schedule in
                Button {
                    store.send(.userScheduleButtonTapped(schedule.id))
                } label: {
                    selectionLabel(
                        title: schedule.title,
                        isSelected: store.state.userScheduleOverlay.selectedSchedule?.id == schedule.id
                    )
                }
            }

            Divider()

            Button {
                store.send(.schedulesButtonTapped)
            } label: {
                Label("Schedules…", mappedSystemImage: userScheduleSystemImage)
            }
        } label: {
            if store.state.userScheduleOverlay.selectedSchedule != nil {
                Label(
                    store.state.userScheduleOverlay.selectedTitle,
                    mappedSystemImage: userScheduleSystemImage
                )
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.tint)
            } else {
                Label(store.state.userScheduleOverlay.selectedTitle, systemImage: "calendar")
                    .labelStyle(.iconOnly)
            }
        }
        .accessibilityLabel("Schedule filter, \(store.state.userScheduleOverlay.selectedTitle)")
    }

    @ViewBuilder
    func selectionLabel(title: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }
}

public struct ScheduleViewerView: View {
    @Dependency(\.date.now) var now
    @Environment(\.scheduleTimeBuffer) var scheduleTimeBuffer
    @Bindable var store: StoreOf<ScheduleViewer>
    @Binding var selectedScheduleID: Schedule.ID?
    @Binding var pendingScheduleLaunchAction: EventViewer.ScheduleLaunchAction?
    @State var nowScrollRequest: ScheduleNowScrollRequest?
    @State var nowScrollSequence = 0
    let showsAuthoringControls: Bool

    public init(
        store: StoreOf<ScheduleViewer>,
        selectedScheduleID: Binding<Schedule.ID?>,
        pendingScheduleLaunchAction: Binding<EventViewer.ScheduleLaunchAction?>,
        showsAuthoringControls: Bool = true
    ) {
        self.store = store
        self._selectedScheduleID = selectedScheduleID
        self._pendingScheduleLaunchAction = pendingScheduleLaunchAction
        self.showsAuthoringControls = showsAuthoringControls
    }

    public var body: some View {
        chromeContent
            .confirmationDialog(
                "Delete Performance?",
                isPresented: $store.scope(\.destination).deletePerformanceConfirmation.isPresented,
                titleVisibility: .visible
            ) {
                Button("Delete Performance", role: .destructive) {
                    if let performanceID = store.destination?.deletePerformanceConfirmation?.performanceID {
                        store.send(
                            .destination(
                                .deletePerformanceConfirmation(
                                    .deleteButtonTapped(performanceID)
                                )
                            )
                        )
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the performance from this schedule.")
            }
            .navigationDestination(item: $store.scope(\.destination).performanceDetail) { detailStore in
                PerformanceDetailView(
                    store: detailStore,
                    showsAuthoringControls: showsAuthoringControls
                )
            }
            .sheet(item: $store.scope(\.destination).reactionEntry) { entryStore in
                PerformanceReactionEntryView(store: entryStore)
            }
            .navigationDestination(item: $store.scope(\.destination).userSchedulesList) { schedulesStore in
                UserSchedulesListView(store: schedulesStore)
            }
            .navigationDestination(item: $store.scope(\.destination).programs) { programsStore in
                ManageProgramsView(store: programsStore)
            }
            .navigationDestination(item: $store.scope(\.destination).userScheduleForm) { formStore in
                UserScheduleFormView(store: formStore)
            }
            .environment(\.showStageNameLabels, store.showStageNameLabels)
            .environment(\.scheduleNowScrollRequest, nowScrollRequest)
            .environment(
                \.performanceReactionMenuContext,
                PerformanceReactionMenuContext(
                    reactions: store.reactions,
                    usage: store.reactionUsage,
                    toggle: { performanceID, emoji in
                        store.send(.reactionButtonTapped(performanceID, emoji))
                    },
                    showOther: { performanceID in
                        store.send(.otherReactionButtonTapped(performanceID))
                    }
                )
            )
            .onAppear {
                consumePendingScheduleLaunchAction()
            }
    }

    var chromeContent: some View {
        content
            .scheduleAccessibilityIdentifier(
                "view.schedule.\(store.eventID.description)"
            )
            .navigationTitle(navigationTitle)
            .toolbar {
                #if os(macOS) && !SKIP
                ToolbarItem(placement: .automatic) {
                    UserScheduleFilterMenu(store: store)
                }
                #else
                ToolbarItem(placement: .topBarLeading) {
                    UserScheduleFilterMenu(store: store)
                }
                #endif

                if currentTimeDestination != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Now") {
                            jumpToCurrentTime(animated: true)
                        }
                    }
                }
                if showsAuthoringControls {
                    ToolbarItem(placement: .primaryAction) {
                        ScheduleAddMenu(
                            store: store,
                            selectedScheduleID: selectedScheduleID
                        )
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    ScheduleKindMenu(store: store)
                }
            }
            .toolbarTitleMenu {
                if let timeZone = store.timeZone {
                    ForEach(store.schedules) { schedule in
                        Button(ScheduleViewer.scheduleTitle(schedule, in: timeZone)) {
                            selectedScheduleID = schedule.id
                        }
                        .accessibilityIdentifier(
                            "button.schedule-day.\(schedule.id.description)"
                        )
                    }
                }
            }
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
    }

    var selectedScheduleTitle: String {
        store.state.selectedScheduleTitle(selectedScheduleID: selectedScheduleID)
    }

    var navigationTitle: String {
        selectedScheduleTitle
    }

    @ViewBuilder
    var content: some View {
        Group {
            if store.schedules.isEmpty {
                ViewerPlaceholderView(
                    title: "Schedule coming soon",
                    systemImage: "calendar",
                    description: "Check back for times and stages."
                )
            } else {
                switch store.scheduleKind {
                case .singleStageAtOnce:
                    ScheduleSingleStageAtOnceView(
                        store: store.spawn(\.singleStageAtOnce),
                        selectedScheduleID: _selectedScheduleID,
                        userScheduleOverlay: store.state.userScheduleOverlay,
                        showsAuthoringControls: showsAuthoringControls,
                        performanceButtonTapped: {
                            store.send(.performanceButtonTapped($0))
                        }
                    )

                case let .allStagesAtOnce(orientation):
                    ScheduleManyStagesAtOnceView(
                        store: store.spawn(\.manyStagesAtOnce),
                        orientation: orientation,
                        selectedScheduleID: _selectedScheduleID,
                        userScheduleOverlay: store.state.userScheduleOverlay,
                        showsAuthoringControls: showsAuthoringControls,
                        performanceButtonTapped: {
                            store.send(.performanceButtonTapped($0))
                        }
                    )

                case .list:
                    SchedulePerformanceListView(
                        store: store.spawn(\.performanceList),
                        selectedScheduleID: selectedScheduleID,
                        userScheduleOverlay: store.state.userScheduleOverlay,
                        showsAuthoringControls: showsAuthoringControls,
                        performanceButtonTapped: {
                            store.send(.performanceButtonTapped($0))
                        }
                    )
                }
            }
        }
    }

    var currentTimeDestination: ScheduleViewer.CurrentTimeDestination? {
        store.state.currentTimeDestination(
            currentDate: now,
            selectedScheduleID: selectedScheduleID,
            buffer: scheduleTimeBuffer
        )
    }

    func consumePendingScheduleLaunchAction() {
        guard pendingScheduleLaunchAction == .jumpToCurrentTime else { return }
        pendingScheduleLaunchAction = nil
        jumpToCurrentTime(animated: false)
    }

    func jumpToCurrentTime(animated: Bool) {
        guard let destination = currentTimeDestination else { return }
        selectedScheduleID = destination.scheduleID
        nowScrollSequence += 1
        nowScrollRequest = ScheduleNowScrollRequest(
            sequence: nowScrollSequence,
            performanceID: destination.performanceID,
            animated: animated
        )
    }
}

private extension View {
    @ViewBuilder
    func scheduleAccessibilityIdentifier(_ identifier: String) -> some View {
        #if os(iOS) || os(macOS)
        // Keep the screen marker beside the content. Applying the identifier to
        // the whole screen makes SwiftUI's generated picker subviews inherit it.
        overlay(alignment: .topLeading) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Schedule"))
                .accessibilityIdentifier(identifier)
        }
        #else
        accessibilityIdentifier(identifier)
        #endif
    }
}
