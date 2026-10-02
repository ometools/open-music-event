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
public struct EventPlaceList {
    public init() {}

    public struct State {
        public init(
            eventID: Event.ID,
            destination: Destination.State? = nil
        ) {
            self.eventID = eventID
            self.destination = destination
            _eventPlaces = FetchAll(
                EventPlaceList.stagesQuery(eventID: eventID)
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

        public var places: [EventPlace] {
            eventPlaces.sorted { lhs, rhs in
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

        public var filteredPlaces: [EventPlace] {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return places }

            return places.filter { place in
                place.name.localizedStandardContains(query)
                    || place.stageUse?.category?.localizedStandardContains(query) == true
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
        case stageDetail(Spawn<EventPlaceDetail>)
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
                        value: .createPlace(eventID)
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
                            $0.errorMessage = "Unable to delete event place."
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
        try EventPlaceList
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

public struct EventPlaceListView: View {
    @Bindable var store: StoreOf<EventPlaceList>
    let showsAuthoringControls: Bool

    public init(
        store: StoreOf<EventPlaceList>,
        showsAuthoringControls: Bool = true
    ) {
        self.store = store
        self.showsAuthoringControls = showsAuthoringControls
    }

    public var body: some View {
        Group {
            if store.places.isEmpty {
                EmptyPlacesView(
                    errorMessage: store.errorMessage,
                    showsAuthoringControls: showsAuthoringControls,
                    onAddStage: {
                        store.send(.addButtonTapped)
                    },
                    onCopyFromOtherEvent: {
                        store.send(.fromOtherEventButtonTapped)
                    }
                )
            } else if store.filteredPlaces.isEmpty {
                ViewerPlaceholderView(
                    title: "No Results",
                    systemImage: "square.grid.2x2",
                    description: "No places match your search."
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

                    ForEach(store.filteredPlaces) { place in
                        Button {
                            store.send(.stageButtonTapped(place.id))
                        } label: {
                            if place.stageUse != nil {
                                EventPlaceStageRowView(place: place)
                            } else {
                                HStack {
                                    Text(place.name)
                                    Spacer()
                                    Text(place.kindLabel)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .navigationLinkListRowStyle()
                        .accessibilityIdentifier(
                            "button.\(place.stageUse == nil ? "place" : "stage").\(place.id.description)"
                        )
                    }
                    .onDelete { offsets in
                        deletePlaces(at: offsets)
                    }
                    .deleteDisabled(!showsAuthoringControls)
                }
                .listStyle(.plain)
            }
        }
        .searchable(text: $store.searchText, prompt: "Search Places")
        .autocorrectionDisabled()
        #if os(iOS)
        .textInputAutocapitalization(.never)
        #endif
        .navigationTitle("Places")
        .toolbar {
            if showsAuthoringControls, store.canCopyStagesFromOtherEvent && !store.places.isEmpty {
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
                            .accessibilityLabel("Add Event Place")
                    }
                }
            }
        }
        .navigationDestination(item: $store.scope(\.destination).stageDetail) { detailStore in
            EventPlaceDetailView(
                store: detailStore,
                showsAuthoringControls: showsAuthoringControls
            )
        }
        .accessibilityIdentifier(
            "view.stages.\(store.eventID.description)"
        )
    }

    func deletePlaces(at offsets: IndexSet) {
        let stageIDs = offsets.compactMap { offset in
            store.filteredPlaces.indices.contains(offset)
                ? store.filteredPlaces[offset].id
                : nil
        }
        store.send(.deleteStages(stageIDs))
    }
}

private extension EventPlace {
    var kindLabel: String {
        switch kind {
        case .some(.known(.stage)): "Stage"
        case .some(.known(.entrance)): "Entrance"
        case .some(.known(.camping)): "Camping"
        case .some(.known(.info)): "Information"
        case .some(.unknown), .none: "Place"
        }
    }
}

struct EmptyPlacesView: View {
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
                Text("Places")
                    .font(.title2.weight(.semibold))
                Text("No places have been added to this event yet.")
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
                        Label("Add Place", systemImage: "plus")
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
        .navigationTitle("Places")
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
public struct EventPlaceDetail {
    public init() {}

    public struct State: Identifiable {
        public let stageID: EventPlace.ID
        public let eventID: Event.ID

        public var destination: Destination.State?
        @FetchOne public var timeZone: TimeZone?
        var eventTimePresentation: EventTimePresentation? {
            timeZone.map { EventTimePresentation(timeZone: $0) }
        }
        public var eventViewerState: EventDetailState
        @FetchOne var persistedEventViewerState: EventDetailState?
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
            @Dependency(EventDetailContext.self) var eventViewer

            self.stageID = stageID
            self.eventID = eventID ?? eventViewer.eventID
            self._timeZone = FetchOne(
                Event.timeZoneQuery(eventID: self.eventID)
            )
            eventViewerState = EventDetailState(id: self.eventID)
            _persistedEventViewerState = FetchOne(
                wrappedValue: nil,
                EventDetailState.none
            )
            _stage = FetchOne(
                EventPlaceDetail.stageQuery(
                    stageID: stageID,
                    eventID: self.eventID
                )
            )
            _contributors = FetchAll(
                ContributorList.contributorProfilesQuery(
                    eventID: self.eventID,
                    hydration: .bskyActorProfile
                )
            )
            _performanceRows = FetchAll(PerformanceRow.all(eventID: self.eventID))
            _schedules = FetchAll(ScheduleList.schedulesQuery(eventID: self.eventID))
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
            ScheduleList.resolvedSelectedScheduleID(
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
            return ScheduleList.scheduleTitle(schedule, in: timeZone)
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

        var scheduleDivision: ScheduleList.ScheduleDivision {
            ScheduleList.scheduleDivisions(event: event, programs: programs)
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
        case performanceDetail(Spawn<ProgramItemDetail>)
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
                        value: .editPlace(
                            eventID: eventID,
                            placeID: stageID
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
                            ProgramItemDetail.State(
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
                    try EventDetailState.persistChanges(
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
                    EventDetailState.where { $0.id.eq(eventID) }
                )
                .task
            }
        }
    }
}

public struct EventPlaceDetailView: View {
    @Bindable var store: StoreOf<EventPlaceDetail>
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails
    let showsAuthoringControls: Bool

    public init(
        store: StoreOf<EventPlaceDetail>,
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
                    if stage.stageUse != nil && !store.schedules.isEmpty {
                        Section("Schedule") {
                            StageScheduleView(
                                stage: stage,
                                store: store,
                                selectedScheduleID: $store.eventViewerState.selectedScheduleID
                            )
                        }
                    }

                    if stage.hasDisplayDetails || stage.stageUse == nil {
                        Section("Details") {
                            if stage.stageUse == nil {
                                LabeledContent("Kind", value: stage.kindLabel)
                            }
                            if let description = stage.description {
                                Text(description)
                            }
                            if let category = stage.stageUse?.category {
                                LabeledContent("Category", value: category.scheduleDivisionTitle)
                            }

                            if showsTechnicalDetails, let sortIndex = stage.stageUse?.sortIndex {
                                LabeledContent("Sort Index", value: sortIndex.formatted())
                            }
                        }
                    }

                    StagePlaceLocatorDetails(place: stage)
                    StagePlaceLinkDetails(place: stage)

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
                                    .accessibilityIdentifier("button.edit-place")
                            }
                        }
                    }
                }
                .navigationDestination(item: $store.scope(\.destination).performanceDetail) { detailStore in
                    ProgramItemDetailView(
                        store: detailStore,
                        showsAuthoringControls: false
                    )
                }
            } else {
                Group {
                    if showsTechnicalDetails {
                        ContentUnavailableView {
                            Label(
                                "Place",
                                mappedSystemImage: "square.grid.2x2"
                            )
                        } description: {
                            Text(verbatim: store.stageID.description)
                        }
                    } else {
                        ContentUnavailableView("Place unavailable", systemImage: "square.grid.2x2")
                    }
                }
                .navigationTitle("Place")
            }
        }
        .accessibilityIdentifier(
            "view.stage-detail.\(store.stageID.description)"
        )
    }
}

struct StageScheduleView: View {
    let stage: EventPlace
    @Bindable var store: StoreOf<EventPlaceDetail>
    @Binding var selectedScheduleID: Schedule.ID?

    @Environment(\.schedulePointsPerHour) var schedulePointsPerHour
    @Environment(\.scheduleTimeBuffer) var scheduleTimeBuffer
    @Environment(\.eventTimePresentation) var eventTimePresentation

    init(
        stage: EventPlace,
        store: StoreOf<EventPlaceDetail>,
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
                    emptyTitle: ScheduleList.emptyStageTitle(
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
                    title: ScheduleList.emptyStageTitle(
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
                        Text(ScheduleList.scheduleTitle(schedule, in: timeZone))
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
        ScheduleList.resolvedSelectedScheduleID(
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
public struct EventPlaceForm {
    public init() {}

    public struct FormValue: Equatable {
        enum KindChoice: String, CaseIterable, Sendable {
            case stage, entrance, camping, info, unspecified, unrecognized
        }

        var category = ""
        var color = OME.Color(rawValue: 0x336699)!
        var description = ""
        var links: [EditableLink] = []
        var lineup: [Contributor.ID] = []
        var locators: [EditableLocator] = []
        var persistentStageID: OpenMusicEventLexicon.Stage.ID?
        var shortLabel = ""
        var name = ""
        var kindChoice: KindChoice = .stage
        var sortIndex = ""
        var iconName = ""

        init() {}

        init(place: EventPlace) {
            kindChoice = switch place.kind {
            case .none: .unspecified
            case .some(.unknown): .unrecognized
            case .some(.known(.stage)): .stage
            case .some(.known(.entrance)): .entrance
            case .some(.known(.camping)): .camping
            case .some(.known(.info)): .info
            }
            category = place.stageUse?.category ?? ""
            color = place.stageUse?.color ?? Self().color
            description = place.description ?? ""
            links = (place.links ?? []).map(EditableLink.init)
            lineup = place.stageUse?.lineup ?? []
            locators = (place.locators ?? []).map(EditableLocator.init)
            persistentStageID = place.stageUse?.stage
            shortLabel = place.stageUse?.shortLabel ?? ""
            name = place.name
            sortIndex = place.stageUse?.sortIndex.map(String.init) ?? ""
            iconName = place.stageUse?.icon?.rawValue ?? ""
        }
    }

    public typealias FormFeature = ComposableForms.Form<FormValue>

    public struct State {
        public typealias MediaEntry = RecordMediaEditing.MediaEntry
        public typealias MediaDraft = RecordMediaEditing.MediaDraft

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
            self._contributors = FetchAll(Contributor.where { $0.event.eq(eventID) })
            self._persistentStages = FetchAll(OpenMusicEventLexicon.Stage.all)
            self.hasLoadedDraft = true
        }

        public init(
            stageID: EventPlace.ID,
            eventID: Event.ID
        ) {
            self.eventID = eventID
            self.mode = .edit(stageID)
            self.form = FormFeature.State(value: FormValue())
            self._contributors = FetchAll(Contributor.where { $0.event.eq(eventID) })
            self._persistentStages = FetchAll(OpenMusicEventLexicon.Stage.all)
        }

        public let eventID: Event.ID
        public let mode: Mode

        var errorMessage: String?
        var destination: Destination.State?
        @FetchAll var contributors: [Contributor]
        var editingLinkID: EditableLink.ID?
        var editingLocatorID: EditableLocator.ID?
        var form: FormFeature.State
        var hasLoadedDraft = false
        var isSaving = false
        var mediaEntries: [MediaEntry] = []
        var mediaDraft: MediaDraft?
        var originalPlace: EventPlace?
        @FetchAll var persistentStages: [OpenMusicEventLexicon.Stage]

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

        var shortLabel: String {
            get { form.value.shortLabel }
            set { form.value.shortLabel = newValue }
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
            hasLoadedDraft && !isSaving && form.canSubmit && validationMessage == nil
        }

        var navigationTitle: String {
            switch mode {
            case .create:
                return "New Event Place"
            case .edit:
                return "Edit Event Place"
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
            let description: String?
            let links: [OME.Link]?
            let locators: [Open<Event.Locator>]?
            let lineup: [Contributor.ID]?
            let persistentStageID: OpenMusicEventLexicon.Stage.ID?
            let category: String?
            let color: OME.Color
            let sortIndex: Int?
            let icon: OME.SemanticIcon?
            let shortLabel: String?
            let originalPlace: EventPlace?
            let mediaEntries: [MediaEntry]
            let kindChoice: FormValue.KindChoice

            init(state: State) {
                self.eventID = state.eventID
                self.mode = state.mode
                self.name = state.trimmedName
                self.description = state.form.value.description.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                let links = state.form.value.links.compactMap(\.preparedLink)
                self.links = links.isEmpty ? nil : links
                let locators = state.form.value.locators.compactMap(\.preparedLocator)
                self.locators = locators.isEmpty ? nil : locators
                self.lineup = state.form.value.lineup.isEmpty ? nil : state.form.value.lineup
                self.persistentStageID = state.form.value.persistentStageID
                self.category = state.trimmedCategory.nilIfEmpty
                self.color = state.color
                self.sortIndex = state.parsedSortIndex
                self.icon = state.trimmedIconName.nilIfEmpty.map(OME.SemanticIcon.init(rawValue:))
                self.shortLabel = state.trimmedShortLabel.nilIfEmpty
                self.originalPlace = state.originalPlace
                self.mediaEntries = state.mediaEntries
                self.kindChoice = state.form.value.kindChoice
            }

            func fields() throws -> EventPlaceRecordEditing.Fields {
                var fields = originalPlace.map(EventPlaceRecordEditing.Fields.init)
                    ?? EventPlaceRecordEditing.Fields(name: name)
                fields.name = name
                fields.description = description
                fields.links = links
                fields.locators = locators
                fields.kind = switch kindChoice {
                case .stage:
                    .known(.stage(.init(
                        stage: persistentStageID,
                        color: color,
                        category: category,
                        sortIndex: sortIndex,
                        icon: icon,
                        shortLabel: shortLabel,
                        lineup: lineup
                    )))
                case .entrance: .known(.entrance(.init()))
                case .camping: .known(.camping(.init()))
                case .info: .known(.info(.init()))
                case .unspecified: nil
                case .unrecognized: originalPlace?.kind
                }
                fields.media = try RecordMediaEditing.preparedMedia(mediaEntries)
                return fields
            }
        }

        var validationMessage: String? {
            guard hasLoadedDraft else { return nil }

            if mediaDraft != nil {
                return "Finish editing media."
            }

            if trimmedName.isEmpty {
                return "Enter a name."
            }

            if form.value.kindChoice == .stage,
               !trimmedSortIndex.isEmpty, parsedSortIndex == nil {
                return "Enter a valid sort index."
            }

            if let message = form.value.locators.compactMap(\.validationMessage).first
                ?? form.value.links.compactMap(\.validationMessage).first {
                return message
            }

            return nil
        }

        mutating func load(_ place: EventPlace) {
            form = FormFeature.State(value: FormValue(place: place))
            originalPlace = place
            mediaEntries = (place.media ?? []).map { MediaEntry(value: $0) }
            hasLoadedDraft = true
            errorMessage = nil
        }

        mutating func editMedia(id: UUID) {
            guard let entry = mediaEntries.first(where: { $0.id == id }) else { return }
            switch entry.value {
            case let .known(.external(external)):
                mediaDraft = MediaDraft(entryID: id, external: external)
            case let .known(.record(reference)):
                mediaDraft = MediaDraft(entryID: id, reference: reference)
            default:
                break
            }
        }

        mutating func saveMediaDraft() {
            guard let mediaDraft, let value = mediaDraft.value() else { return }
            if let id = mediaDraft.entryID {
                guard let index = mediaEntries.firstIndex(where: { $0.id == id }) else {
                    self.mediaDraft = nil
                    return
                }
                mediaEntries[index].value = value
            } else {
                mediaEntries.append(MediaEntry(value: value))
            }
            self.mediaDraft = nil
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
        case addExternalMediaButtonTapped
        case addImageButtonTapped
        case addLineupContributorTapped(Contributor.ID)
        case addLinkButtonTapped
        case addLocatorButtonTapped(EditableLocator.Kind)
        case addRecordMediaButtonTapped
        case cancelButtonTapped
        case createPersistentStageTapped
        case destination(Destination.Action)
        case form(FormFeature.Action)
        case formSubmitted(FormValue)
        case editLinkButtonTapped(EditableLink.ID)
        case editLocatorButtonTapped(EditableLocator.ID)
        case editPersistentStageTapped(OpenMusicEventLexicon.Stage.ID)
        case linkPersistentStageTapped(OpenMusicEventLexicon.Stage.ID)
        case mediaDeleteButtonTapped(UUID)
        case mediaDraftAltChanged(String)
        case mediaDraftCancelButtonTapped
        case mediaDraftDescriptionChanged(String)
        case mediaDraftKindChanged(String)
        case mediaDraftRemoveThumbnailButtonTapped
        case mediaDraftSaveButtonTapped
        case mediaDraftThumbnailURLChanged(String)
        case mediaDraftTitleChanged(String)
        case mediaDraftURIChanged(String)
        case mediaEditButtonTapped(UUID)
        case mediaImageInfoButtonTapped(UUID)
        case mediaMoveButtonTapped(UUID, Int)
        case moveLineupContributorTapped(Contributor.ID, Int)
        case moveLinkButtonTapped(EditableLink.ID, Int)
        case moveLocatorButtonTapped(EditableLocator.ID, Int)
        case removeLinkButtonTapped(EditableLink.ID)
        case removeLineupContributorTapped(Contributor.ID)
        case removeLocatorButtonTapped(EditableLocator.ID)
        case saveButtonTapped
        case unlinkPersistentStageTapped
    }

    @Feature
    public enum Destination {
        case imageInfo(Spawn<ImageInfo>)
        case importImages(Spawn<ImportImages>)
        case persistentStageEditor(Spawn<StageForm>)
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
        Update { state, action in
            switch action {
            case .addExternalMediaButtonTapped:
                state.mediaDraft = State.MediaDraft(kind: .external)

            case .addImageButtonTapped:
                state.destination = .importImages(
                    Spawn(ImportImages.State(configuration: .eventPlaceImages))
                )

            case let .addLineupContributorTapped(id):
                guard state.contributors.contains(where: { $0.id == id }),
                      !state.form.value.lineup.contains(id) else { return }
                state.form.value.lineup.append(id)

            case .addLinkButtonTapped:
                let link = EditableLink()
                state.form.value.links.append(link)
                state.editingLinkID = link.id
                state.editingLocatorID = nil

            case let .addLocatorButtonTapped(kind):
                let locator = EditableLocator(kind: kind)
                state.form.value.locators.append(locator)
                state.editingLocatorID = locator.id
                state.editingLinkID = nil

            case .addRecordMediaButtonTapped:
                state.mediaDraft = State.MediaDraft(kind: .record)

            case .cancelButtonTapped:
                store.addTask {
                    try store.dismiss()
                }

            case .createPersistentStageTapped:
                state.destination = .persistentStageEditor(
                    Spawn(StageForm.State(eventID: state.eventID))
                )

            case .destination:
                break

            case let .editLinkButtonTapped(id):
                guard state.form.value.links.contains(where: { $0.id == id }) else { return }
                state.editingLinkID = id
                state.editingLocatorID = nil

            case let .editLocatorButtonTapped(id):
                guard state.form.value.locators.contains(where: { $0.id == id }) else { return }
                state.editingLocatorID = id
                state.editingLinkID = nil

            case let .editPersistentStageTapped(id):
                guard id.authority == state.eventID.authority,
                      state.persistentStages.contains(where: { $0.id == id }) else { return }
                state.destination = .persistentStageEditor(
                    Spawn(StageForm.State(stageID: id, eventID: state.eventID))
                )

            case .form:
                break

            case .formSubmitted:
                guard !state.isSaving else { return }
                guard state.hasLoadedDraft else {
                    state.errorMessage = "This event place could not be loaded."
                    return
                }
                if let validationMessage = state.validationMessage {
                    state.errorMessage = validationMessage
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
                            $0.errorMessage = "Unable to save event place."
                            $0.isSaving = false
                        }
                    }
                }

            case let .linkPersistentStageTapped(id):
                guard state.persistentStages.contains(where: { $0.id == id }) else { return }
                state.form.value.persistentStageID = id

            case let .mediaDeleteButtonTapped(id):
                state.mediaEntries.removeAll { $0.id == id }

            case let .mediaDraftAltChanged(alt):
                state.mediaDraft?.thumbnailAlt = alt

            case .mediaDraftCancelButtonTapped:
                state.mediaDraft = nil

            case let .mediaDraftDescriptionChanged(description):
                state.mediaDraft?.description = description

            case let .mediaDraftKindChanged(kind):
                state.mediaDraft?.mediaKind = kind

            case .mediaDraftRemoveThumbnailButtonTapped:
                state.mediaDraft?.removeThumbnail = true
                state.mediaDraft?.thumbnailURL = ""

            case .mediaDraftSaveButtonTapped:
                state.saveMediaDraft()

            case let .mediaDraftThumbnailURLChanged(url):
                state.mediaDraft?.thumbnailURL = url
                state.mediaDraft?.removeThumbnail = false

            case let .mediaDraftTitleChanged(title):
                state.mediaDraft?.title = title

            case let .mediaDraftURIChanged(uri):
                state.mediaDraft?.uri = uri

            case let .mediaEditButtonTapped(id):
                state.editMedia(id: id)

            case let .mediaImageInfoButtonTapped(id):
                guard let entry = state.mediaEntries.first(where: { $0.id == id }),
                      let imageValue = entry.imageValue
                else { return }
                state.destination = .imageInfo(Spawn(ImageInfo.State(
                    id: id,
                    image: imageValue.image,
                    configuration: .allImages,
                    sourceLabel: imageValue.displaySource,
                    recordID: state.eventID,
                    previewData: entry.importedImage?.data
                )))

            case let .mediaMoveButtonTapped(id, offset):
                guard let index = state.mediaEntries.firstIndex(where: { $0.id == id }),
                      state.mediaEntries.indices.contains(index + offset)
                else { return }
                state.mediaEntries.swapAt(index, index + offset)

            case let .moveLineupContributorTapped(id, offset):
                guard let index = state.form.value.lineup.firstIndex(of: id),
                      state.form.value.lineup.indices.contains(index + offset) else { return }
                state.form.value.lineup.swapAt(index, index + offset)

            case let .moveLinkButtonTapped(id, offset):
                guard let index = state.form.value.links.firstIndex(where: { $0.id == id }),
                      state.form.value.links.indices.contains(index + offset) else { return }
                state.form.value.links.swapAt(index, index + offset)

            case let .moveLocatorButtonTapped(id, offset):
                guard let index = state.form.value.locators.firstIndex(where: { $0.id == id }),
                      state.form.value.locators.indices.contains(index + offset) else { return }
                state.form.value.locators.swapAt(index, index + offset)

            case let .removeLinkButtonTapped(id):
                state.form.value.links.removeAll { $0.id == id }
                if state.editingLinkID == id { state.editingLinkID = nil }

            case let .removeLineupContributorTapped(id):
                state.form.value.lineup.removeAll { $0 == id }

            case let .removeLocatorButtonTapped(id):
                state.form.value.locators.removeAll { $0.id == id }
                if state.editingLocatorID == id { state.editingLocatorID = nil }

            case .saveButtonTapped:
                guard !state.isSaving else { return }
                guard state.hasLoadedDraft else {
                    state.errorMessage = "This event place could not be loaded."
                    return
                }

                store.addTask {
                    try store.send(.form(.submittedForm))
                }

            case .unlinkPersistentStageTapped:
                state.form.value.persistentStageID = nil
            }
        }
        .ifLet(\.destination) {
            EmptyFeature()
                .ifCaseLet(\.importImages) {
                    ImportImages()
                }
                .ifCaseLet(\.imageInfo) {
                    ImageInfo { imageID, image in
                        try store.modify {
                            guard let index = $0.mediaEntries.firstIndex(where: { $0.id == imageID }),
                                  case .known(.image) = $0.mediaEntries[index].value
                            else { return }
                            $0.mediaEntries[index].value = .known(.image(image))
                            $0.mediaEntries[index].importedImage?.image = image
                        }
                    }
                }
                .ifCaseLet(\.persistentStageEditor) {
                    StageForm()
                }
        }
        .onEvent(ImportedImagesSubmitted.self) { images, state in
            guard case .importImages = state.destination else { return }
            state.mediaEntries.append(contentsOf: images.map { State.MediaEntry(importedImage: $0) })
        }
        .onEvent(PersistentStageSaved.self) { id, state in
            state.form.value.persistentStageID = id
        }
        .onEvent(PersistentStageDeleted.self) { id, state in
            if state.form.value.persistentStageID == id {
                state.form.value.persistentStageID = nil
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
                    try EventPlaceDetail.stageQuery(
                        stageID: stageID,
                        eventID: state.eventID
                    )
                    .fetchOne(db)
                }) {
                    state.load(stage)
                } else {
                    state.errorMessage = "This event place could not be loaded."
                }
            } catch {
                state.errorMessage = "This event place could not be loaded."
            }
        }
    }
}

private enum EventPlaceFormFormFieldID {
    static var name: AnyHashable { AnyHashable(\EventPlaceForm.FormValue.name) }
    static var sortIndex: AnyHashable { AnyHashable(\EventPlaceForm.FormValue.sortIndex) }
}

private extension EventPlaceForm.FormFeature {
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

public struct EventPlaceFormView: View {
    @Bindable var store: StoreOf<EventPlaceForm>
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails
    @FocusState var focusedField: AnyHashable?

    public init(store: StoreOf<EventPlaceForm>) {
        self.store = store
    }

    public var body: some View {
        EventPlaceFormContent(
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
                EventPlaceFormCancelButton(store: store)
            }
            ToolbarItem(placement: .confirmationAction) {
                EventPlaceFormSaveButton(store: store)
            }
        }
        .navigationTitle(store.navigationTitle)
        .sheet(item: $store.scope(\.destination).importImages) { importStore in
            NavigationStack {
                ImportImagesView(store: importStore)
            }
        }
        .sheet(item: $store.scope(\.destination).imageInfo) { imageInfoStore in
            NavigationStack {
                ImageInfoView(store: imageInfoStore)
            }
        }
        .sheet(item: $store.scope(\.destination).persistentStageEditor) { profileStore in
            NavigationStack {
                StageFormView(store: profileStore)
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

struct EventPlaceFormLoadedForm: View {
    @Bindable var store: StoreOf<EventPlaceForm>
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails
    let focusedField: FocusState<AnyHashable?>.Binding

    init(
        store: StoreOf<EventPlaceForm>,
        focusedField: FocusState<AnyHashable?>.Binding
    ) {
        self.store = store
        self.focusedField = focusedField
    }

    var body: some View {
        SwiftUI.Form {
            eventPlaceSection
            StagePlaceLocatorEditor(store: store)
            StagePlaceLinkEditor(store: store)
            if store.form.value.kindChoice == .stage {
                StagePlaceLineupEditor(store: store)
                StagePlaceIdentityEditor(store: store)
            }
            if showsTechnicalDetails && store.form.value.kindChoice == .stage {
                iconSection
            }
            mediaSection
            errorSection
        }
    }

    private var eventPlaceSection: some View {
        Section("Event Place") {
            nameField

            Picker("Kind", selection: $store.form.value.kindChoice) {
                Text("Stage").tag(EventPlaceForm.FormValue.KindChoice.stage)
                Text("Entrance").tag(EventPlaceForm.FormValue.KindChoice.entrance)
                Text("Camping").tag(EventPlaceForm.FormValue.KindChoice.camping)
                Text("Information").tag(EventPlaceForm.FormValue.KindChoice.info)
                Text("Unspecified").tag(EventPlaceForm.FormValue.KindChoice.unspecified)
                if store.form.value.kindChoice == .unrecognized {
                    Text("Unrecognized kind").tag(EventPlaceForm.FormValue.KindChoice.unrecognized)
                }
            }

            PortableTextField(
                "Description",
                text: $store.form.value.description,
                axis: .vertical
            )
            .portableLineLimit(2...6)

            if store.form.value.kindChoice == .stage {
                TextField("Category", text: $store.form.value.category)

                if showsTechnicalDetails {
                    sortIndexField
                }
                colorField
            }
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

    var mediaSection: some View {
        Section("Media") {
            ForEach(store.mediaEntries) { entry in
                let index = store.mediaEntries.firstIndex(where: { $0.id == entry.id })
                if let image = entry.imageValue {
                    ImageAssetPickerRowView(
                        recordID: store.eventID,
                        image: image,
                        canMoveUp: index.map { $0 > 0 } ?? false,
                        canMoveDown: index.map { $0 + 1 < store.mediaEntries.count } ?? false
                    ) {
                        store.send(.mediaImageInfoButtonTapped(entry.id))
                    } onRemove: {
                        store.send(.mediaDeleteButtonTapped(entry.id))
                    } onMoveUp: {
                        store.send(.mediaMoveButtonTapped(entry.id, -1))
                    } onMoveDown: {
                        store.send(.mediaMoveButtonTapped(entry.id, 1))
                    }
                } else {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title)
                            if let subtitle = entry.subtitle {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Menu {
                            if entry.canEditLink {
                                Button("Edit") { store.send(.mediaEditButtonTapped(entry.id)) }
                            }
                            if index.map({ $0 > 0 }) == true {
                                Button("Move Up") { store.send(.mediaMoveButtonTapped(entry.id, -1)) }
                            }
                            if index.map({ $0 + 1 < store.mediaEntries.count }) == true {
                                Button("Move Down") { store.send(.mediaMoveButtonTapped(entry.id, 1)) }
                            }
                            Button("Delete", role: .destructive) {
                                store.send(.mediaDeleteButtonTapped(entry.id))
                            }
                        } label: {
                            Label("Media Actions", systemImage: "ellipsis.circle")
                                .labelStyle(.iconOnly)
                        }
                    }
                }
            }

            if store.mediaDraft == nil {
                Menu {
                    Button("Image") { store.send(.addImageButtonTapped) }
                    Button("External Link") { store.send(.addExternalMediaButtonTapped) }
                    Button("AT Protocol Record") { store.send(.addRecordMediaButtonTapped) }
                } label: {
                    Label("Add Media", systemImage: "plus")
                }
            }

            if let draft = store.mediaDraft {
                Text(draft.kind == .external ? "External Media" : "AT Protocol Record")
                    .font(.headline)
                TextField("URL", text: mediaDraftURIBinding)
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                if draft.kind == .external {
                    TextField("Title", text: mediaDraftTitleBinding)
                    PortableTextField(
                        "Description",
                        text: mediaDraftDescriptionBinding,
                        axis: .vertical
                    )
                    .portableLineLimit(2...5)
                    TextField("Media Kind", text: mediaDraftKindBinding)
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                    TextField("Thumbnail URL", text: mediaDraftThumbnailURLBinding)
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                    if draft.thumbnail != nil || !draft.thumbnailURL.isEmpty {
                        TextField("Thumbnail Alt Text", text: mediaDraftAltBinding)
                        Button("Remove Thumbnail", role: .destructive) {
                            store.send(.mediaDraftRemoveThumbnailButtonTapped)
                        }
                    }
                }
                if let validationMessage = draft.validationMessage {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                HStack {
                    Button("Cancel") { store.send(.mediaDraftCancelButtonTapped) }
                    Spacer()
                    Button("Done") { store.send(.mediaDraftSaveButtonTapped) }
                        .disabled(draft.validationMessage != nil)
                }
            }
        }
    }

    var mediaDraftURIBinding: Binding<String> {
        Binding(
            get: { store.mediaDraft?.uri ?? "" },
            set: { store.send(.mediaDraftURIChanged($0)) }
        )
    }

    var mediaDraftTitleBinding: Binding<String> {
        Binding(
            get: { store.mediaDraft?.title ?? "" },
            set: { store.send(.mediaDraftTitleChanged($0)) }
        )
    }

    var mediaDraftDescriptionBinding: Binding<String> {
        Binding(
            get: { store.mediaDraft?.description ?? "" },
            set: { store.send(.mediaDraftDescriptionChanged($0)) }
        )
    }

    var mediaDraftKindBinding: Binding<String> {
        Binding(
            get: { store.mediaDraft?.mediaKind ?? "" },
            set: { store.send(.mediaDraftKindChanged($0)) }
        )
    }

    var mediaDraftThumbnailURLBinding: Binding<String> {
        Binding(
            get: { store.mediaDraft?.thumbnailURL ?? "" },
            set: { store.send(.mediaDraftThumbnailURLChanged($0)) }
        )
    }

    var mediaDraftAltBinding: Binding<String> {
        Binding(
            get: { store.mediaDraft?.thumbnailAlt ?? "" },
            set: { store.send(.mediaDraftAltChanged($0)) }
        )
    }
    @ViewBuilder
    private var errorSection: some View {
        if let validationMessage = store.validationMessage {
            Section {
                Text(verbatim: validationMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
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
                .focused(focusedField, equals: EventPlaceFormFormFieldID.name)
                .onSubmit {
                    store.send(.form(.fieldSubmitted(EventPlaceFormFormFieldID.name)))
                }
            validationStatus(for: EventPlaceFormFormFieldID.name)
        }
    }

    private var sortIndexField: some View {
        VStack(alignment: .leading) {
            TextField("Sort Index", text: $store.form.value.sortIndex)
                .focused(focusedField, equals: EventPlaceFormFormFieldID.sortIndex)
                .onSubmit {
                    store.send(.form(.fieldSubmitted(EventPlaceFormFormFieldID.sortIndex)))
                }
            #if os(iOS)
                .keyboardType(.numbersAndPunctuation)
            #endif
            validationStatus(for: EventPlaceFormFormFieldID.sortIndex)
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

struct EventPlaceFormContent: View {
    let store: StoreOf<EventPlaceForm>
    let focusedField: FocusState<AnyHashable?>.Binding

    var body: some View {
        if store.hasLoadedDraft {
            EventPlaceFormLoadedForm(
                store: store,
                focusedField: focusedField
            )
        } else {
            ViewerPlaceholderView(
                title: store.navigationTitle,
                systemImage: "square.grid.2x2",
                description: "This event place could not be loaded."
            )
        }
    }
}

struct EventPlaceFormCancelButton: View {
    let store: StoreOf<EventPlaceForm>

    var body: some View {
        Button {
            store.send(.cancelButtonTapped)
        } label: {
            Label("Cancel", systemImage: "xmark")
                .labelStyle(.iconOnly)
        }
    }
}

struct EventPlaceFormSaveButton: View {
    let store: StoreOf<EventPlaceForm>

    var body: some View {
        SubmitButton(
            isInProgress: store.isSaving,
            isDisabled: !store.canSubmit
        ) {
            store.send(.saveButtonTapped)
        }
    }
}

private extension EventPlace {
    var hasDisplayDetails: Bool {
        description != nil || stageUse?.category != nil || stageUse?.sortIndex != nil
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

private extension EventPlaceForm.State {
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
