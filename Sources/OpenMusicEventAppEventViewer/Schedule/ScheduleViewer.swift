import ComposableArchitecture2
import Dependencies
import Foundation
import ScheduleComponents
import Sharing
import SQLiteData
import SwiftUI
import Tagged

@Feature
public struct ScheduleViewer {
    public init() {}

    public struct ScheduleDivision: Hashable, Identifiable, Sendable {
        public init(category: OMERecord.Stage.Category?) {
            self.category = category
        }

        public var category: OMERecord.Stage.Category?
        public var id: String { category?.rawValue ?? "schedule" }

        public static let schedule = Self(category: nil)

        var systemImage: String {
            switch category?.rawValue {
            case nil:
                return "calendar"
            case "workshop":
                return "figure.mind.and.body"
            case "discussions":
                return "bubble.left.and.bubble.right"
            default:
                return "square.grid.2x2"
            }
        }

        var title: String {
            switch category?.rawValue {
            case nil:
                return "Schedule"
            case "workshop":
                return "Workshops"
            default:
                return category?.rawValue.scheduleDivisionTitle ?? "Schedule"
            }
        }

    }

    public enum ScheduleMode: String, CaseIterable, Hashable, Sendable {
        case singleStageAtOnce
        case list

        var title: String {
            switch self {
            case .singleStageAtOnce:
                return "Single Stage At Once"
            case .list:
                return "List"
            }
        }

        var systemImage: String {
            switch self {
            case .singleStageAtOnce:
                return "calendar.day.timeline.leading"
            case .list:
                return "list.bullet"
            }
        }
    }

    public struct State {
        public init(
            eventID: OMERecord.Event.ID,
            scheduleDivision: ScheduleDivision = .schedule,
            database: (any DatabaseReader)? = nil
        ) {
            self.eventID = eventID
            self.scheduleDivision = scheduleDivision
            _performances = FetchAll(
                ScheduleViewer.eventPerformancesQuery(eventID: eventID),
                database: database
            )
            _schedules = FetchAll(
                ScheduleViewer.schedulesQuery(eventID: eventID),
                database: database
            )
            _stages = FetchAll(
                ScheduleViewer.stagesQuery(eventID: eventID),
                database: database
            )
        }

        public let eventID: OMERecord.Event.ID
        public let scheduleDivision: ScheduleDivision
        public var destination: Destination.State?
        public var scheduleMode: ScheduleMode = .singleStageAtOnce
        public var selectedStageID: OMERecord.ID<OMERecord.Stage>?

        @FetchAll public var performances: [OMERecord.Performance]
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

        public func visiblePerformances(
            selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?
        ) -> [OMERecord.Performance] {
            ScheduleViewer.visiblePerformances(
                performances: performances,
                scheduleID: resolvedSelectedScheduleID(selectedScheduleID),
                stages: visibleStages
            )
        }

        public func visiblePerformancesForSelectedStage(
            selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?
        ) -> [OMERecord.Performance] {
            guard let selectedStageID = resolvedSelectedStageID else { return [] }
            return visiblePerformances(selectedScheduleID: selectedScheduleID)
                .filter { $0.stageID == selectedStageID }
        }

        func resolvedSelectedScheduleID(
            _ selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?
        ) -> OMERecord.ID<OMERecord.Schedule>? {
            if let selectedScheduleID,
               schedules.contains(where: { $0.id.scheduleID == selectedScheduleID }) {
                return selectedScheduleID
            }
            return schedules.first?.id.scheduleID
        }

        var resolvedSelectedStageID: OMERecord.ID<OMERecord.Stage>? {
            ScheduleViewer.resolvedSelectedStageID(
                selectedStageID: selectedStageID,
                stages: visibleStages
            )
        }

        func selectedScheduleTitle(
            selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?
        ) -> String {
            selectedSchedule(selectedScheduleID: selectedScheduleID)
                .map(ScheduleViewer.scheduleTitle) ?? "Select Schedule"
        }

        var selectedStage: OMERecord.Stage? {
            guard let resolvedSelectedStageID else { return nil }
            return visibleStages.first { $0.id.stageID == resolvedSelectedStageID }
        }

