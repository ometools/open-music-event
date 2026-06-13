import BlueskyActorCache
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
            scheduleDivision: ScheduleDivision = .schedule
        ) {
            @Dependency(\.defaultEventTimeZone) var defaultEventTimeZone

            self.eventID = eventID
            self.timeZone = defaultEventTimeZone
            self.scheduleDivision = scheduleDivision
            self._scheduleViewerState = Shared(
                .scheduleViewerState(
                    eventID: eventID,
                    scheduleDivision: scheduleDivision
                )
            )
            _event = FetchOne(
                OMERecord.Event.where { $0.id.eq(eventID) }
            )
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
        public let scheduleDivision: ScheduleDivision
        public var destination: Destination.State?
        @Shared public var scheduleViewerState: ScheduleViewerState

        @FetchOne public var event: OMERecord.Event?
        public var scheduleMode: ScheduleMode {
            get { scheduleViewerState.scheduleMode }
            set {
                $scheduleViewerState.withLock {
                    $0.scheduleMode = newValue
                }
            }
        }

        public var showStageNameLabels: Bool {
            get { scheduleViewerState.showStageNameLabels }
            set {
                $scheduleViewerState.withLock {
                    $0.showStageNameLabels = newValue
                }
            }
        }

        public var selectedStageID: OMERecord.ID<OMERecord.Stage>? {
            get { scheduleViewerState.selectedStageID }
            set {
                $scheduleViewerState.withLock {
                    $0.selectedStageID = newValue
                }
            }
        }

        @FetchAll public var performanceRows: [PerformanceRow]
        @FetchAll public var schedules: [OMERecord.Schedule]
        @FetchAll public var stages: [OMERecord.Stage]

        public var performances: [OMERecord.Performance] {
            performanceRows.map(\.performance)
        }

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
            visiblePerformanceRows(selectedScheduleID: selectedScheduleID)
                .map(\.performance)
        }

        func visiblePerformanceRows(
            selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?
        ) -> [PerformanceRow] {
            ScheduleViewer.visiblePerformances(
                performanceRows: performanceRows,
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
        case addPerformanceButtonTapped(OMERecord.ID<OMERecord.Schedule>?)
        case addScheduleButtonTapped
        case destination(Destination.Action)
        case performanceButtonTapped(OMERecord.ID<OMERecord.Performance>)
        case scheduleModeButtonTapped(ScheduleMode)
    }

    @Feature
    public enum Destination {
        case editPerformance(Spawn<EditPerformance>)
        case editSchedule(Spawn<EditSchedule>)
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
        return schedule.date.formatted(dateFormat: "EEEE")
    }

    static func performanceRowSubtitle(
        for performance: OMERecord.Performance,
        timeZone: TimeZone
    ) -> String {
        "\(performanceRowTimeRange(for: performance, timeZone: timeZone)) \(daySegment(for: performance.startTime, timeZone: timeZone))"
    }

    private static func performanceRowTimeRange(
        for performance: OMERecord.Performance,
        timeZone: TimeZone
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm a"
        return "\(formatter.string(from: performance.startTime)) - \(formatter.string(from: performance.endTime))"
    }

    private static func daySegment(
        for date: Date,
        timeZone: TimeZone
    ) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        var displayDate = date
        let hour = calendar.component(.hour, from: date)
        let segment: String

        if hour < 6 {
            segment = "Night"
            displayDate = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        } else if hour < 12 {
            segment = "Morning"
        } else if hour < 17 {
            segment = "Afternoon"
        } else if hour < 20 {
            segment = "Evening"
        } else {
            segment = "Night"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEEE"
        return "\(formatter.string(from: displayDate)) \(segment)"
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
        performanceRows: [PerformanceRow],
        scheduleID: OMERecord.ID<OMERecord.Schedule>?,
        stages: [OMERecord.Stage]
    ) -> [PerformanceRow] {
        guard let scheduleID else { return [] }
        let visibleStageIDs = Set(stages.map(\.id.stageID))
        return performanceRows.filter {
            $0.performance.scheduleID == scheduleID
                && visibleStageIDs.contains($0.performance.stageID)
        }
    }

    static func visibleStages(
        stages: [OMERecord.Stage],
        division: ScheduleDivision
    ) -> [OMERecord.Stage] {
        stages.filter { $0.category == division.category }
    }

    static func canAddPerformance(
        selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?,
        schedules: [OMERecord.Schedule],
        stages: [OMERecord.Stage]
    ) -> Bool {
        !stages.isEmpty
            && schedules.contains { $0.id.scheduleID == selectedScheduleID }
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case let .addPerformanceButtonTapped(selectedScheduleID):
                guard let schedule = state.selectedSchedule(
                    selectedScheduleID: selectedScheduleID
                ),
                      !state.stages.isEmpty
                else { return }
                state.destination = .editPerformance(
                    Spawn(
                        EditPerformance.State(
                            eventID: state.eventID,
                            schedule: schedule,
                            stages: state.stages,
                            timeZone: state.timeZone
                        )
                    )
                )

            case .addScheduleButtonTapped:
                state.destination = .editSchedule(
                    Spawn(
                        EditSchedule.State(
                            eventID: state.eventID,
                            initialDate: state.event?.startDate,
                            timeZone: state.timeZone
                        )
                    )
                )

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
                ScheduleAddMenu(
                    store: store,
                    selectedScheduleID: selectedScheduleID
                )
            }
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
        .sheet(item: $store.scope(\.destination, action: \.destination).editSchedule) { editStore in
            NavigationStack {
                EditScheduleView(store: editStore)
            }
        }
        .sheet(item: $store.scope(\.destination, action: \.destination).editPerformance) { editStore in
            NavigationStack {
                EditPerformanceView(store: editStore)
            }
        }
        .navigationDestination(item: $store.scope(\.destination, action: \.destination).performanceDetail) { detailStore in
            PerformanceDetailView(store: detailStore)
        }
        .environment(\.showStageNameLabels, store.showStageNameLabels)
    }
}

