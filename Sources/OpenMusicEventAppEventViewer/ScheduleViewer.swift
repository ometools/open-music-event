import ComposableArchitecture2
import Dependencies
import Foundation
import SQLiteData
import SwiftUI
import Tagged

@Feature
public struct ScheduleViewer {
    public init() {}

    public enum ScheduleStyle: String, CaseIterable, Hashable, Sendable {
        case list
        case timeline
        case grid
    }

    public struct State {
        public init(
            eventID: OMERecord.Event.ID,
            database: (any DatabaseReader)? = nil
        ) {
            self.eventID = eventID
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
        public var destination: Destination.State?
        public var scheduleStyle: ScheduleStyle = .list
        public var selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?

        @FetchAll public var performances: [OMERecord.Performance]
        @FetchAll public var schedules: [OMERecord.Schedule]
        @FetchAll public var stages: [OMERecord.Stage]

        public var selectedSchedule: OMERecord.Schedule? {
            guard let selectedScheduleID = resolvedSelectedScheduleID else { return nil }
            return schedules.first { $0.id.scheduleID == selectedScheduleID }
        }

        public var visiblePerformances: [OMERecord.Performance] {
            guard let selectedScheduleID = resolvedSelectedScheduleID else { return [] }
            return performances.filter { $0.scheduleID == selectedScheduleID }
        }

        var resolvedSelectedScheduleID: OMERecord.ID<OMERecord.Schedule>? {
            if let selectedScheduleID,
               schedules.contains(where: { $0.id.scheduleID == selectedScheduleID }) {
                return selectedScheduleID
            }
            return schedules.first?.id.scheduleID
        }

        var selectedScheduleTitle: String {
            selectedSchedule.map(ScheduleViewer.scheduleTitle) ?? "Select Schedule"
        }

        var stagesByID: [OMERecord.ID<OMERecord.Stage>: OMERecord.Stage] {
            Dictionary(uniqueKeysWithValues: stages.map { ($0.id.stageID, $0) })
        }
    }

    public enum Action {
        case destination(Destination.Action)
        case performanceButtonTapped(OMERecord.ID<OMERecord.Performance>)
        case scheduleTitleMenuButtonTapped(OMERecord.ID<OMERecord.Schedule>)
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

            case let .scheduleTitleMenuButtonTapped(scheduleID):
                state.selectedScheduleID = scheduleID
            }
        }
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
    }
}

public struct ScheduleViewerView: View {
    @Bindable var store: StoreOf<ScheduleViewer>

    public init(store: StoreOf<ScheduleViewer>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if store.schedules.isEmpty {
                ViewerPlaceholderView(
                    title: "Schedule",
                    systemImage: "calendar",
                    description: "No schedule has been added to this event yet."
                )
            } else if store.visiblePerformances.isEmpty {
                ViewerPlaceholderView(
                    title: store.selectedScheduleTitle,
                    systemImage: "calendar",
                    description: "No performances have been added to this schedule yet."
                )
            } else {
                List(store.visiblePerformances) { performance in
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
        .navigationTitle(store.selectedScheduleTitle)
        .toolbarTitleMenu {
            ForEach(store.schedules) { schedule in
                Button(ScheduleViewer.scheduleTitle(schedule)) {
                    store.send(.scheduleTitleMenuButtonTapped(schedule.id.scheduleID))
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

private extension OMERecord.Performance {
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

private extension OMEColor {
    var swiftUIColor: Color {
        Color(
            red: Double((rawValue >> 16) & 0xFF) / 255.0,
            green: Double((rawValue >> 8) & 0xFF) / 255.0,
            blue: Double(rawValue & 0xFF) / 255.0
        )
    }
}