        var stagesByID: [OMERecord.ID<OMERecord.Stage>: OMERecord.Stage] {
            Dictionary(uniqueKeysWithValues: stages.map { ($0.id.stageID, $0) })
        }

        var visibleStages: [OMERecord.Stage] {
            ScheduleViewer.visibleStages(
                stages: stages,
                division: scheduleDivision
            )
        }
    }

    public enum Action {
        case destination(Destination.Action)
        case performanceButtonTapped(OMERecord.ID<OMERecord.Performance>)
        case scheduleModeButtonTapped(ScheduleMode)
    }

    @Feature
    public enum Destination {
        case performanceDetail(Spawn<PerformanceDetail>)
    }

    static func eventPerformancesQuery(
        eventID: OMERecord.Event.ID
    ) -> some SelectStatementOf<OMERecord.Performance> {
        OMERecord.Performance
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .order { ($0.startTime, $0.title.collate(.nocase)) }
    }

    static func performancesQuery(
        eventID: OMERecord.Event.ID,
        scheduleID: OMERecord.ID<OMERecord.Schedule>
    ) -> some SelectStatementOf<OMERecord.Performance> {
        OMERecord.Performance
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .where { $0.scheduleID.eq(scheduleID) }
            .order { ($0.startTime, $0.title.collate(.nocase)) }
    }

    static func schedulesQuery(
        eventID: OMERecord.Event.ID
    ) -> some SelectStatementOf<OMERecord.Schedule> {
        OMERecord.Schedule
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .order { ($0.date, $0.startsAt.asc(nulls: .last), $0.customTitle.asc(nulls: .last)) }
    }

    static func stagesQuery(
        eventID: OMERecord.Event.ID
    ) -> some SelectStatementOf<OMERecord.Stage> {
        OMERecord.Stage
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .order { ($0.sortIndex.asc(nulls: .last), $0.name.collate(.nocase)) }
    }

    static func scheduleTitle(_ schedule: OMERecord.Schedule) -> String {
        if let customTitle = schedule.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !customTitle.isEmpty {
            return customTitle
        }
        return schedule.date.formatted(dateStyle: .full)
    }

    static func resolvedSelectedStageID(
        selectedStageID: OMERecord.ID<OMERecord.Stage>?,
        stages: [OMERecord.Stage]
    ) -> OMERecord.ID<OMERecord.Stage>? {
        if let selectedStageID,
           stages.contains(where: { $0.id.stageID == selectedStageID }) {
            return selectedStageID
        }
        return stages.first?.id.stageID
    }

    static func scheduleDivisions(stages: [OMERecord.Stage]) -> [ScheduleDivision] {
        guard !stages.isEmpty else { return [] }

        var divisions: [ScheduleDivision] = [.schedule]
        var seenCategories = Set<OMERecord.Stage.Category>()
        for stage in stages {
            guard let category = stage.category, seenCategories.insert(category).inserted else {
                continue
            }
            divisions.append(ScheduleDivision(category: category))
        }
        return divisions
    }

    static func visiblePerformances(
        performances: [OMERecord.Performance],
        scheduleID: OMERecord.ID<OMERecord.Schedule>?,
        stages: [OMERecord.Stage]
    ) -> [OMERecord.Performance] {
        guard let scheduleID else { return [] }
        let visibleStageIDs = Set(stages.map(\.id.stageID))
        return performances.filter {
            $0.scheduleID == scheduleID && visibleStageIDs.contains($0.stageID)
        }
    }

    static func visibleStages(
        stages: [OMERecord.Stage],
        division: ScheduleDivision
    ) -> [OMERecord.Stage] {
        stages.filter { $0.category == division.category }
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .destination:
                break

            case let .performanceButtonTapped(performanceID):
                store.withDependencies {
                    state.destination = .performanceDetail(
                        Spawn(
                            PerformanceDetail.State(
                                performanceID: performanceID,
                                eventID: state.eventID
                            )
                        )
                    )
                }

            case let .scheduleModeButtonTapped(scheduleMode):
                state.scheduleMode = scheduleMode
            }
        }
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
    }
}

public struct ScheduleViewerView: View {
    @Bindable var store: StoreOf<ScheduleViewer>
    @Shared var selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?

