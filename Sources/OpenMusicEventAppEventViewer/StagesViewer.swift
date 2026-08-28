import HeroImageList
import BlueskyActorCache
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
            eventID: OMERecord.Event.ID,
            destination: Destination.State? = nil
        ) {
            self.eventID = eventID
            self.destination = destination
            _stages = FetchAll(
                StagesViewer.stagesQuery(eventID: eventID)
            )
        }

        public let eventID: OMERecord.Event.ID
        public var destination: Destination.State?
        public var errorMessage: String?
        public var searchText = ""

        @FetchAll public var stages: [OMERecord.Stage]

        public var canCopyStagesFromOtherEvent: Bool {
            stages.isEmpty || StagesViewer.hasOnlyReplaceableSingletonStage(stages)
        }

        public var filteredStages: [OMERecord.Stage] {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return stages }

            return stages.filter { stage in
                stage.name.localizedStandardContains(query)
                    || stage.category?.rawValue.localizedStandardContains(query) == true
            }
        }
    }

    public enum Action {
        case addButtonTapped
        case deleteStages([OMERecord.ID<OMERecord.Stage>])
        case destination(Destination.Action)
        case fromOtherEventButtonTapped
        case stageButtonTapped(OMERecord.ID<OMERecord.Stage>)
    }

    @Feature
    public enum Destination {
        case stageDetail(Spawn<StageDetail>)
    }

    @Dependency(\.defaultDatabase) var database

    static func stagesQuery(
        eventID: OMERecord.Event.ID
    ) -> some SelectStatementOf<OMERecord.Stage> {
        OMERecord.Stage
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .order { ($0.sortIndex.asc(nulls: .last), $0.name.collate(.nocase)) }
    }

    static func hasOnlyReplaceableSingletonStage(_ stages: [OMERecord.Stage]) -> Bool {
        guard stages.count == 1, let stage = stages.first else { return false }
        return stage.id.stageID == OMERecord.Stage.singletonID
            && stage.name == OMERecord.Stage.singletonName
            && stage.color == OMERecord.Stage.singletonColor
            && stage.category == nil
            && stage.sortIndex == nil
            && stage.images == nil
            && stage.systemIconName == nil
            && stage.iconShortCode == nil
            && stage.lineup == nil
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
                                try OMERecord.Stage
                                    .where { $0.id.organizerID.eq(eventID.organizerID) }
                                    .where { $0.id.eventID.eq(eventID.eventID) }
                                    .where { $0.id.stageID.eq(stageID) }
                                    .delete()
                                    .execute(db)
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
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
    }

    static func duplicateStageDraft(
        _ stage: OMERecord.Stage,
        to eventID: OMERecord.Event.ID
    ) -> OMERecord.Stage.Draft {
        OMERecord.Stage.Draft(
            id: OMERecord.Stage.ID(
                organizerID: eventID.organizerID,
                eventID: eventID.eventID,
                stageID: stage.id.stageID
            ),
            name: stage.name,
            color: stage.color,
            category: stage.category,
            sortIndex: stage.sortIndex,
            images: duplicateStageImages(stage.images),
            systemIconName: stage.systemIconName,
            iconShortCode: stage.iconShortCode,
            lineup: nil
        )
    }

    private static func duplicateStageImages(
        _ images: [OMERecord.ImageAsset]?
    ) -> [OMERecord.ImageAsset]? {
        let images = images?.compactMap { image -> OMERecord.ImageAsset? in
            if case let .url(url) = image.source, url.isFileURL {
                return nil
            }

            var image = image
            image.assetKey = nil
            return image
        }
        return images?.isEmpty == false ? images : nil
    }
}

@Feature
public struct CopyStagesFromEvent {
    public init() {}

    public struct SourceEventOption: Equatable, Identifiable, Sendable {
        public var endDate: LocalDate?
        public var id: OMERecord.Event.ID
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
        public init(eventID: OMERecord.Event.ID) {
            self.eventID = eventID
        }

        public let eventID: OMERecord.Event.ID
        public var errorMessage: String?
        public var isCopying = false
        public var isLoading = false
        public var selectedSourceEventID: OMERecord.Event.ID?
        public var selectedStageIDs: Set<OMERecord.ID<OMERecord.Stage>> = []
        public var sourceEvents: [SourceEventOption] = []
        public var sourceStages: [OMERecord.Stage] = []

