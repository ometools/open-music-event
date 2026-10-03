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
                                LabeledContent("Category", value: eventPlaceDivisionTitle(category))
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