    public init(
        store: StoreOf<ScheduleViewer>,
        selectedScheduleID: Shared<OMERecord.ID<OMERecord.Schedule>?>
    ) {
        self.store = store
        self._selectedScheduleID = selectedScheduleID
    }

    public var body: some View {
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
                        scheduleDivisionTitle: store.scheduleDivision.title,
                        selectedStage: store.selectedStage,
                        stages: store.visibleStages,
                        performances: store.state.visiblePerformances(
                            selectedScheduleID: selectedScheduleID
                        ),
                        selectedStageID: $store.selectedStageID
                    ) { performanceID in
                        store.send(.performanceButtonTapped(performanceID))
                    }

                case .list:
                    SchedulePerformanceListView(
                        store: store,
                        selectedScheduleID: selectedScheduleID
                    )
                }
            }
        }
        .navigationTitle(
            store.state.selectedScheduleTitle(selectedScheduleID: selectedScheduleID)
        )
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ScheduleModeMenu(store: store)
            }
        }
        .toolbarTitleMenu {
            ForEach(store.schedules) { schedule in
                Button(ScheduleViewer.scheduleTitle(schedule)) {
                    $selectedScheduleID.withLock {
                        $0 = schedule.id.scheduleID
                    }
                }
            }
        }
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationDestination(item: $store.scope(state: \.destination, action: \.destination).performanceDetail) { detailStore in
            PerformanceDetailView(store: detailStore)
        }
    }
}

struct ScheduleModeMenu: View {
    @Bindable var store: StoreOf<ScheduleViewer>

    var body: some View {
        Menu {
            ForEach(ScheduleViewer.ScheduleMode.allCases, id: \.self) { mode in
                Button {
                    store.send(.scheduleModeButtonTapped(mode))
                } label: {
                    Label {
                        Text(mode.title)
                    } icon: {
                        Image(systemName: store.scheduleMode == mode ? "checkmark" : mode.systemImage)
                    }
                }
            }
        } label: {
            Label(store.scheduleMode.title, systemImage: store.scheduleMode.systemImage)
        }
    }
}

struct SchedulePerformanceListView: View {
    @Bindable var store: StoreOf<ScheduleViewer>
    let selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?

