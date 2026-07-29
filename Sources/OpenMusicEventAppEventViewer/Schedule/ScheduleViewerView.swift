import ComposableArchitecture2
import Dependencies
import Sharing
import SwiftUI

struct ScheduleNowScrollRequest: Equatable {
    let sequence: Int
    let performanceID: OMERecord.ID<OMERecord.Performance>
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
    let selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?

    public init(
        store: StoreOf<ScheduleViewer>,
        selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?
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
        } label: {
            Label("Add", systemImage: "plus")
                .labelStyle(.iconOnly)
        }
    }
}

public struct ScheduleKindMenu: View {
    @Environment(\.needsStageDisambiguation) var needsStageDisambiguation
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

            if needsStageDisambiguation {
                Section("Display") {
                    Toggle(isOn: $store.showStageNameLabels.animation()) {
                        Label("Show Stage Labels", systemImage: "tag")
                    }
                }
            }
        } label: {
            selectedModeLabel
                .labelStyle(.iconOnly)
        }
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
            Label(title, systemImage: systemImage)
        } else {
            Text(title)
        }
    }

    @ViewBuilder
    var selectedModeLabel: some View {
        if let systemImage = store.scheduleKind.systemImage {
            Label(store.scheduleKind.title, systemImage: systemImage)
        } else {
            Text(store.scheduleKind.title)
        }
    }
}

public struct ScheduleViewerView: View {
    @Dependency(\.date.now) var now
    @Environment(\.scheduleTimeBuffer) var scheduleTimeBuffer
    @Bindable var store: StoreOf<ScheduleViewer>
    @Shared var selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?
    @Binding var pendingScheduleLaunchAction: EventViewer.ScheduleLaunchAction?
    @State var nowScrollRequest: ScheduleNowScrollRequest?
    @State var nowScrollSequence = 0
    let showsAuthoringControls: Bool

    public init(
        store: StoreOf<ScheduleViewer>,
        selectedScheduleID: Shared<OMERecord.ID<OMERecord.Schedule>?>,
        pendingScheduleLaunchAction: Binding<EventViewer.ScheduleLaunchAction?>,
        showsAuthoringControls: Bool = true
    ) {
        self.store = store
        self._selectedScheduleID = selectedScheduleID
        self._pendingScheduleLaunchAction = pendingScheduleLaunchAction
        self.showsAuthoringControls = showsAuthoringControls
    }

    public var body: some View {
        content
            .navigationTitle(
                store.state.selectedScheduleTitle(selectedScheduleID: selectedScheduleID)
            )
            .toolbar {
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
                if !store.state.usesSingletonSchedule {
                    ForEach(store.schedules) { schedule in
                        Button(ScheduleViewer.scheduleTitle(schedule)) {
                            $selectedScheduleID.withLock {
                                $0 = schedule.id.scheduleID
                            }
                        }
                    }
                }
            }
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .confirmationDialog(
                "Delete Performance?",
                isPresented: $store.scope(\.destination, action: \.destination).deletePerformanceConfirmation.isPresented,
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
            .navigationDestination(item: $store.scope(\.destination, action: \.destination).performanceDetail) { detailStore in
                PerformanceDetailView(
                    store: detailStore,
                    showsAuthoringControls: showsAuthoringControls
                )
            }
            .environment(\.showStageNameLabels, store.showStageNameLabels)
            .environment(\.scheduleNowScrollRequest, nowScrollRequest)
            .onAppear {
                consumePendingScheduleLaunchAction()
            }
    }

    @ViewBuilder
    var content: some View {
        Group {
            if store.schedules.isEmpty {
                ViewerPlaceholderView(
                    title: "Schedule",
                    systemImage: "calendar",
                    description: "No schedule has been added to this event yet."
                )
            } else {
                switch store.scheduleKind {
                case .singleStageAtOnce:
                    ScheduleSingleStageAtOnceView(
                        store: store.spawn(\.singleStageAtOnce),
                        selectedScheduleID: _selectedScheduleID,
                        showsAuthoringControls: showsAuthoringControls
                    )

                case .allStagesAtOnce:
                    ScheduleManyStagesAtOnceView(
                        store: store.spawn(\.manyStagesAtOnce),
                        selectedScheduleID: _selectedScheduleID,
                        showsAuthoringControls: showsAuthoringControls
                    )

                case .list:
                    SchedulePerformanceListView(
                        store: store.spawn(\.performanceList),
                        selectedScheduleID: selectedScheduleID,
                        showsAuthoringControls: showsAuthoringControls
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
        $selectedScheduleID.withLock {
            $0 = destination.scheduleID
        }
        nowScrollSequence += 1
        nowScrollRequest = ScheduleNowScrollRequest(
            sequence: nowScrollSequence,
            performanceID: destination.performanceID,
            animated: animated
        )
    }
}
