import OpenMusicEventLexicon
import ATProto
import ATProtoTypes
import HeroImageList
import Bluesky
import ComposableForms
import ComposableArchitecture2
import Dependencies
import Foundation
#if !SKIP && canImport(AppKit)
import AppKit
#elseif !SKIP && canImport(UIKit)
import UIKit
#endif
import OpenMusicEventComponents
import OpenMusicEventDatabase
import OpenMusicEventEditors
import OpenMusicEventImages
import ScheduleComponents
import Sharing
import SQLiteData
import SwiftUITabFeatures
import SwiftUI
import Tagged

@Feature
public struct StagesViewer {
    public init() {}

    public struct State {
        public init(
            eventID: Event.ID,
            destination: Destination.State? = nil
        ) {
            self.eventID = eventID
            self.destination = destination
            _eventPlaces = FetchAll(
                StagesViewer.stagesQuery(eventID: eventID)
            )
        }

        public let eventID: Event.ID
        public var destination: Destination.State?
        public var errorMessage: String?
        public var searchText = ""

        @FetchAll public var eventPlaces: [EventPlace]

        public var stages: [EventPlace] {
            eventPlaces
                .filter { $0.stageUse != nil }
                .sorted { lhs, rhs in
                    let left = lhs.stageUse?.sortIndex ?? Int.max
                    let right = rhs.stageUse?.sortIndex ?? Int.max
                    return left == right
                        ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                        : left < right
                }
        }

        public var canCopyStagesFromOtherEvent: Bool {
            stages.isEmpty
        }

        public var filteredStages: [EventPlace] {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return stages }

            return stages.filter { stage in
                stage.name.localizedStandardContains(query)
                    || stage.stageUse?.category?.localizedStandardContains(query) == true
            }
        }
    }

    public enum Action {
        case addButtonTapped
        case deleteStages([EventPlace.ID])
        case destination(Destination.Action)
        case fromOtherEventButtonTapped
        case stageButtonTapped(EventPlace.ID)
    }

    @Feature
    public enum Destination {
        case stageDetail(Spawn<StageDetail>)
    }

    @Dependency(\.defaultDatabase) var database

    static func stagesQuery(
        eventID: Event.ID
    ) -> some SelectStatementOf<EventPlace> {
        EventPlace.where { $0.event.eq(eventID) }
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .addButtonTapped:
                let eventID = state.eventID
                store.addTask {
                    let task = try store.post(
                        key: EventEditingRequested.self,
                        value: .createStage(eventID)
                    )
                    await task?.value
                }

            case let .deleteStages(stageIDs):
                let eventID = state.eventID
                store.addTask {
                    do {
                        try database.write { db in
                            for stageID in stageIDs {
                                try EventPlaceRecordEditing.delete(
                                    stageID,
                                    eventID: eventID,
                                    in: db
                                )
                            }
                        }
                        try store.modify {
                            $0.errorMessage = nil
                        }
                    } catch {
                        try store.modify {
                            $0.errorMessage = "Unable to delete event stage."
                        }
                    }
                }

            case .destination:
                break

            case .fromOtherEventButtonTapped:
                guard state.canCopyStagesFromOtherEvent else {
                    state.errorMessage = "This event already has stages."
                    return
                }

                state.errorMessage = nil
                let eventID = state.eventID
                store.addTask {
                    let task = try store.post(
                        key: EventEditingRequested.self,
                        value: .copyStagesFromEvent(eventID)
                    )
                    await task?.value
                }

            case let .stageButtonTapped(stageID):
                store.withDependencies {
                    state.destination = .stageDetail(
                        Spawn(.init(stageID: stageID, eventID: state.eventID))
                    )
                }
            }
        }
        .ifLet(\.destination) {
            Destination.body
        }
    }

}

@Feature
public struct CopyStagesFromEvent {
    public init() {}

    public struct SourceEventOption: Equatable, Identifiable, Sendable {
        public var endDate: LocalDate?
        public var id: Event.ID
        public var name: String
        public var stageCount: Int
        public var startDate: LocalDate?

        var subtitle: String {
            let stageText = stageCount == 1 ? "1 stage" : "\(stageCount) stages"
            guard let dateText else { return stageText }
            return "\(dateText) - \(stageText)"
        }

        private var dateText: String? {
            switch (startDate, endDate) {
            case let (.some(startDate), .some(endDate)) where endDate != startDate:
                "\(startDate) - \(endDate)"
            case let (.some(startDate), _):
                startDate.description
            case let (_, .some(endDate)):
                endDate.description
            case (.none, .none):
                nil
            }
        }
    }

    public struct State {
        public init(eventID: Event.ID) {
            self.eventID = eventID
        }

        public let eventID: Event.ID
        public var errorMessage: String?
        public var isCopying = false
        public var isLoading = false
        public var selectedSourceEventID: Event.ID?
        public var selectedStageIDs: Set<EventPlace.ID> = []
        public var sourceEvents: [SourceEventOption] = []
        public var sourceStages: [EventPlace] = []

        var canCopy: Bool {
            !isCopying
                && !isLoading
                && selectedSourceEventID != nil
                && !selectedStageIDs.isEmpty
        }

        var isEveryStageSelected: Bool {
            !sourceStages.isEmpty
                && selectedStageIDs == Set(sourceStages.map(\.id))
        }

        var selectAllButtonTitle: String {
            isEveryStageSelected ? "Clear" : "Select All"
        }
    }