    var body: some View {
        let performances = store.state.visiblePerformances(selectedScheduleID: selectedScheduleID)
        if performances.isEmpty {
            ViewerPlaceholderView(
                title: store.state.selectedScheduleTitle(selectedScheduleID: selectedScheduleID),
                systemImage: "calendar",
                description: "No performances have been added to this schedule division yet."
            )
        } else {
            List(performances) { performance in
                Button {
                    store.send(.performanceButtonTapped(performance.id.performanceID))
                } label: {
                    SchedulePerformanceRow(
                        performance: performance,
                        stage: store.stagesByID[performance.stageID]
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
    }
}

@Feature
public struct PerformanceDetail {
    public init() {}

    public struct State: Identifiable {
        public init(
            performanceID: OMERecord.ID<OMERecord.Performance>,
            eventID: OMERecord.Event.ID? = nil,
            database: (any DatabaseReader)? = nil
        ) {
            @Dependency(\.defaultEventID) var defaultEventID

            self.eventID = eventID ?? defaultEventID
            self.performanceID = performanceID
            _participants = FetchAll(
                PerformanceDetail.participantsQuery(
                    performanceID: performanceID,
                    eventID: self.eventID
                ),
                database: database
            )
            _performance = FetchOne(
                PerformanceDetail.performanceQuery(
                    performanceID: performanceID,
                    eventID: self.eventID
                ),
                database: database
            )
            _stages = FetchAll(
                ScheduleViewer.stagesQuery(eventID: self.eventID),
                database: database
            )
        }

        public let eventID: OMERecord.Event.ID
        public let performanceID: OMERecord.ID<OMERecord.Performance>

        @FetchAll public var participants: [OMERecord.Participant]
        @FetchOne public var performance: OMERecord.Performance?
        @FetchAll public var stages: [OMERecord.Stage]

        public var id: OMERecord.ID<OMERecord.Performance> { performanceID }

        public var stage: OMERecord.Stage? {
            guard let performance else { return nil }
            return stages.first { $0.id.stageID == performance.stageID }
        }
    }

    public enum Action {}

    static func participantsQuery(
        performanceID: OMERecord.ID<OMERecord.Performance>,
        eventID: OMERecord.Event.ID
    ) -> some SelectStatementOf<OMERecord.Participant> {
        OMERecord.Participant
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .where { participant in
                OMERecord.Performance.Participants
                    .where { $0.organizerID.eq(eventID.organizerID) }
                    .where { $0.eventID.eq(eventID.eventID) }
                    .where { $0.performanceID.eq(performanceID) }
                    .where { $0.participantID.eq(participant.id.participantID) }
                    .exists()
            }
            .order { $0.name.collate(.nocase) }
    }

    static func performanceQuery(
        performanceID: OMERecord.ID<OMERecord.Performance>,
        eventID: OMERecord.Event.ID
    ) -> some SelectStatementOf<OMERecord.Performance> {
        OMERecord.Performance
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .where { $0.id.performanceID.eq(performanceID) }
    }

    public var body: some Feature {
        Update { _, _ in }
    }
}

public struct PerformanceDetailView: View {
    @Bindable var store: StoreOf<PerformanceDetail>

    public init(store: StoreOf<PerformanceDetail>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if let performance = store.performance {
                List {
                    SchedulePerformanceHeader(
                        performance: performance,
                        stage: store.stage
                    )

                    if let description = performance.displayDescription {
                        Section("About") {
                            Text(description)
                        }
                    }

                    if !store.participants.isEmpty {
                        Section("People") {
                            ForEach(store.participants) { participant in
                                PeopleRowView(participant: participant)
                            }
                        }
                    }

                    if !performance.recordings.isEmpty {
                        Section("Recordings") {
                            ForEach(Array(performance.recordings.enumerated()), id: \.offset) { _, recording in
                                PerformanceRecordingRow(recording: recording)
                            }
                        }
                    }
                }
                .navigationTitle(performance.title)
            } else {
                ContentUnavailableView(
                    "Performance",
                    systemImage: "music.mic",
                    description: Text(verbatim: store.performanceID.rawValue.rawValue)
                )
                .navigationTitle("Performance")
            }
        }
    }
}

struct SchedulePerformanceHeader: View {
    let performance: OMERecord.Performance
    let stage: OMERecord.Stage?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(stage?.color.swiftUIColor ?? .secondary.opacity(0.35))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "music.note")
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 5) {
                Text(performance.title)
                    .font(.headline)

                Text(performance.timeRangeText)
                    .foregroundStyle(.secondary)

                if let stage {
                    Text(stage.name)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

struct PerformanceRecordingRow: View {
    let recording: ExternalPlatform.Asset

    var body: some View {
        if let url = recording.url {
            Link(destination: url) {
                Label(recording.platform.name, systemImage: "link")
            }
        } else if let record = recording.record {
            Label(record.uri.description, systemImage: "record.circle")
        } else {
            Label("Recording", systemImage: "play.circle")
        }
    }
}

struct SchedulePerformanceRow: View {
    let performance: OMERecord.Performance
    let stage: OMERecord.Stage?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(stage?.color.swiftUIColor ?? .secondary.opacity(0.35))
                .frame(width: 12, height: 12)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                Text(performance.title)
                    .font(.headline)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(performance.timeRangeText)
                    if let stage {
                        Text(stage.name)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                if let description = performance.displayDescription {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

extension OMERecord.Performance {
    var displayDescription: String? {
        let description = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        return description?.isEmpty == false ? description : nil
    }

    var timeRangeText: String {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: startTime, to: endTime)
    }
}

private extension LocalDate {
    func formatted(dateStyle: DateFormatter.Style) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = dateStyle
        formatter.timeStyle = .none
        formatter.timeZone = .current
        return formatter.string(from: atStartOfDay(in: .current))
    }
}

extension OMEColor {
    var swiftUIColor: Color {
        Color(
            red: Double((rawValue >> 16) & 0xFF) / 255.0,
            green: Double((rawValue >> 8) & 0xFF) / 255.0,
            blue: Double(rawValue & 0xFF) / 255.0
        )
    }
}

private extension String {
    var scheduleDivisionTitle: String {
        split { $0 == "-" || $0 == "_" || $0 == " " }
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}
