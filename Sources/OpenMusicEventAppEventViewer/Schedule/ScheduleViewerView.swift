import ComposableArchitecture2
import Sharing
import SwiftUI

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
        }
    }
}

public struct ScheduleModeMenu: View {
    @Environment(\.needsStageDisambiguation) var needsStageDisambiguation
    @Bindable var store: StoreOf<ScheduleViewer>

    public init(store: StoreOf<ScheduleViewer>) {
        self.store = store
    }

    public var body: some View {
        Menu {
            Section("Mode") {
                ForEach(ScheduleViewer.ScheduleMode.allCases, id: \.self) { mode in
                    Button {
                        store.send(.scheduleModeButtonTapped(mode))
                    } label: {
                        modeLabel(mode)
                    }
                }
            }

            if needsStageDisambiguation {
                Section("Display") {
                    Toggle(isOn: $store.showStageNameLabels.animation()) {
                        Label("Show Stage Labels", systemImage: "tag")
                    }
                }
            }
        } label: { selectedModeLabel }
    }

    @ViewBuilder
    func modeLabel(_ mode: ScheduleViewer.ScheduleMode) -> some View {
        if store.scheduleMode == mode {
            Label {
                Text(mode.title)
            } icon: {
                Image(systemName: "checkmark")
            }
        } else if let systemImage = mode.systemImage {
            Label(mode.title, systemImage: systemImage)
        } else {
            Text(mode.title)
        }
    }

    @ViewBuilder
    var selectedModeLabel: some View {
        if let systemImage = store.scheduleMode.systemImage {
            Label(store.scheduleMode.title, systemImage: systemImage)
        } else {
            Text(store.scheduleMode.title)
        }
    }
}

public struct ScheduleViewerView: View {
    @Bindable var store: StoreOf<ScheduleViewer>
    @Shared var selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?
    let showsAuthoringControls: Bool

    public init(
        store: StoreOf<ScheduleViewer>,
        selectedScheduleID: Shared<OMERecord.ID<OMERecord.Schedule>?>,
        showsAuthoringControls: Bool = true
    ) {
        self.store = store
        self._selectedScheduleID = selectedScheduleID
        self.showsAuthoringControls = showsAuthoringControls
    }

    public var body: some View {
        content
            .navigationTitle(
                store.state.selectedScheduleTitle(selectedScheduleID: selectedScheduleID)
            )
            .toolbar {
                if showsAuthoringControls {
                    ToolbarItem(placement: .primaryAction) {
                        ScheduleAddMenu(
                            store: store,
                            selectedScheduleID: selectedScheduleID
                        )
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    ScheduleModeMenu(store: store)
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
                switch store.scheduleMode {
                case .singleStageAtOnce:
                    ScheduleSingleStageAtOnceView(
                        store: store.spawn(\.singleStageAtOnce),
                        selectedScheduleID: _selectedScheduleID,
                        showsAuthoringControls: showsAuthoringControls
                    )

                case .manyStagesAtOnce:
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
}