    public enum Action {
        case copyButtonTapped
        case selectAllStagesButtonTapped
        case sourceEventButtonTapped(Event.ID)
        case stageButtonTapped(EventPlace.ID)
        case task
    }

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.date.now) var now

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .copyButtonTapped:
                guard let selectedSourceEventID = state.selectedSourceEventID else {
                    state.errorMessage = "Choose an event."
                    return
                }
                guard !state.selectedStageIDs.isEmpty else {
                    state.errorMessage = "Choose at least one stage."
                    return
                }
                guard !state.isCopying else { return }

                let destinationEventID = state.eventID
                let selectedStageIDs = state.selectedStageIDs
                let createdAt = now
                state.errorMessage = nil
                state.isCopying = true
                store.addTask {
                    do {
                        _ = try database.write { db in
                            try Self.copyStages(
                                from: selectedSourceEventID,
                                stageIDs: selectedStageIDs,
                                to: destinationEventID,
                                createdAt: createdAt,
                                in: db
                            )
                        }
                        try store.modify {
                            $0.errorMessage = nil
                            $0.isCopying = false
                        }
                        try store.dismiss()
                    } catch let error as CopyStagesFromEventError {
                        try store.modify {
                            $0.errorMessage = error.message
                            $0.isCopying = false
                        }
                    } catch {
                        try store.modify {
                            $0.errorMessage = "Unable to copy stages."
                            $0.isCopying = false
                        }
                    }
                }

            case .selectAllStagesButtonTapped:
                if state.isEveryStageSelected {
                    state.selectedStageIDs = []
                } else {
                    state.selectedStageIDs = Set(state.sourceStages.map(\.id))
                }
                state.errorMessage = nil

            case let .sourceEventButtonTapped(sourceEventID):
                guard state.sourceEvents.contains(where: { $0.id == sourceEventID }) else {
                    return
                }
                guard state.selectedSourceEventID != sourceEventID else { return }

                state.errorMessage = nil
                state.isLoading = true
                state.selectedSourceEventID = sourceEventID
                state.selectedStageIDs = []
                state.sourceStages = []
                store.addTask {
                    do {
                        let sourceStages = try database.read { db in
                            try Self.sourceStages(
                                eventID: sourceEventID,
                                in: db
                            )
                        }
                        try store.modify {
                            $0.errorMessage = nil
                            $0.isLoading = false
                            $0.selectedStageIDs = Set(sourceStages.map(\.id))
                            $0.sourceStages = sourceStages
                        }
                    } catch {
                        try store.modify {
                            $0.errorMessage = "Unable to load stages."
                            $0.isLoading = false
                        }
                    }
                }

            case let .stageButtonTapped(stageID):
                guard state.sourceStages.contains(where: { $0.id == stageID }) else {
                    return
                }
                if state.selectedStageIDs.contains(stageID) {
                    state.selectedStageIDs.remove(stageID)
                } else {
                    state.selectedStageIDs.insert(stageID)
                }
                state.errorMessage = nil

            case .task:
                guard !state.isLoading else { return }

                let eventID = state.eventID
                state.errorMessage = nil
                state.isLoading = true
                store.addTask {
                    do {
                        let sourceEvents = try database.read { db in
                            try Self.sourceEventOptions(
                                for: eventID,
                                in: db
                            )
                        }
                        let selectedSourceEventID = sourceEvents.first?.id
                        let sourceStages = try database.read { db in
                            try selectedSourceEventID.map {
                                try Self.sourceStages(eventID: $0, in: db)
                            } ?? []
                        }
                        try store.modify {
                            $0.errorMessage = sourceEvents.isEmpty
                                ? "No other events have stages to copy."
                                : nil
                            $0.isLoading = false
                            $0.selectedSourceEventID = selectedSourceEventID
                            $0.selectedStageIDs = Set(sourceStages.map(\.id))
                            $0.sourceEvents = sourceEvents
                            $0.sourceStages = sourceStages
                        }
                    } catch {
                        try store.modify {
                            $0.errorMessage = "Unable to load events."
                            $0.isLoading = false
                        }
                    }
                }
            }
        }
    }

    enum CopyStagesFromEventError: Error, Equatable, Sendable {
        case selectedStagesNotFound

        var message: String {
            switch self {
            case .selectedStagesNotFound:
                "Choose at least one stage."
            }
        }
    }

    static func copyStages(
        from sourceEventID: Event.ID,
        stageIDs: Set<EventPlace.ID>,
        to destinationEventID: Event.ID,
        createdAt: Date,
        in db: Database
    ) throws -> Int {
        let sourceStages = try sourceStages(eventID: sourceEventID, in: db)
            .filter { stageIDs.contains($0.id) }
        guard !sourceStages.isEmpty else {
            throw CopyStagesFromEventError.selectedStagesNotFound
        }

        for stage in sourceStages {
            var fields = EventPlaceRecordEditing.Fields(stage)
            if case var .known(.stage(use)) = fields.kind {
                use.lineup = nil
                fields.kind = .known(.stage(use))
            }
            _ = try EventPlaceRecordEditing.create(
                eventID: destinationEventID,
                fields: fields,
                createdAt: createdAt,
                in: db
            )
        }

        return sourceStages.count
    }

    static func sourceEventOptions(
        for eventID: Event.ID,
        in db: Database
    ) throws -> [SourceEventOption] {
        let events = try Event.all.fetchAll(db)
            .filter { $0.id.authority == eventID.authority }
        let stages = try EventPlace.all.fetchAll(db)
            .filter { $0.id.authority == eventID.authority && $0.stageUse != nil }
        let stageCounts = Dictionary(
            grouping: stages,
            by: \.event
        )
        .mapValues(\.count)

        return events
            .filter { $0.id != eventID }
            .compactMap { event -> SourceEventOption? in
                let stageCount = stageCounts[event.id] ?? 0
                guard stageCount > 0 else { return nil }
                return SourceEventOption(
                    endDate: localDay(event.end),
                    id: event.id,
                    name: event.name,
                    stageCount: stageCount,
                    startDate: localDay(event.start)
                )
            }
            .sorted(by: SourceEventOption.sort)
    }

    static func sourceStages(
        eventID: Event.ID,
        in db: Database
    ) throws -> [EventPlace] {
        try StagesViewer
            .stagesQuery(eventID: eventID)
            .fetchAll(db)
            .filter { $0.stageUse != nil }
            .sorted { lhs, rhs in
                let left = lhs.stageUse?.sortIndex ?? Int.max
                let right = rhs.stageUse?.sortIndex ?? Int.max
                return left == right
                    ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                    : left < right
            }
    }

    private static func localDay(_ value: Open<Event.Time>?) -> LocalDate? {
        guard case let .some(.known(.day(day))) = value else { return nil }
        return day.value
    }
}

private extension CopyStagesFromEvent.SourceEventOption {
    static func sort(lhs: Self, rhs: Self) -> Bool {
        switch (lhs.startDate, rhs.startDate) {
        case let (.some(lhsDate), .some(rhsDate)) where lhsDate != rhsDate:
            lhsDate > rhsDate
        case (.some, .none):
            true
        case (.none, .some):
            false
        default:
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

public struct StagesViewerView: View {
    @Bindable var store: StoreOf<StagesViewer>
    let showsAuthoringControls: Bool

    public init(
        store: StoreOf<StagesViewer>,
        showsAuthoringControls: Bool = true
    ) {
        self.store = store
        self.showsAuthoringControls = showsAuthoringControls
    }

    public var body: some View {
        Group {
            if store.stages.isEmpty {
                EmptyStagesView(
                    errorMessage: store.errorMessage,
                    showsAuthoringControls: showsAuthoringControls,
                    onAddStage: {
                        store.send(.addButtonTapped)
                    },
                    onCopyFromOtherEvent: {
                        store.send(.fromOtherEventButtonTapped)
                    }
                )
            } else if store.filteredStages.isEmpty {
                ViewerPlaceholderView(
                    title: "No Results",
                    systemImage: "square.grid.2x2",
                    description: "No stages match your search."
                )
            } else {
                List {
                    if let errorMessage = store.errorMessage {
                        Section {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }

                    ForEach(store.filteredStages) { stage in
                        Button {
                            store.send(.stageButtonTapped(stage.id))
                        } label: {
                            EventPlaceStageRowView(place: stage)
                        }
                        .navigationLinkListRowStyle()
                        .accessibilityIdentifier(
                            "button.stage.\(stage.id.description)"
                        )
                    }
                    .onDelete { offsets in
                        deleteStages(at: offsets)
                    }
                    .deleteDisabled(!showsAuthoringControls)
                }
                .listStyle(.plain)
            }
        }
        .searchable(text: $store.searchText, prompt: "Search Stages")
        .autocorrectionDisabled()
        #if os(iOS)
        .textInputAutocapitalization(.never)
        #endif
        .navigationTitle("Stages")
        .toolbar {
            if showsAuthoringControls, store.canCopyStagesFromOtherEvent && !store.stages.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        store.send(.fromOtherEventButtonTapped)
                    } label: {
                        Label("From Other Event", systemImage: "square.on.square")
                            .labelStyle(.iconOnly)
                    }
                }
            }

            if showsAuthoringControls {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        store.send(.addButtonTapped)
                    } label: {
                        Image(systemName: "plus")
                            .accessibilityLabel("Add Event Stage")
                    }
                }
            }
        }
        .navigationDestination(item: $store.scope(\.destination).stageDetail) { detailStore in
            StageDetailView(
                store: detailStore,
                showsAuthoringControls: showsAuthoringControls
            )
        }
        .accessibilityIdentifier(
            "view.stages.\(store.eventID.description)"
        )
    }

    func deleteStages(at offsets: IndexSet) {
        let stageIDs = offsets.compactMap { offset in
            store.filteredStages.indices.contains(offset)
                ? store.filteredStages[offset].id
                : nil
        }
        store.send(.deleteStages(stageIDs))
    }
}