struct ScheduleAddMenu: View {
    @Bindable var store: StoreOf<ScheduleViewer>
    let selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?

    var body: some View {
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
                    stages: store.stages
                )
            )
        } label: {
            Label("Add", systemImage: "plus")
        }
    }
}

struct ScheduleModeMenu: View {
    @Bindable var store: StoreOf<ScheduleViewer>

    var body: some View {
        Menu {
            Section("Mode") {
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
            }

            Section("Display") {
                Toggle(isOn: $store.showStageNameLabels.animation()) {
                    Label("Show Stage Labels", systemImage: "tag")
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
        let rows = store.state.visiblePerformanceRows(selectedScheduleID: selectedScheduleID)
        if rows.isEmpty {
            ViewerPlaceholderView(
                title: store.state.selectedScheduleTitle(selectedScheduleID: selectedScheduleID),
                systemImage: "calendar",
                description: "No performances have been added to this schedule division yet."
            )
        } else {
            List(rows) { row in
                Button {
                    store.send(.performanceButtonTapped(row.performanceID))
                } label: {
                    SchedulePerformanceRow(
                        row: row,
                        subtitle: ScheduleViewer.performanceRowSubtitle(
                            for: row.performance,
                            timeZone: store.timeZone
                        )
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
            eventID: OMERecord.Event.ID? = nil
        ) {
            @Dependency(\.defaultEventID) var defaultEventID

            self.eventID = eventID ?? defaultEventID
            self.performanceID = performanceID
            _contributors = FetchAll(
                PerformanceDetail.contributorsQuery(
                    performanceID: performanceID,
                    eventID: self.eventID,
                    hydration: .bskyActorProfile
                )
            )
            _performance = FetchOne(
                PerformanceDetail.performanceQuery(
                    performanceID: performanceID,
                    eventID: self.eventID
                )
            )
            _stages = FetchAll(
                ScheduleViewer.stagesQuery(eventID: self.eventID)
            )
        }

        public let eventID: OMERecord.Event.ID
        public let performanceID: OMERecord.ID<OMERecord.Performance>

        @FetchAll var contributors: [ContributorProfile]
        @FetchOne public var performance: OMERecord.Performance?
        @FetchAll public var stages: [OMERecord.Stage]

        public var id: OMERecord.ID<OMERecord.Performance> { performanceID }

        public var stage: OMERecord.Stage? {
            guard let performance else { return nil }
            return stages.first { $0.id.stageID == performance.stageID }
        }

        var actorProfileLoadRequests: [ContributorProfile.ActorProfileLoadRequest] {
            contributors.actorProfileLoadRequests
        }
    }

    public enum Action {}

    @Dependency(\.blueskyActorProfileCache) var blueskyActorProfileCache

    static func contributorsQuery(
        performanceID: OMERecord.ID<OMERecord.Performance>,
        eventID: OMERecord.Event.ID,
        hydration: ContributorProfile.Hydration = .none
    ) -> some Statement<ContributorProfile> {
        ContributorProfile.forPerformance(
            performanceID: performanceID,
            eventID: eventID,
            hydration: hydration
        )
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
            .onChange(of: store.actorProfileLoadRequests, initial: true) { _, requests, _ in
                guard !requests.isEmpty else { return }

                store.addTask {
                    for request in requests {
                        do {
                            _ = try await blueskyActorProfileCache.refreshProfileIfNeeded(
                                request.actor.description,
                                24 * 60 * 60,
                                15 * 60
                            )
                        } catch is CancellationError {
                            return
                        } catch {
                        }
                    }
                }
            }
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

                    if !store.contributors.isEmpty {
                        Section("Contributors") {
                            ForEach(store.contributors) { contributor in
                                ContributorsRowView(profile: contributor)
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
    let row: PerformanceRow
    let subtitle: String

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(row.stage?.color.swiftUIColor ?? .secondary.opacity(0.35))
                .frame(width: 5)

            stageIcon
                .frame(width: 60, height: 60)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .lineLimit(2)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .frame(height: 60)
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .foregroundStyle(.primary)
    }

    @ViewBuilder
    private var stageIcon: some View {
        if let stage = row.stage {
            ScheduleStageIcon(stage: stage)
        } else {
            Image(systemName: "music.note")
                .resizable()
                .scaledToFit()
                .padding(14)
                .foregroundStyle(.secondary)
        }
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
    func formatted(dateFormat: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = dateFormat
        formatter.timeZone = .current
        return formatter.string(from: atStartOfDay(in: .current))
    }

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