        var canCopy: Bool {
            !isCopying
                && !isLoading
                && selectedSourceEventID != nil
                && !selectedStageIDs.isEmpty
        }

        var isEveryStageSelected: Bool {
            !sourceStages.isEmpty
                && selectedStageIDs == Set(sourceStages.map(\.id.stageID))
        }

        var selectAllButtonTitle: String {
            isEveryStageSelected ? "Clear" : "Select All"
        }
    }

    public enum Action {
        case copyButtonTapped
        case selectAllStagesButtonTapped
        case sourceEventButtonTapped(OMERecord.Event.ID)
        case stageButtonTapped(OMERecord.ID<OMERecord.Stage>)
        case task
    }

    @Dependency(\.defaultDatabase) var database

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
                state.errorMessage = nil
                state.isCopying = true
                store.addTask {
                    do {
                        _ = try database.write { db in
                            try Self.copyStages(
                                from: selectedSourceEventID,
                                stageIDs: selectedStageIDs,
                                to: destinationEventID,
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
                    state.selectedStageIDs = Set(state.sourceStages.map(\.id.stageID))
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
                            $0.selectedStageIDs = Set(sourceStages.map(\.id.stageID))
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
                guard state.sourceStages.contains(where: { $0.id.stageID == stageID }) else {
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
                            $0.selectedStageIDs = Set(sourceStages.map(\.id.stageID))
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
        case selectedStagesAlreadyExist
        case selectedStagesNotFound

        var message: String {
            switch self {
            case .selectedStagesAlreadyExist:
                "One or more selected stages already exist in this event."
            case .selectedStagesNotFound:
                "Choose at least one stage."
            }
        }
    }

    static func copyStages(
        from sourceEventID: OMERecord.Event.ID,
        stageIDs: Set<OMERecord.ID<OMERecord.Stage>>,
        to destinationEventID: OMERecord.Event.ID,
        in db: Database
    ) throws -> Int {
        let sourceStages = try sourceStages(eventID: sourceEventID, in: db)
            .filter { stageIDs.contains($0.id.stageID) }
        guard !sourceStages.isEmpty else {
            throw CopyStagesFromEventError.selectedStagesNotFound
        }

        let destinationStages = try StagesViewer
            .stagesQuery(eventID: destinationEventID)
            .fetchAll(db)
        let destinationStageIDs = Set(destinationStages.map(\.id.stageID))
        let isReplacingSingletonStage = StagesViewer
            .hasOnlyReplaceableSingletonStage(destinationStages)

        if !isReplacingSingletonStage {
            guard !sourceStages.contains(where: { destinationStageIDs.contains($0.id.stageID) }) else {
                throw CopyStagesFromEventError.selectedStagesAlreadyExist
            }
        }

        if isReplacingSingletonStage {
            try deleteSingletonStage(eventID: destinationEventID, in: db)
        }

        try OMERecord.Stage.insert {
            sourceStages.map { stage in
                StagesViewer.duplicateStageDraft(stage, to: destinationEventID)
            }
        }
        .execute(db)

        return sourceStages.count
    }

    static func deleteSingletonStage(
        eventID: OMERecord.Event.ID,
        in db: Database
    ) throws {
        try OMERecord.Stage
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .where { $0.id.stageID.eq(OMERecord.Stage.singletonID) }
            .delete()
            .execute(db)
    }

    static func sourceEventOptions(
        for eventID: OMERecord.Event.ID,
        in db: Database
    ) throws -> [SourceEventOption] {
        let events = try OMERecord.Event
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .fetchAll(db)
        let stages = try OMERecord.Stage
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .fetchAll(db)
        let stageCounts = Dictionary(
            grouping: stages,
            by: \.id.eventID
        )
        .mapValues(\.count)

        return events
            .filter { $0.id != eventID }
            .compactMap { event -> SourceEventOption? in
                let stageCount = stageCounts[event.id.eventID] ?? 0
                guard stageCount > 0 else { return nil }
                return SourceEventOption(
                    endDate: event.endDate,
                    id: event.id,
                    name: event.name,
                    stageCount: stageCount,
                    startDate: event.startDate
                )
            }
            .sorted(by: SourceEventOption.sort)
    }

    static func sourceStages(
        eventID: OMERecord.Event.ID,
        in db: Database
    ) throws -> [OMERecord.Stage] {
        try StagesViewer
            .stagesQuery(eventID: eventID)
            .fetchAll(db)
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
                            store.send(.stageButtonTapped(stage.id.stageID))
                        } label: {
                            StageRowView(stage: stage)
                        }
                        .navigationLinkListRowStyle()
                        .accessibilityIdentifier(
                            "button.stage.\(stage.id.stageID.rawValue.rawValue)"
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
        .navigationDestination(item: $store.scope(\.destination, action: \.destination).stageDetail) { detailStore in
            StageDetailView(
                store: detailStore,
                showsAuthoringControls: showsAuthoringControls
            )
        }
        .accessibilityIdentifier(
            "view.stages.\(store.eventID.eventID.rawValue.rawValue)"
        )
    }

    func deleteStages(at offsets: IndexSet) {
        let stageIDs = offsets.compactMap { offset in
            store.filteredStages.indices.contains(offset)
                ? store.filteredStages[offset].id.stageID
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
                            store.send(.stageButtonTapped(stage.id.stageID))
                        } label: {
                            HStack(spacing: 12) {
                                StageArtworkView(stage: stage, size: 34)

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

                                Image(
                                    systemName: store.selectedStageIDs.contains(stage.id.stageID)
                                        ? "checkmark.circle.fill"
                                        : "circle"
                                )
                                .foregroundStyle(
                                    store.selectedStageIDs.contains(stage.id.stageID)
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
        public let stageID: OMERecord.ID<OMERecord.Stage>
        public let eventID: OMERecord.Event.ID

        public var destination: Destination.State?
        @FetchOne public var timeZone: TimeZone?
        var eventTimePresentation: EventTimePresentation? {
            timeZone.map { EventTimePresentation(timeZone: $0) }
        }
        public var eventViewerState: EventViewerState
        @FetchOne var persistedEventViewerState: EventViewerState?
        @FetchOne public var stage: OMERecord.Stage?
        @FetchAll var contributors: [ContributorProfile]
        @FetchAll public var performanceRows: [PerformanceRow]
        @FetchAll public var schedules: [OMERecord.Schedule]

        public init(
            stageID: OMERecord.ID<OMERecord.Stage>,
            eventID: OMERecord.Event.ID? = nil
        ) {
            @Dependency(EventViewerContext.self) var eventViewer

            self.stageID = stageID
            self.eventID = eventID ?? eventViewer.eventID
            self._timeZone = FetchOne(
                OMERecord.Event.timeZoneQuery(eventID: self.eventID)
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
        }

        public var id: OMERecord.ID<OMERecord.Stage> { stageID }

        var lineupContributors: [ContributorProfile] {
            guard let lineup = stage?.lineup, !lineup.isEmpty else { return [] }
            let contributorsByID = Dictionary(
                uniqueKeysWithValues: contributors.map { ($0.contributorID, $0) }
            )
            return lineup.compactMap { contributorsByID[$0] }
        }

        var actorProfileLoadRequests: [ContributorProfile.ActorProfileLoadRequest] {
            lineupContributors.actorProfileLoadRequests
        }

        var resolvedSelectedScheduleID: OMERecord.ID<OMERecord.Schedule>? {
            ScheduleViewer.resolvedSelectedScheduleID(
                eventViewerState.selectedScheduleID,
                schedules: schedules
            )
        }

        var selectedScheduleTitle: String {
            guard let resolvedSelectedScheduleID,
                  let schedule = schedules.first(where: {
                      $0.id.scheduleID == resolvedSelectedScheduleID
                  }),
                  let timeZone
            else { return "Select Schedule" }
            return ScheduleViewer.scheduleTitle(schedule, in: timeZone)
        }

        var selectedSchedulePerformances: [OMERecord.Performance] {
            guard let selectedScheduleID = resolvedSelectedScheduleID else { return [] }
            return performanceRows
                .map(\.performance)
                .filter {
                    $0.scheduleID == selectedScheduleID
                        && $0.stageID == stageID
                }
        }
    }

    public enum Action {
        case destination(Destination.Action)
        case editButtonTapped
        case performanceButtonTapped(OMERecord.ID<OMERecord.Performance>)
    }

    @Feature
    public enum Destination {
        case performanceDetail(Spawn<PerformanceDetail>)
    }

    @Dependency(\.blueskyActorProfileCache) var blueskyActorProfileCache
    @Dependency(\.defaultDatabase) var database

    static func stageQuery(
        stageID: OMERecord.ID<OMERecord.Stage>,
        eventID: OMERecord.Event.ID
    ) -> some SelectStatementOf<OMERecord.Stage> {
        OMERecord.Stage
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .where { $0.id.stageID.eq(stageID) }
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
                    $0.id.performanceID == performanceID
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
        .ifLet(\.destination, action: \.destination) {
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
                        tint: stage.color.swiftUIColor
                    ) {
                        StageIconFallback(stage: stage, size: 150)
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
                            if let category = stage.category?.displayName {
                                LabeledContent("Category", value: category)
                            }

                            if showsTechnicalDetails, let sortIndex = stage.sortIndex {
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
                .navigationDestination(item: $store.scope(\.destination, action: \.destination).performanceDetail) { detailStore in
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
                            Text(verbatim: store.stageID.rawValue.rawValue)
                        }
                    } else {
                        ContentUnavailableView("Stage unavailable", systemImage: "square.grid.2x2")
                    }
                }
                .navigationTitle("Stage")
            }
        }
        .accessibilityIdentifier(
            "view.stage-detail.\(store.stageID.rawValue.rawValue)"
        )
    }
}

struct StageScheduleView: View {
    let stage: OMERecord.Stage
    @Bindable var store: StoreOf<StageDetail>
    @Binding var selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?

    @Environment(\.schedulePointsPerHour) var schedulePointsPerHour
    @Environment(\.scheduleTimeBuffer) var scheduleTimeBuffer
    @Environment(\.eventTimePresentation) var eventTimePresentation

    init(
        stage: OMERecord.Stage,
        store: StoreOf<StageDetail>,
        selectedScheduleID: Binding<OMERecord.ID<OMERecord.Schedule>?>
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
                        scheduleDivision: ScheduleViewer.ScheduleDivision(category: stage.category),
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
                        scheduleDivision: ScheduleViewer.ScheduleDivision(category: stage.category),
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
    let schedules: [OMERecord.Schedule]
    let timeZone: TimeZone
    @Binding var selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?

    init(
        schedules: [OMERecord.Schedule],
        timeZone: TimeZone,
        selectedScheduleID: Binding<OMERecord.ID<OMERecord.Schedule>?>
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
                        selectedScheduleID = schedule.id.scheduleID
                    } label: {
                        Text(ScheduleViewer.scheduleTitle(schedule, in: timeZone))
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .foregroundStyle(
                                resolvedSelectedScheduleID == schedule.id.scheduleID
                                    ? Color.white
                                    : Color.primary
                            )
                            .background {
                                Capsule()
                                    .fill(
                                        resolvedSelectedScheduleID == schedule.id.scheduleID
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

    var resolvedSelectedScheduleID: OMERecord.ID<OMERecord.Schedule>? {
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
        var color: OMEColor = 0x336699
        var iconShortCode = ""
        var name = ""
        var sortIndex = ""
        var systemIconName = ""

        init() {}

        init(draft: OMERecord.Stage.Draft) {
            category = draft.category?.rawValue ?? ""
            color = draft.color
            iconShortCode = draft.iconShortCode ?? ""
            name = draft.name
            sortIndex = draft.sortIndex.map(String.init) ?? ""
            systemIconName = draft.systemIconName ?? ""
        }
    }

    public typealias FormFeature = ComposableForms.Form<FormValue>

    public struct State {
        public enum Mode: Equatable {
            case create
            case edit(OMERecord.ID<OMERecord.Stage>)

            var stageID: OMERecord.ID<OMERecord.Stage>? {
                switch self {
                case .create:
                    return nil
                case let .edit(stageID):
                    return stageID
                }
            }
        }

        public init(eventID: OMERecord.Event.ID) {
            self.eventID = eventID
            self.mode = .create
            let draft = Self.emptyDraft(stageID: nil, eventID: eventID)
            self.draft = draft
            self.form = FormFeature.State(value: FormValue(draft: draft))
            self.heroImagePicker = ImageAssetPicker.State(configuration: .stageHero, assets: draft.images)
            self.logoImagePicker = ImageAssetPicker.State(configuration: .stageLogo, assets: draft.images)
            self.posterImagePicker = ImageAssetPicker.State(configuration: .stagePoster, assets: draft.images)
            self.hasLoadedDraft = true
        }

        public init(
            stageID: OMERecord.ID<OMERecord.Stage>,
            eventID: OMERecord.Event.ID
        ) {
            self.eventID = eventID
            self.mode = .edit(stageID)
            let draft = Self.emptyDraft(stageID: stageID, eventID: eventID)
            self.draft = draft
            self.form = FormFeature.State(value: FormValue(draft: draft))
            let cacheContext = LocalImageCacheContext(
                stageID: OMERecord.Stage.ID(
                    organizerID: eventID.organizerID,
                    eventID: eventID.eventID,
                    stageID: stageID
                )
            )
            self.heroImagePicker = ImageAssetPicker.State(
                configuration: .stageHero,
                assets: draft.images,
                cacheContext: cacheContext
            )
            self.logoImagePicker = ImageAssetPicker.State(
                configuration: .stageLogo,
                assets: draft.images,
                cacheContext: cacheContext
            )
            self.posterImagePicker = ImageAssetPicker.State(
                configuration: .stagePoster,
                assets: draft.images,
                cacheContext: cacheContext
            )
        }

        public let eventID: OMERecord.Event.ID
        public let mode: Mode

        var draft: OMERecord.Stage.Draft {
            didSet {
                form.value = FormValue(draft: draft)
                resetImagePickers()
            }
        }
        var errorMessage: String?
        var destination: Destination.State?
        var form: FormFeature.State
        var hasLoadedDraft = false
        var heroImagePicker: ImageAssetPicker.State
        var isSaving = false
        var logoImagePicker: ImageAssetPicker.State
        var posterImagePicker: ImageAssetPicker.State

        var category: String {
            get { form.value.category }
            set { form.value.category = newValue }
        }

        var color: OMEColor {
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

        var iconShortCode: String {
            get { form.value.iconShortCode }
            set { form.value.iconShortCode = newValue }
        }

        var logoURL: String {
            get { logoImagePicker.firstURLString }
            set { logoImagePicker.replaceURLString(newValue) }
        }

        var sortIndex: String {
            get { form.value.sortIndex }
            set { form.value.sortIndex = newValue }
        }

        var systemIconName: String {
            get { form.value.systemIconName }
            set { form.value.systemIconName = newValue }
        }

        public var stageID: OMERecord.ID<OMERecord.Stage>? {
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

        func preparedDraft(
            stageID: OMERecord.ID<OMERecord.Stage>
        ) throws -> (draft: OMERecord.Stage.Draft, blobs: [LocalImageBlob]) {
            var draft = draft
            let stageRecordID = stageRecordID(stageID: stageID)
            let preparedImages = try preparedImages(
                context: .init(stageID: stageRecordID)
            )
            draft.id = stageRecordID
            draft.name = trimmedName
            draft.category = trimmedCategory.nilIfEmpty.map { OMERecord.Stage.Category($0) }
            draft.color = color
            draft.iconShortCode = trimmedIconShortCode.nilIfEmpty
            draft.sortIndex = parsedSortIndex
            draft.systemIconName = trimmedSystemIconName.nilIfEmpty
            draft.images = preparedImages.images.isEmpty ? nil : preparedImages.images
            return (draft, preparedImages.blobs)
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

        func stageID(in db: Database) throws -> OMERecord.ID<OMERecord.Stage> {
            if let stageID = mode.stageID {
                return stageID
            }

            let base = Self.stageIDBase(for: trimmedName)
            var candidate = base
            var suffix = 2

            while try StageDetail.stageQuery(
                stageID: Self.localID(candidate),
                eventID: eventID
            )
            .fetchOne(db) != nil {
                candidate = "\(base)-\(suffix)"
                suffix += 1
            }

            return Self.localID(candidate)
        }

        func stageRecordID(
            stageID: OMERecord.ID<OMERecord.Stage>
        ) -> OMERecord.Stage.ID {
            OMERecord.Stage.ID(
                organizerID: eventID.organizerID,
                eventID: eventID.eventID,
                stageID: stageID
            )
        }

        mutating func resetImagePickers() {
            let cacheContext = imageCacheContext
            heroImagePicker = ImageAssetPicker.State(
                configuration: .stageHero,
                assets: draft.images,
                cacheContext: cacheContext
            )
            logoImagePicker = ImageAssetPicker.State(
                configuration: .stageLogo,
                assets: draft.images,
                cacheContext: cacheContext
            )
            posterImagePicker = ImageAssetPicker.State(
                configuration: .stagePoster,
                assets: draft.images,
                cacheContext: cacheContext
            )
        }

        private var imageCacheContext: LocalImageCacheContext? {
            if let id = draft.id {
                return LocalImageCacheContext(stageID: id)
            }
            if let stageID = mode.stageID {
                return LocalImageCacheContext(stageID: stageRecordID(stageID: stageID))
            }
            return nil
        }

        private var parsedSortIndex: Int? {
            trimmedSortIndex.isEmpty ? nil : Int(trimmedSortIndex)
        }

        private func preparedImages(
            context: LocalImageCacheContext
        ) throws -> (images: [OMERecord.ImageAsset], blobs: [LocalImageBlob]) {
            var images = (draft.images ?? []).filter {
                $0.role != .logo && $0.role != .hero && $0.role != .poster
            }
            var blobs: [LocalImageBlob] = []

            for picker in [logoImagePicker, heroImagePicker, posterImagePicker] {
                let preparedImages = try picker.materializedImages(context: context)
                images.append(contentsOf: preparedImages.images)
                blobs.append(contentsOf: preparedImages.blobs)
            }

            return (images, blobs)
        }

        private var trimmedCategory: String {
            category.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private var trimmedIconShortCode: String {
            iconShortCode.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private var trimmedName: String {
            form.value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private var trimmedSortIndex: String {
            sortIndex.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private var trimmedSystemIconName: String {
            systemIconName.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private static func emptyDraft(
            stageID: OMERecord.ID<OMERecord.Stage>?,
            eventID: OMERecord.Event.ID
        ) -> OMERecord.Stage.Draft {
            OMERecord.Stage.Draft(
                id: stageID.map {
                    OMERecord.Stage.ID(
                        organizerID: eventID.organizerID,
                        eventID: eventID.eventID,
                        stageID: $0
                    )
                },
                name: "",
                color: 0x336699,
                category: nil,
                sortIndex: nil,
                images: nil,
                systemIconName: nil,
                iconShortCode: nil,
                lineup: nil
            )
        }

        private static func localID(_ string: String) -> OMERecord.ID<OMERecord.Stage> {
            OMERecord.ID<OMERecord.Stage>(.init(string))
        }

        fileprivate static func parseHexColor(_ string: String) -> OMEColor? {
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

            return OMEColor(rawValue)
        }

        private static func stageIDBase(for name: String) -> String {
            let normalized = name
                .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
                .lowercased()
            let words = normalized
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }

            return words.isEmpty
                ? "stage-\(UUID().uuidString.lowercased())"
                : words.joined(separator: "-")
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

    public var body: some Feature {
        Scope(\.form, action: \.form) {
            FormFeature()
                .onSubmit { value in
                    try store.send(.formSubmitted(value))
                }
        }
        Scope(\.heroImagePicker, action: \.heroImagePicker) {
            ImageAssetPicker()
        }
        Scope(\.logoImagePicker, action: \.logoImagePicker) {
            ImageAssetPicker()
        }
        Scope(\.posterImagePicker, action: \.posterImagePicker) {
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
                let draftState = state

                store.addTask {
                    do {
                        try database.write { db in
                            if case .create = draftState.mode {
                                let stages = try StagesViewer
                                    .stagesQuery(eventID: draftState.eventID)
                                    .fetchAll(db)
                                if StagesViewer.hasOnlyReplaceableSingletonStage(stages) {
                                    try CopyStagesFromEvent.deleteSingletonStage(
                                        eventID: draftState.eventID,
                                        in: db
                                    )
                                }
                            }
                            let stageID = try draftState.stageID(in: db)
                            let preparedDraft = try draftState.preparedDraft(stageID: stageID)
                            try OMERecord.Stage.upsert {
                                preparedDraft.draft
                            }
                            .execute(db)
                            if !preparedDraft.blobs.isEmpty {
                                try LocalImageBlob.insert { preparedDraft.blobs }.execute(db)
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
        .ifLet(\.destination, action: \.destination) {
            EmptyFeature()
                .ifCaseLet(\.heroImportImages) {
                    ImportImages()
                }
                .ifCaseLet(\.heroImageInfo) {
                    ImageInfo { imageID, asset in
                        try store.modify {
                            $0.heroImagePicker.updateImageInfo(
                                imageID: imageID,
                                asset: asset
                            )
                        }
                    }
                }
                .ifCaseLet(\.logoImportImages) {
                    ImportImages()
                }
                .ifCaseLet(\.logoImageInfo) {
                    ImageInfo { imageID, asset in
                        try store.modify {
                            $0.logoImagePicker.updateImageInfo(
                                imageID: imageID,
                                asset: asset
                            )
                        }
                    }
                }
                .ifCaseLet(\.posterImportImages) {
                    ImportImages()
                }
                .ifCaseLet(\.posterImageInfo) {
                    ImageInfo { imageID, asset in
                        try store.modify {
                            $0.posterImagePicker.updateImageInfo(
                                imageID: imageID,
                                asset: asset
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
                    state.draft = stage.editDraft
                    state.form = FormFeature.State(value: FormValue(draft: state.draft))
                    state.hasLoadedDraft = true
                    state.errorMessage = nil
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
        .sheet(item: $store.scope(\.destination, action: \.destination).logoImportImages) { importStore in
            NavigationStack {
                ImportImagesView(store: importStore)
            }
        }
        .sheet(item: $store.scope(\.destination, action: \.destination).logoImageInfo) { imageInfoStore in
            NavigationStack {
                ImageInfoView(store: imageInfoStore)
            }
        }
        .sheet(item: $store.scope(\.destination, action: \.destination).heroImportImages) { importStore in
            NavigationStack {
                ImportImagesView(store: importStore)
            }
        }
        .sheet(item: $store.scope(\.destination, action: \.destination).heroImageInfo) { imageInfoStore in
            NavigationStack {
                ImageInfoView(store: imageInfoStore)
            }
        }
        .sheet(item: $store.scope(\.destination, action: \.destination).posterImportImages) { importStore in
            NavigationStack {
                ImportImagesView(store: importStore)
            }
        }
        .sheet(item: $store.scope(\.destination, action: \.destination).posterImageInfo) { imageInfoStore in
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
            TextField("SF Symbol", text: $store.form.value.systemIconName)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
            TextField("Short Code", text: $store.form.value.iconShortCode)
                #if os(iOS)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                #endif
        }
    }

    private var imageSection: some View {
        Group {
            ImageAssetPickerSection(
                store: store.scope(\.logoImagePicker, action: \.logoImagePicker)
            )
            ImageAssetPickerSection(
                store: store.scope(\.heroImagePicker, action: \.heroImagePicker)
            )
            ImageAssetPickerSection(
                store: store.scope(\.posterImagePicker, action: \.posterImagePicker)
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

private extension OMERecord.Stage {
    var editDraft: OMERecord.Stage.Draft {
        OMERecord.Stage.Draft(
            id: id,
            name: name,
            color: color,
            category: category,
            sortIndex: sortIndex,
            images: images,
            systemIconName: systemIconName,
            iconShortCode: iconShortCode,
            lineup: lineup
        )
    }

    var hasDisplayDetails: Bool {
        category?.displayName != nil || sortIndex != nil
    }

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
    static func formatHexColor(_ color: OMEColor) -> String {
        String(format: "#%06X", color.rawValue & 0xFFFFFF)
    }
}

private extension OMEColor {
    var editStageColor: Color {
        get { swiftUIColor }
        set {
            guard let color = OMEColor(newValue) else { return }
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

    init(red: CGFloat, green: CGFloat, blue: CGFloat) {
        self.init(
            (Int((red * 255).rounded()) << 16)
                | (Int((green * 255).rounded()) << 8)
                | Int((blue * 255).rounded())
        )
    }
}