struct EmptyStagesView: View {
    var errorMessage: String?
    var showsAuthoringControls: Bool
    var onAddStage: () -> Void
    var onCopyFromOtherEvent: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            MappedSystemImage(systemName: "square.grid.2x2")
                .frame(width: 52, height: 52)
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("Stages")
                    .font(.title2.weight(.semibold))
                Text("No stages have been added to this event yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if showsAuthoringControls {
                VStack(spacing: 10) {
                    Button {
                        onCopyFromOtherEvent()
                    } label: {
                        Label("From Other Event", systemImage: "square.on.square")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        onAddStage()
                    } label: {
                        Label("Add Stage", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .navigationTitle("Stages")
    }
}

public struct CopyStagesFromEventView: View {
    @Environment(\.dismiss) var dismiss
    @Bindable var store: StoreOf<CopyStagesFromEvent>

    public init(store: StoreOf<CopyStagesFromEvent>) {
        self.store = store
    }

    public var body: some View {
        List {
            if let errorMessage = store.errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section("Event") {
                if store.isLoading && store.sourceEvents.isEmpty {
                    ProgressView()
                } else if store.sourceEvents.isEmpty {
                    ContentUnavailableView(
                        "No Events",
                        systemImage: "calendar.badge.exclamationmark"
                    )
                } else {
                    ForEach(store.sourceEvents) { sourceEvent in
                        Button {
                            store.send(.sourceEventButtonTapped(sourceEvent.id))
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(sourceEvent.name)
                                        .lineLimit(1)
                                    Text(sourceEvent.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                if store.selectedSourceEventID == sourceEvent.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .portableContentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !store.sourceStages.isEmpty {
                Section {
                    ForEach(store.sourceStages) { stage in
                        Button {
                            store.send(.stageButtonTapped(stage.id))
                        } label: {
                            HStack(spacing: 12) {
                                EventPlaceStageArtworkView(place: stage, size: 34)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(stage.name)
                                        .lineLimit(1)

                                    if let category = stage.stageUse?.category {
                                        Text(category.scheduleDivisionTitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()

                                Image(
                                    systemName: store.selectedStageIDs.contains(stage.id)
                                        ? "checkmark.circle.fill"
                                        : "circle"
                                )
                                .foregroundStyle(
                                    store.selectedStageIDs.contains(stage.id)
                                        ? Color.accentColor
                                        : Color.secondary
                                )
                            }
                            .portableContentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        Text("Stages")
                        Spacer()
                        Button(store.selectAllButtonTitle) {
                            store.send(.selectAllStagesButtonTapped)
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .disabled(store.isCopying)
        .navigationTitle("From Other Event")
        .task {
            await store.send(.task)?.value
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                SubmitButton(
                    isInProgress: store.isCopying,
                    isDisabled: !store.canCopy
                ) {
                    store.send(.copyButtonTapped)
                }
            }
        }
    }
}

@Feature
public struct StageDetail {
    public init() {}

    public struct State: Identifiable {
        public let stageID: EventPlace.ID
        public let eventID: Event.ID

        public var destination: Destination.State?
        @FetchOne public var timeZone: TimeZone?
        var eventTimePresentation: EventTimePresentation? {
            timeZone.map { EventTimePresentation(timeZone: $0) }
        }
        public var eventViewerState: EventViewerState
        @FetchOne var persistedEventViewerState: EventViewerState?
        @FetchOne public var stage: EventPlace?
        @FetchAll var contributors: [ContributorProfile]
        @FetchAll public var performanceRows: [PerformanceRow]
        @FetchAll public var schedules: [Schedule]
        @FetchOne public var event: Event?
        @FetchAll public var programs: [Program]

        public init(
            stageID: EventPlace.ID,
            eventID: Event.ID? = nil
        ) {
            @Dependency(EventViewerContext.self) var eventViewer

            self.stageID = stageID
            self.eventID = eventID ?? eventViewer.eventID
            self._timeZone = FetchOne(
                Event.timeZoneQuery(eventID: self.eventID)
            )
            eventViewerState = EventViewerState(id: self.eventID)
            _persistedEventViewerState = FetchOne(
                wrappedValue: nil,
                EventViewerState.none
            )
            _stage = FetchOne(
                StageDetail.stageQuery(
                    stageID: stageID,
                    eventID: self.eventID
                )
            )
            _contributors = FetchAll(
                ContributorsViewer.contributorProfilesQuery(
                    eventID: self.eventID,
                    hydration: .bskyActorProfile
                )
            )
            _performanceRows = FetchAll(PerformanceRow.all(eventID: self.eventID))
            _schedules = FetchAll(ScheduleViewer.schedulesQuery(eventID: self.eventID))
            _event = FetchOne(Event.where { $0.id.eq(self.eventID) })
            _programs = FetchAll(Program.where { $0.event.eq(self.eventID) })
        }

        public var id: EventPlace.ID { stageID }

        var lineupContributors: [ContributorProfile] {
            guard let lineup = stage?.stageUse?.lineup, !lineup.isEmpty else { return [] }
            let contributorsByID = Dictionary(
                uniqueKeysWithValues: contributors.map { ($0.contributorID, $0) }
            )
            return lineup.compactMap { contributorsByID[$0] }
        }

        var actorProfileLoadRequests: [ContributorProfile.ActorProfileLoadRequest] {
            lineupContributors.actorProfileLoadRequests
        }

        var resolvedSelectedScheduleID: Schedule.ID? {
            ScheduleViewer.resolvedSelectedScheduleID(
                eventViewerState.selectedScheduleID,
                schedules: schedules
            )
        }

        var selectedScheduleTitle: String {
            guard let resolvedSelectedScheduleID,
                  let schedule = schedules.first(where: {
                      $0.id == resolvedSelectedScheduleID
                  }),
                  let timeZone
            else { return "Select Schedule" }
            return ScheduleViewer.scheduleTitle(schedule, in: timeZone)
        }

        var selectedSchedulePerformances: [ProgramItem] {
            guard let selectedScheduleID = resolvedSelectedScheduleID else { return [] }
            return performanceRows
                .map(\.performance)
                .filter {
                    $0.schedule == selectedScheduleID
                        && $0.eventPlace == stageID
                }
        }

        var scheduleDivision: ScheduleViewer.ScheduleDivision {
            ScheduleViewer.scheduleDivisions(event: event, programs: programs)
                .first { $0.eventPlaces.contains(stageID) } ?? .schedule
        }
    }

    public enum Action {
        case destination(Destination.Action)
        case editButtonTapped
        case performanceButtonTapped(ProgramItem.ID)
    }

    @Feature
    public enum Destination {
        case performanceDetail(Spawn<PerformanceDetail>)
    }

    @Dependency(\.blueskyActorProfileCache) var blueskyActorProfileCache
    @Dependency(\.defaultDatabase) var database

    static func stageQuery(
        stageID: EventPlace.ID,
        eventID: Event.ID
    ) -> some SelectStatementOf<EventPlace> {
        EventPlace
            .where { $0.event.eq(eventID) }
            .where { $0.id.eq(stageID) }
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .destination:
                break

            case .editButtonTapped:
                let eventID = state.eventID
                let stageID = state.stageID
                store.addTask {
                    let task = try store.post(
                        key: EventEditingRequested.self,
                        value: .editStage(
                            eventID: eventID,
                            stageID: stageID
                        )
                    )
                    await task?.value
                }

            case let .performanceButtonTapped(performanceID):
                guard state.selectedSchedulePerformances.contains(where: {
                    $0.id == performanceID
                }) else { return }
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
            }
        }
        .ifLet(\.destination) {
            Destination.body
        }
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
        .onChange(of: store.persistedEventViewerState) {
            oldPersistedState, persistedState, state in
            guard let persistedState else { return }
            state.eventViewerState.mergePersistedChanges(
                from: oldPersistedState,
                to: persistedState
            )
        }
        .onChange(of: store.eventViewerState) { oldViewerState, viewerState, state in
            guard state.persistedEventViewerState != viewerState else { return }
            do {
                try database.write { db in
                    try EventViewerState.persistChanges(
                        from: oldViewerState,
                        to: viewerState,
                        in: db
                    )
                }
            } catch {
                reportIssue(error)
            }
        }
        .onMount { state in
            let eventID = state.eventID
            let persistedEventViewerState = state.$persistedEventViewerState
            store.addTask {
                try await persistedEventViewerState.load(
                    EventViewerState.where { $0.id.eq(eventID) }
                )
                .task
            }
        }
    }
}

public struct StageDetailView: View {
    @Bindable var store: StoreOf<StageDetail>
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails
    let showsAuthoringControls: Bool

    public init(
        store: StoreOf<StageDetail>,
        showsAuthoringControls: Bool = true
    ) {
        self.store = store
        self.showsAuthoringControls = showsAuthoringControls
    }

    public var body: some View {
        Group {
            if let stage = store.stage {
                let heroImageSources = stage.heroImageSources
                let heroImageTitleSources = stage.heroImageTitleSources
                HeroImageList(
                    title: Text(stage.name),
                    showsNavigationTitleBeforeScroll: heroImageTitleSources.containsLogo
                ) {
                    HeroImage(
                        title: Text(stage.name),
                        sources: heroImageSources,
                        titleSources: heroImageTitleSources,
                        tint: stage.stageUIColor
                    ) {
                        EventPlaceStageIconFallback(place: stage, size: 150)
                    }
                } content: {
                    if !store.schedules.isEmpty {
                        Section("Schedule") {
                            StageScheduleView(
                                stage: stage,
                                store: store,
                                selectedScheduleID: $store.eventViewerState.selectedScheduleID
                            )
                        }
                    }

                    if stage.hasDisplayDetails {
                        Section("Details") {
                            if let category = stage.stageUse?.category {
                                LabeledContent("Category", value: category.scheduleDivisionTitle)
                            }

                            if showsTechnicalDetails, let sortIndex = stage.stageUse?.sortIndex {
                                LabeledContent("Sort Index", value: sortIndex.formatted())
                            }
                        }
                    }

                    if !store.lineupContributors.isEmpty {
                        Section("Lineup") {
                            ForEach(store.lineupContributors) { contributor in
                                ContributorsRowView(profile: contributor)
                            }
                        }
                    }
                }
                .toolbar {
                    if showsAuthoringControls {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                store.send(.editButtonTapped)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                                    .labelStyle(.iconOnly)
                            }
                        }
                    }
                }
                .navigationDestination(item: $store.scope(\.destination).performanceDetail) { detailStore in
                    PerformanceDetailView(
                        store: detailStore,
                        showsAuthoringControls: false
                    )
                }
            } else {
                Group {
                    if showsTechnicalDetails {
                        ContentUnavailableView {
                            Label(
                                "Stage",
                                mappedSystemImage: "square.grid.2x2"
                            )
                        } description: {
                            Text(verbatim: store.stageID.description)
                        }
                    } else {
                        ContentUnavailableView("Stage unavailable", systemImage: "square.grid.2x2")
                    }
                }
                .navigationTitle("Stage")
            }
        }
        .accessibilityIdentifier(
            "view.stage-detail.\(store.stageID.description)"
        )
    }
}

struct StageScheduleView: View {
    let stage: EventPlace
    @Bindable var store: StoreOf<StageDetail>
    @Binding var selectedScheduleID: Schedule.ID?

    @Environment(\.schedulePointsPerHour) var schedulePointsPerHour
    @Environment(\.scheduleTimeBuffer) var scheduleTimeBuffer
    @Environment(\.eventTimePresentation) var eventTimePresentation

    init(
        stage: EventPlace,
        store: StoreOf<StageDetail>,
        selectedScheduleID: Binding<Schedule.ID?>
    ) {
        self.stage = stage
        self.store = store
        self._selectedScheduleID = selectedScheduleID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.schedules.count > 1 {
                if let timeZone = store.timeZone {
                    StageScheduleDaySelector(
                        schedules: store.schedules,
                        timeZone: timeZone,
                        selectedScheduleID: _selectedScheduleID
                    )
                }
            }

            if let timeRange,
               eventTimePresentation != nil {
                ScheduleFixedStageTimeline(
                    stage: stage,
                    performances: store.selectedSchedulePerformances,
                    timeRange: timeRange,
                    pageHeight: scheduleHeight(for: timeRange),
                    userScheduleOverlay: UserScheduleOverlay(
                        schedules: [],
                        memberships: [],
                        selectedScheduleID: nil
                    ),
                    emptyTitle: ScheduleViewer.emptyStageTitle(
                        scheduleDivision: store.state.scheduleDivision,
                        scheduleTitle: store.state.selectedScheduleTitle,
                        stage: stage
                    ),
                    showsAuthoringControls: false,
                    onUserScheduleMembershipTapped: { _, _ in },
                    onNewUserScheduleTapped: { _ in },
                    onEditPerformanceTapped: { _ in },
                    onDeletePerformanceTapped: { _ in },
                    onPerformanceTapped: { performanceID in
                        store.send(.performanceButtonTapped(performanceID))
                    }
                )
            } else {
                ScheduleEmptyView(
                    title: ScheduleViewer.emptyStageTitle(
                        scheduleDivision: store.state.scheduleDivision,
                        scheduleTitle: store.state.selectedScheduleTitle,
                        stage: stage
                    ),
                    otherScheduleDivisions: [],
                    onScheduleDivisionTapped: { _ in }
                )
            }
        }
    }

    var timeRange: DateInterval? {
        ScheduleStageTimelinePage.timeRange(
            for: store.selectedSchedulePerformances,
            buffer: scheduleTimeBuffer
        )
    }

    func scheduleHeight(for timeRange: DateInterval) -> CGFloat {
        max(
            CGFloat(timeRange.duration / 3600) * schedulePointsPerHour,
            420
        )
    }
}

struct StageScheduleDaySelector: View {
    let schedules: [Schedule]
    let timeZone: TimeZone
    @Binding var selectedScheduleID: Schedule.ID?

    init(
        schedules: [Schedule],
        timeZone: TimeZone,
        selectedScheduleID: Binding<Schedule.ID?>
    ) {
        self.schedules = schedules
        self.timeZone = timeZone
        self._selectedScheduleID = selectedScheduleID
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(schedules) { schedule in
                    Button {
                        selectedScheduleID = schedule.id
                    } label: {
                        Text(ScheduleViewer.scheduleTitle(schedule, in: timeZone))
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .foregroundStyle(
                                resolvedSelectedScheduleID == schedule.id
                                    ? Color.white
                                    : Color.primary
                            )
                            .background {
                                Capsule()
                                    .fill(
                                        resolvedSelectedScheduleID == schedule.id
                                            ? stageSelectionColor
                                            : Color.secondary.opacity(0.12)
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear {
            resolveSelectedSchedule()
        }
        .onChange(of: resolvedSelectedScheduleID) { _, _ in
            resolveSelectedSchedule()
        }
    }

    var resolvedSelectedScheduleID: Schedule.ID? {
        ScheduleViewer.resolvedSelectedScheduleID(
            selectedScheduleID,
            schedules: schedules
        )
    }

    var stageSelectionColor: Color {
        .accentColor
    }

    func resolveSelectedSchedule() {
        guard selectedScheduleID != resolvedSelectedScheduleID else { return }
        selectedScheduleID = resolvedSelectedScheduleID
    }
}

@Feature
public struct EditStage {
    public init() {}

    public struct FormValue: Equatable {
        var category = ""
        var color = OME.Color(rawValue: 0x336699)!
        var shortLabel = ""
        var name = ""
        var sortIndex = ""
        var iconName = ""

        init() {}

        init(place: EventPlace) {
            category = place.stageUse?.category ?? ""
            color = place.stageUse?.color ?? Self().color
            shortLabel = place.stageUse?.shortLabel ?? ""
            name = place.name
            sortIndex = place.stageUse?.sortIndex.map(String.init) ?? ""
            iconName = place.stageUse?.icon?.rawValue ?? ""
        }
    }

    public typealias FormFeature = ComposableForms.Form<FormValue>

    public struct State {
        public enum Mode: Equatable, Sendable {
            case create
            case edit(EventPlace.ID)

            var stageID: EventPlace.ID? {
                switch self {
                case .create:
                    return nil
                case let .edit(stageID):
                    return stageID
                }
            }
        }

        public init(eventID: Event.ID) {
            self.eventID = eventID
            self.mode = .create
            self.form = FormFeature.State(value: FormValue())
            self.heroImagePicker = ImageAssetPicker.State(
                configuration: .stageHero, recordImages: nil, recordID: eventID
            )
            self.logoImagePicker = ImageAssetPicker.State(
                configuration: .stageLogo, recordImages: nil, recordID: eventID
            )
            self.posterImagePicker = ImageAssetPicker.State(
                configuration: .stagePoster, recordImages: nil, recordID: eventID
            )
            self.hasLoadedDraft = true
        }

        public init(
            stageID: EventPlace.ID,
            eventID: Event.ID
        ) {
            self.eventID = eventID
            self.mode = .edit(stageID)
            self.form = FormFeature.State(value: FormValue())
            self.heroImagePicker = ImageAssetPicker.State(
                configuration: .stageHero,
                recordImages: nil,
                recordID: eventID
            )
            self.logoImagePicker = ImageAssetPicker.State(
                configuration: .stageLogo,
                recordImages: nil,
                recordID: eventID
            )
            self.posterImagePicker = ImageAssetPicker.State(
                configuration: .stagePoster,
                recordImages: nil,
                recordID: eventID
            )
        }

        public let eventID: Event.ID
        public let mode: Mode

        var errorMessage: String?
        var destination: Destination.State?
        var form: FormFeature.State
        var hasLoadedDraft = false
        var heroImagePicker: ImageAssetPicker.State
        var isSaving = false
        var logoImagePicker: ImageAssetPicker.State
        var originalPlace: EventPlace?
        var originalImages: [OME.Image] = []
        var posterImagePicker: ImageAssetPicker.State

        var category: String {
            get { form.value.category }
            set { form.value.category = newValue }
        }

        var color: OME.Color {
            get { form.value.color }
            set { form.value.color = newValue }
        }

        var colorHex: String {
            get { Self.formatHexColor(color) }
            set {
                guard let color = Self.parseHexColor(
                    newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                ) else { return }
                self.color = color
            }
        }

        var heroImageURL: String {
            get { heroImagePicker.firstURLString }
            set { heroImagePicker.replaceURLString(newValue) }
        }

        var shortLabel: String {
            get { form.value.shortLabel }
            set { form.value.shortLabel = newValue }
        }

        var logoURL: String {
            get { logoImagePicker.firstURLString }
            set { logoImagePicker.replaceURLString(newValue) }
        }

        var sortIndex: String {
            get { form.value.sortIndex }
            set { form.value.sortIndex = newValue }
        }

        var iconName: String {
            get { form.value.iconName }
            set { form.value.iconName = newValue }
        }

        public var stageID: EventPlace.ID? {
            mode.stageID
        }

        var canSubmit: Bool {
            hasLoadedDraft && !isSaving && form.canSubmit
        }

        var navigationTitle: String {
            switch mode {
            case .create:
                return "New Event Stage"
            case .edit:
                return "Edit Event Stage"
            }
        }

        var submitButtonTitle: String {
            switch mode {
            case .create:
                return "Create"
            case .edit:
                return "Save"
            }
        }

        fileprivate struct SaveRequest: Sendable {
            let eventID: Event.ID
            let mode: Mode
            let name: String
            let category: String?
            let color: OME.Color
            let sortIndex: Int?
            let icon: OME.SemanticIcon?
            let shortLabel: String?
            let originalPlace: EventPlace?
            let logoImages: [ImageAssetPicker.ImageValue]
            let heroImages: [ImageAssetPicker.ImageValue]
            let posterImages: [ImageAssetPicker.ImageValue]

            init(state: State) {
                self.eventID = state.eventID
                self.mode = state.mode
                self.name = state.trimmedName
                self.category = state.trimmedCategory.nilIfEmpty
                self.color = state.color
                self.sortIndex = state.parsedSortIndex
                self.icon = state.trimmedIconName.nilIfEmpty.map(OME.SemanticIcon.init(rawValue:))
                self.shortLabel = state.trimmedShortLabel.nilIfEmpty
                self.originalPlace = state.originalPlace
                self.logoImages = state.logoImagePicker.images
                self.heroImages = state.heroImagePicker.images
                self.posterImages = state.posterImagePicker.images
            }

            func fields() throws -> EventPlaceRecordEditing.Fields {
                var fields = originalPlace.map(EventPlaceRecordEditing.Fields.init)
                    ?? EventPlaceRecordEditing.Fields(name: name)
                fields.name = name
                fields.kind = .known(.stage(.init(
                    stage: originalPlace?.stageUse?.stage,
                    color: color,
                    category: category,
                    sortIndex: sortIndex,
                    icon: icon,
                    shortLabel: shortLabel,
                    lineup: originalPlace?.stageUse?.lineup
                )))
                fields.media = try preparedMedia()
                return fields
            }

            private func preparedMedia() throws -> [Open<OME.Media>]? {
                var logos = try logoImages.map { try preparedImage($0, role: .logo) }
                var heroes = try heroImages.map { try preparedImage($0, role: .hero) }
                var posters = try posterImages.map { try preparedImage($0, role: .poster) }
                var media: [Open<OME.Media>] = []

                for existing in originalPlace?.media ?? [] {
                    switch existing {
                    case let .known(.image(image))
                        where image.role == .known(.logo)
                            && image.displayImageAsset(recordID: eventID) != nil:
                        if !logos.isEmpty { media.append(.known(.image(logos.removeFirst()))) }
                    case let .known(.image(image))
                        where image.role == .known(.hero)
                            && image.displayImageAsset(recordID: eventID) != nil:
                        if !heroes.isEmpty { media.append(.known(.image(heroes.removeFirst()))) }
                    case let .known(.image(image))
                        where image.role == .known(.poster)
                            && image.displayImageAsset(recordID: eventID) != nil:
                        if !posters.isEmpty { media.append(.known(.image(posters.removeFirst()))) }
                    default:
                        media.append(existing)
                    }
                }
                media.append(contentsOf: logos.map { .known(.image($0)) })
                media.append(contentsOf: heroes.map { .known(.image($0)) })
                media.append(contentsOf: posters.map { .known(.image($0)) })
                return media.isEmpty ? nil : media
            }

            private func preparedImage(
                _ value: ImageAssetPicker.ImageValue,
                role: OME.Image.Role
            ) throws -> OME.Image {
                var image = value.image
                if let importedImage = value.importedImage {
                    let blob = try stageLocalImageBlob(
                        importedImage.data,
                        mimeType: ATProto.MIMEType(rawValue: importedImage.mimeType)
                    )
                    image.source = .known(.blob(blob))
                }
                image.role = .known(role)
                return image
            }
        }

        var validationMessage: String? {
            guard hasLoadedDraft else { return nil }

            if trimmedName.isEmpty {
                return "Enter a name."
            }

            if !trimmedSortIndex.isEmpty, parsedSortIndex == nil {
                return "Enter a valid sort index."
            }

            return nil
        }

        mutating func resetImagePickers() {
            heroImagePicker = ImageAssetPicker.State(
                configuration: .stageHero,
                recordImages: originalImages,
                recordID: eventID
            )
            logoImagePicker = ImageAssetPicker.State(
                configuration: .stageLogo,
                recordImages: originalImages,
                recordID: eventID
            )
            posterImagePicker = ImageAssetPicker.State(
                configuration: .stagePoster,
                recordImages: originalImages,
                recordID: eventID
            )
        }

        mutating func load(_ place: EventPlace) {
            form = FormFeature.State(value: FormValue(place: place))
            originalPlace = place
            let editableImages = (place.media ?? []).compactMap { medium -> OME.Image? in
                guard case let .known(.image(image)) = medium,
                      image.role == .known(.logo)
                        || image.role == .known(.hero)
                        || image.role == .known(.poster),
                      image.displayImageAsset(recordID: eventID) != nil
                else { return nil }
                return image
            }
            originalImages = editableImages
            resetImagePickers()
            hasLoadedDraft = true
            errorMessage = nil
        }

        private var parsedSortIndex: Int? {
            trimmedSortIndex.isEmpty ? nil : Int(trimmedSortIndex)
        }

        private var trimmedCategory: String {
            category.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private var trimmedShortLabel: String {
            shortLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private var trimmedName: String {
            form.value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private var trimmedSortIndex: String {
            sortIndex.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private var trimmedIconName: String {
            iconName.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        fileprivate static func parseHexColor(_ string: String) -> OME.Color? {
            var value = string

            if value.hasPrefix("#") {
                value.removeFirst()
            } else if value.hasPrefix("0x") || value.hasPrefix("0X") {
                value.removeFirst(2)
            }

            guard value.count == 6,
                  let rawValue = Int(value, radix: 16),
                  (0...0xFFFFFF).contains(rawValue) else {
                return nil
            }

            return OME.Color(rawValue: rawValue)
        }
    }

    public enum Action {
        case cancelButtonTapped
        case destination(Destination.Action)
        case form(FormFeature.Action)
        case formSubmitted(FormValue)
        case heroImagePicker(ImageAssetPicker.Action)
        case logoImagePicker(ImageAssetPicker.Action)
        case posterImagePicker(ImageAssetPicker.Action)
        case saveButtonTapped
    }

    @Feature
    public enum Destination {
        case heroImageInfo(Spawn<ImageInfo>)
        case heroImportImages(Spawn<ImportImages>)
        case logoImageInfo(Spawn<ImageInfo>)
        case logoImportImages(Spawn<ImportImages>)
        case posterImageInfo(Spawn<ImageInfo>)
        case posterImportImages(Spawn<ImportImages>)
    }

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.date.now) var now

    public var body: some Feature {
        Scope(\.form) {
            FormFeature()
                .onSubmit { value in
                    try store.send(.formSubmitted(value))
                }
        }
        Scope(\.heroImagePicker) {
            ImageAssetPicker()
        }
        Scope(\.logoImagePicker) {
            ImageAssetPicker()
        }
        Scope(\.posterImagePicker) {
            ImageAssetPicker()
        }
        Update { state, action in
            switch action {
            case .cancelButtonTapped:
                store.addTask {
                    try store.dismiss()
                }

            case .destination:
                break

            case .form:
                break

            case .formSubmitted:
                guard !state.isSaving else { return }
                guard state.hasLoadedDraft else {
                    state.errorMessage = "This event stage could not be loaded."
                    return
                }

                state.errorMessage = nil
                state.isSaving = true
                let saveRequest = State.SaveRequest(state: state)
                let createdAt = now

                store.addTask {
                    do {
                        let fields = try saveRequest.fields()
                        try await database.write { db in
                            switch saveRequest.mode {
                            case .create:
                                _ = try EventPlaceRecordEditing.create(
                                    eventID: saveRequest.eventID,
                                    fields: fields,
                                    createdAt: createdAt,
                                    in: db
                                )
                            case let .edit(stageID):
                                try EventPlaceRecordEditing.update(
                                    stageID,
                                    eventID: saveRequest.eventID,
                                    fields: fields,
                                    in: db
                                )
                            }
                        }
                        try store.modify {
                            $0.errorMessage = nil
                            $0.isSaving = false
                        }
                        try store.dismiss()
                    } catch {
                        try store.modify {
                            $0.errorMessage = "Unable to save event stage."
                            $0.isSaving = false
                        }
                    }
                }

            case .heroImagePicker(.addButtonTapped):
                state.destination = .heroImportImages(
                    Spawn(state.heroImagePicker.importImagesState())
                )

            case let .heroImagePicker(.imageInfoButtonTapped(id)):
                guard let imageInfoState = state.heroImagePicker.imageInfoState(for: id) else {
                    return
                }
                state.destination = .heroImageInfo(Spawn(imageInfoState))

            case .heroImagePicker:
                break

            case .logoImagePicker(.addButtonTapped):
                state.destination = .logoImportImages(
                    Spawn(state.logoImagePicker.importImagesState())
                )

            case let .logoImagePicker(.imageInfoButtonTapped(id)):
                guard let imageInfoState = state.logoImagePicker.imageInfoState(for: id) else {
                    return
                }
                state.destination = .logoImageInfo(Spawn(imageInfoState))

            case .logoImagePicker:
                break

            case .posterImagePicker(.addButtonTapped):
                state.destination = .posterImportImages(
                    Spawn(state.posterImagePicker.importImagesState())
                )

            case let .posterImagePicker(.imageInfoButtonTapped(id)):
                guard let imageInfoState = state.posterImagePicker.imageInfoState(for: id) else {
                    return
                }
                state.destination = .posterImageInfo(Spawn(imageInfoState))

            case .posterImagePicker:
                break

            case .saveButtonTapped:
                guard !state.isSaving else { return }
                guard state.hasLoadedDraft else {
                    state.errorMessage = "This event stage could not be loaded."
                    return
                }

                store.addTask {
                    try store.send(.form(.submittedForm))
                }
            }
        }
        .ifLet(\.destination) {
            EmptyFeature()
                .ifCaseLet(\.heroImportImages) {
                    ImportImages()
                }
                .ifCaseLet(\.heroImageInfo) {
                    ImageInfo { imageID, image in
                        try store.modify {
                            $0.heroImagePicker.updateImageInfo(
                                imageID: imageID,
                                image: image
                            )
                        }
                    }
                }
                .ifCaseLet(\.logoImportImages) {
                    ImportImages()
                }
                .ifCaseLet(\.logoImageInfo) {
                    ImageInfo { imageID, image in
                        try store.modify {
                            $0.logoImagePicker.updateImageInfo(
                                imageID: imageID,
                                image: image
                            )
                        }
                    }
                }
                .ifCaseLet(\.posterImportImages) {
                    ImportImages()
                }
                .ifCaseLet(\.posterImageInfo) {
                    ImageInfo { imageID, image in
                        try store.modify {
                            $0.posterImagePicker.updateImageInfo(
                                imageID: imageID,
                                image: image
                            )
                        }
                    }
                }
        }
        .onEvent(ImportedImagesSubmitted.self) { images, state in
            switch state.destination {
            case .heroImportImages(_):
                state.heroImagePicker.append(images)
            case .logoImportImages(_):
                state.logoImagePicker.append(images)
            case .posterImportImages(_):
                state.posterImagePicker.append(images)
            case .heroImageInfo(_), .logoImageInfo(_), .posterImageInfo(_), nil:
                break
            }
        }
        .onMount { state in
            guard !state.hasLoadedDraft else { return }
            guard let stageID = state.mode.stageID else {
                state.hasLoadedDraft = true
                state.errorMessage = nil
                return
            }

            do {
                if let stage = try database.read({ db in
                    try StageDetail.stageQuery(
                        stageID: stageID,
                        eventID: state.eventID
                    )
                    .fetchOne(db)
                }) {
                    state.load(stage)
                } else {
                    state.errorMessage = "This event stage could not be loaded."
                }
            } catch {
                state.errorMessage = "This event stage could not be loaded."
            }
        }
    }
}

private enum EditStageFormFieldID {
    static var name: AnyHashable { AnyHashable(\EditStage.FormValue.name) }
    static var sortIndex: AnyHashable { AnyHashable(\EditStage.FormValue.sortIndex) }
}

private extension EditStage.FormFeature {
    init() {
        self.init {
            Self.Field(\.name) {
                Validation(error: "Enter a name.") {
                    !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            }

            Self.Field(\.sortIndex) {
                Validation(error: "Enter a valid sort index.") { value in
                    let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    return value.isEmpty || Int(value) != nil
                }
            }

            Self.Field(\.color)
        }
    }
}

public struct EditStageView: View {
    @Bindable var store: StoreOf<EditStage>
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails
    @FocusState var focusedField: AnyHashable?

    public init(store: StoreOf<EditStage>) {
        self.store = store
    }

    public var body: some View {
        EditStageContent(
            store: store,
            focusedField: $focusedField
        )
        .disabled(store.isSaving)
        .onChange(of: focusedField) { _, focusedField in
            syncStoreFocusedField(focusedField)
        }
        .onChange(of: store.form.focusedField) { _, focusedField in
            syncViewFocusedField(focusedField)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                EditStageCancelButton(store: store)
            }
            ToolbarItem(placement: .confirmationAction) {
                EditStageSaveButton(store: store)
            }
        }
        .navigationTitle(store.navigationTitle)
        .sheet(item: $store.scope(\.destination).logoImportImages) { importStore in
            NavigationStack {
                ImportImagesView(store: importStore)
            }
        }
        .sheet(item: $store.scope(\.destination).logoImageInfo) { imageInfoStore in
            NavigationStack {
                ImageInfoView(store: imageInfoStore)
            }
        }
        .sheet(item: $store.scope(\.destination).heroImportImages) { importStore in
            NavigationStack {
                ImportImagesView(store: importStore)
            }
        }
        .sheet(item: $store.scope(\.destination).heroImageInfo) { imageInfoStore in
            NavigationStack {
                ImageInfoView(store: imageInfoStore)
            }
        }
        .sheet(item: $store.scope(\.destination).posterImportImages) { importStore in
            NavigationStack {
                ImportImagesView(store: importStore)
            }
        }
        .sheet(item: $store.scope(\.destination).posterImageInfo) { imageInfoStore in
            NavigationStack {
                ImageInfoView(store: imageInfoStore)
            }
        }
    }

    private func syncStoreFocusedField(_ focusedField: AnyHashable?) {
        if store.form.focusedField != focusedField {
            $store.form.focusedField.wrappedValue = focusedField
        }
    }

    private func syncViewFocusedField(_ focusedField: AnyHashable?) {
        if self.focusedField != focusedField {
            self.focusedField = focusedField
        }
    }
}

struct EditStageLoadedForm: View {
    @Bindable var store: StoreOf<EditStage>
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails
    let focusedField: FocusState<AnyHashable?>.Binding

    init(
        store: StoreOf<EditStage>,
        focusedField: FocusState<AnyHashable?>.Binding
    ) {
        self.store = store
        self.focusedField = focusedField
    }

    var body: some View {
        SwiftUI.Form {
            eventStageSection
            if showsTechnicalDetails {
                iconSection
            }
            imageSection
            errorSection
        }
    }

    private var eventStageSection: some View {
        Section("Event Stage") {
            nameField

            TextField("Category", text: $store.form.value.category)

            if showsTechnicalDetails {
                sortIndexField
            }
            colorField
        }
    }

    private var iconSection: some View {
        Section("Icon") {
            TextField("Icon", text: $store.form.value.iconName)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
            TextField("Short Code", text: $store.form.value.shortLabel)
                #if os(iOS)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                #endif
        }
    }

    private var imageSection: some View {
        Group {
            ImageAssetPickerSection(
                store: store.scope(\.logoImagePicker)
            )
            ImageAssetPickerSection(
                store: store.scope(\.heroImagePicker)
            )
            ImageAssetPickerSection(
                store: store.scope(\.posterImagePicker)
            )
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let errorMessage = store.errorMessage {
            Section {
                Text(verbatim: errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading) {
            TextField("Name", text: $store.form.value.name)
                .focused(focusedField, equals: EditStageFormFieldID.name)
                .onSubmit {
                    store.send(.form(.fieldSubmitted(EditStageFormFieldID.name)))
                }
            validationStatus(for: EditStageFormFieldID.name)
        }
    }

    private var sortIndexField: some View {
        VStack(alignment: .leading) {
            TextField("Sort Index", text: $store.form.value.sortIndex)
                .focused(focusedField, equals: EditStageFormFieldID.sortIndex)
                .onSubmit {
                    store.send(.form(.fieldSubmitted(EditStageFormFieldID.sortIndex)))
                }
            #if os(iOS)
                .keyboardType(.numbersAndPunctuation)
            #endif
            validationStatus(for: EditStageFormFieldID.sortIndex)
        }
    }

    private var colorField: some View {
        #if os(Android) && SKIP_BRIDGE
        Text("Stage Color")
        #else
        ColorPicker(
            "Stage Color",
            selection: $store.form.value.color.editStageColor,
            supportsOpacity: false
        )
        #endif
    }

    @ViewBuilder
    private func validationStatus(for field: AnyHashable) -> some View {
        FormFieldValidationStatus(validation: store.form.validation[field])
    }
}

struct EditStageContent: View {
    let store: StoreOf<EditStage>
    let focusedField: FocusState<AnyHashable?>.Binding

    var body: some View {
        if store.hasLoadedDraft {
            EditStageLoadedForm(
                store: store,
                focusedField: focusedField
            )
        } else {
            ViewerPlaceholderView(
                title: store.navigationTitle,
                systemImage: "square.grid.2x2",
                description: "This event stage could not be loaded."
            )
        }
    }
}

struct EditStageCancelButton: View {
    let store: StoreOf<EditStage>

    var body: some View {
        Button {
            store.send(.cancelButtonTapped)
        } label: {
            Label("Cancel", systemImage: "xmark")
                .labelStyle(.iconOnly)
        }
    }
}

struct EditStageSaveButton: View {
    let store: StoreOf<EditStage>

    var body: some View {
        SubmitButton(
            isInProgress: store.isSaving,
            isDisabled: !store.canSubmit
        ) {
            store.send(.saveButtonTapped)
        }
    }
}

struct StageRowView: View {
    let stage: OMERecord.Stage

    var body: some View {
        HStack(spacing: 12) {
            StageArtworkView(stage: stage, size: 60)

            VStack(alignment: .leading, spacing: 3) {
                Text(stage.name)
                    .lineLimit(1)

                if let category = stage.category?.displayName {
                    Text(category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .foregroundStyle(.primary)
    }
}

struct StageArtworkView: View {
    let stage: OMERecord.Stage
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(stage.color.swiftUIColor.opacity(0.18))

            ImageAssetAsyncImage(
                asset: stage.images?.imageAsset(role: .logo),
                cacheContext: .init(stageID: stage.id),
                contentMode: .fit
            ) {
                StageIconFallback(stage: stage, size: size)
            }
            .foregroundStyle(stage.color.swiftUIColor)
            .padding(10)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct StageIconFallback: View {
    let stage: OMERecord.Stage
    let size: CGFloat

    var body: some View {
        if let systemIconName = stage.systemIconName {
            Image(systemName: systemIconName)
                .font(.system(size: size * 0.42, weight: .semibold))
        } else if let iconShortCode = stage.iconShortCode {
            Text(iconShortCode)
                .font(.system(size: size * 0.36, weight: .heavy))
                .lineLimit(1)
                #if os(iOS)
                .minimumScaleFactor(0.2)
                #endif
        } else {
            Text(stage.initials)
                .font(.system(size: size * 0.36, weight: .heavy))
                .lineLimit(1)
                #if os(iOS)
                .minimumScaleFactor(0.2)
                #endif
        }
    }
}

private extension EventPlace {
    var hasDisplayDetails: Bool {
        stageUse?.category != nil || stageUse?.sortIndex != nil
    }
}

private extension OMERecord.Stage {
    var initials: String {
        let initials = name
            .split(separator: " ")
            .filter { !$0.localizedCaseInsensitiveContains("the") }
            .compactMap(\.first)
            .prefix(2)
            .map(String.init)
            .joined()
        return initials.isEmpty ? "?" : initials
    }
}

private extension OMERecord.Stage.Category {
    var displayName: String? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value.scheduleDivisionTitle
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var scheduleDivisionTitle: String {
        split { $0 == "-" || $0 == "_" || $0 == " " }
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

private extension EditStage.State {
    static func formatHexColor(_ color: OME.Color) -> String {
        String(format: "#%06X", color.rawValue & 0xFFFFFF)
    }
}

private extension OME.Color {
    var editStageColor: Color {
        get {
            Color(
                red: Double((rawValue >> 16) & 0xFF) / 255.0,
                green: Double((rawValue >> 8) & 0xFF) / 255.0,
                blue: Double(rawValue & 0xFF) / 255.0
            )
        }
        set {
            guard let color = OME.Color(newValue) else { return }
            self = color
        }
    }

    init?(_ color: Color) {
        #if !SKIP && canImport(UIKit)
        let resolvedColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard resolvedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }
        self.init(red: red, green: green, blue: blue)
        #elseif !SKIP && canImport(AppKit)
        guard let resolvedColor = NSColor(color).usingColorSpace(.sRGB) else {
            return nil
        }
        self.init(
            red: resolvedColor.redComponent,
            green: resolvedColor.greenComponent,
            blue: resolvedColor.blueComponent
        )
        #else
        return nil
        #endif
    }

    init?(red: CGFloat, green: CGFloat, blue: CGFloat) {
        self.init(rawValue:
            (Int((red * 255).rounded()) << 16)
                | (Int((green * 255).rounded()) << 8)
                | Int((blue * 255).rounded())
        )
    }
}
