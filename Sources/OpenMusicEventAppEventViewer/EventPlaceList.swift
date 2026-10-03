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
                                        Text(eventPlaceDivisionTitle(category))
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

