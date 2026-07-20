import ComposableArchitecture2
import Dependencies
import ErrorHandling
import IssueReporting
import Sharing
import OpenMusicEventDatabase
import OpenMusicEventEditors
import OpenMusicEventAuthentication
import OpenMusicEventSourceEditing
import OpenMusicEventViewers
import SQLiteData
import SourceEditing
import SwiftUI
import SwiftUITabFeatures
import Tagged

private enum DefaultEventIDKey: DependencyKey {
    static var liveValue: OMERecord.Event.ID {
        unimplemented(
            "DependencyValues.defaultEventID",
            placeholder: .init(
                organizerID: OMERecord.Organizer.ID("did:web:example.com")!,
                eventID: .init("-1")
            )
        )
    }
}

private enum DefaultEventTimeZoneKey: DependencyKey {
    static var liveValue: TimeZone {
        .current
    }

    static let testValue = TimeZone(secondsFromGMT: 0)!
}

extension DependencyValues {
    var defaultEventID: OMERecord.Event.ID {
        get { self[DefaultEventIDKey.self] }
        set { self[DefaultEventIDKey.self] = newValue }
    }

    var defaultEventTimeZone: TimeZone {
        get { self[DefaultEventTimeZoneKey.self] }
        set { self[DefaultEventTimeZoneKey.self] = newValue }
    }
}

private func updateEventWorkspaceDependencies(
    eventID: OMERecord.Event.ID,
    dependencies: inout DependencyValues
) {
    do {
        dependencies.sourceEditingSession = try dependencies.sourceWorkspaceDatabase
            .event(eventID)?
            .sourceEditingSession
    } catch {
        dependencies.sourceEditingSession = nil
        reportIssue(error)
    }
}

extension OMERecord.Event {
  static var defaultEvent: some SelectStatementOf<OMERecord.Event> {
    @Dependency(\.defaultEventID) var defaultEventID
    return Self.where { $0.id.eq(defaultEventID) }
  }
}

extension OpenMusicEventViewers.EventFeature {
    static func defaultFeatures(authoringMode: Authoring.Mode) -> [Self] {
        let authoringFeatures = authoringMode.isAuthoring ? editorFeatures : []
        return defaultReadOnlyFeatures.filter { $0 != .search && $0 != .about }
            + authoringFeatures
            + [.search, .about]
    }

    static func features(
        eventID: OMERecord.Event.ID,
        authoringMode: Authoring.Mode
    ) -> [Self] {
        @Dependency(\.defaultDatabase) var database
        let stages = (try? database.read { db in
            try ScheduleViewer.stagesQuery(eventID: eventID).fetchAll(db)
        }) ?? []
        return features(
            scheduleDivisions: ScheduleViewer.scheduleDivisions(stages: stages),
            authoringMode: authoringMode
        )
    }

    static func features(
        scheduleDivisions: [ScheduleDivision],
        authoringMode: Authoring.Mode
    ) -> [Self] {
        let divisions = scheduleDivisions.isEmpty ? [.schedule] : scheduleDivisions
        return divisions.map(Self.schedule) + defaultFeatures(authoringMode: authoringMode).filter {
            $0.scheduleDivision == nil
        }
    }
}

@Feature
public struct EventViewer {
    public init() {}

    public typealias EventFeature = OpenMusicEventViewers.EventFeature

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.sourceDataRefresh) var sourceDataRefresh
    @StoreTaskID var sourceDataRefreshTask

    public struct State: Identifiable {
        public init(eventID: OMERecord.Event.ID) {
            let authoringMode = Self.authoringMode(eventID: eventID)
            self.init(
                eventID: eventID,
                authoringMode: authoringMode,
                features: EventFeature.features(
                    eventID: eventID,
                    authoringMode: authoringMode
                )
            )
        }

        public init(
            eventID: OMERecord.Event.ID,
            authoringMode: Authoring.Mode = .attendee,
            features: [EventFeature]
        ) {
            let eventTimeZone = Self.eventTimeZone(eventID: eventID)

            self.authoringMode = authoringMode
            self.eventID = eventID
            self.eventTimeZone = eventTimeZone
            self._eventViewerState = Shared(.eventViewerState(eventID))
            self._stages = FetchAll(ScheduleViewer.stagesQuery(eventID: eventID))
            self.installedFeatures = features
            self.selectedFeature = features.first ?? .schedule(.schedule)
            self.eventSearch = Spawn(EventSearch.State(eventID: eventID))
            self.installFeatureStores(features)
        }

        private mutating func installFeatureStores(
            _ features: [EventFeature],
            preservingEventWorkspace: Bool = true
        ) {
            let existingCommunicationsViewer = self.communicationsViewer
            let existingContactInfoViewer = self.contactInfoViewer
            let existingContributorsViewer = self.contributorsViewer
            let existingDestination = self.destination
            let existingEventInfoViewer = self.eventInfoViewer
            let existingEventSearch = self.eventSearch
            let existingEventSettings = self.eventSettings
            let existingEventWorkspace = self.eventWorkspace
            let existingLocationViewer = self.locationViewer
            let existingNotificationsViewer = self.notificationsViewer
            let existingPostersViewer = self.postersViewer
            let existingScheduleViewers = self.scheduleViewers
            let existingSiteMapViewer = self.siteMapViewer
            let existingStagesViewer = self.stagesViewer

            self.scheduleViewers = []
            self.contributorsViewer = nil
            self.stagesViewer = nil
            self.communicationsViewer = nil
            self.contactInfoViewer = nil
            self.locationViewer = nil
            self.siteMapViewer = nil
            self.postersViewer = nil
            self.notificationsViewer = nil
            self.eventSettings = nil
            self.eventWorkspace = nil
            self.eventSearch = existingEventSearch
            self.eventInfoViewer = nil
            self.destination = existingDestination

            withEventDependencies {
                for feature in features {
                    switch feature {
                    case let .schedule(division):
                        self.scheduleViewers.append(
                            existingScheduleViewers.first {
                                $0.state.scheduleDivision == division
                            } ?? Spawn(
                                ScheduleViewer.State(
                                    eventID: eventID,
                                    scheduleDivision: division
                                )
                            )
                        )
                    case .contributors:
                        self.contributorsViewer = existingContributorsViewer
                            ?? Spawn(ContributorsViewer.State(eventID: eventID))
                    case .stages:
                        self.stagesViewer = existingStagesViewer
                            ?? Spawn(StagesViewer.State(eventID: eventID))
                    case .communications:
                        self.communicationsViewer = existingCommunicationsViewer
                            ?? Spawn(CommunicationsViewer.State(eventID: eventID))
                    case .contactInfo:
                        self.contactInfoViewer = existingContactInfoViewer
                            ?? Spawn(ContactInfoViewer.State(eventID: eventID))
                    case .location:
                        self.locationViewer = existingLocationViewer
                            ?? Spawn(LocationViewer.State(eventID: eventID))
                    case .siteMap:
                        self.siteMapViewer = existingSiteMapViewer
                            ?? Spawn(SiteMapViewer.State(eventID: eventID))
                    case .posters:
                        self.postersViewer = existingPostersViewer
                            ?? Spawn(PostersViewer.State(eventID: eventID))
                    case .notifications:
                        self.notificationsViewer = existingNotificationsViewer
                            ?? Spawn(NotificationsViewer.State(eventID: eventID))
                    case .settings:
                        self.eventSettings = existingEventSettings
                            ?? Spawn(EventSettings.State(eventID: eventID))
                    case .workspace:
                        self.eventWorkspace = (preservingEventWorkspace
                            ? existingEventWorkspace
                            : nil)
                            ?? eventWorkspaceSpawn(eventID: eventID)
                    case .search:
                        self.eventSearch = existingEventSearch
                    case .about:
                        self.eventInfoViewer = existingEventInfoViewer
                            ?? Spawn(EventInfoViewer.State(eventID: eventID))
                    }
                }
            }
        }

        mutating func refreshAuthoringMode() {
            self.authoringMode = Self.authoringMode(eventID: eventID)
        }

        mutating func reloadFeaturesForAuthoringMode(
            preserving selectedFeature: EventFeature? = nil
        ) {
            let selectedFeature = selectedFeature ?? self.selectedFeature
            let features = withEventDependencies {
                EventFeature.features(
                    eventID: eventID,
                    authoringMode: authoringMode
                )
            }
            self.installedFeatures = features
            self.selectedFeature = features.contains(selectedFeature)
                ? selectedFeature
                : features.first ?? .schedule(.schedule)
            self.installFeatureStores(features)
        }

        mutating func setAuthoringMode(_ authoringMode: Authoring.Mode) {
            self.authoringMode = authoringMode
            self.reloadFeaturesForAuthoringMode()
        }

        mutating func reloadAfterSourceDataRefresh() {
            let mountedAuthoringMode = self.authoringMode
            self.refreshAuthoringMode()
            if mountedAuthoringMode.isAuthoring, !self.authoringMode.isAuthoring {
                self.authoringMode = mountedAuthoringMode
            }
            let selectedFeature = self.selectedFeature
            self.eventTimeZone = Self.eventTimeZone(eventID: eventID)
            let features = withEventDependencies {
                EventFeature.features(
                    eventID: eventID,
                    authoringMode: authoringMode
                )
            }
            self.installedFeatures = features
            self.selectedFeature = features.contains(selectedFeature)
                ? selectedFeature
                : features.first ?? .schedule(.schedule)
            self.installFeatureStores(features, preservingEventWorkspace: false)
        }

        public static func route(
            eventID: OMERecord.Event.ID,
            target: EventTarget?,
            authoringMode: Authoring.Mode? = nil
        ) -> Self {
            let authoringMode = authoringMode ?? Self.authoringMode(eventID: eventID)
            var state = Self(
                eventID: eventID,
                authoringMode: authoringMode,
                features: EventFeature.features(
                    eventID: eventID,
                    authoringMode: authoringMode
                )
            )
            if let target, target.eventFeature.isEditorFeature, !state.showsAuthoringControls {
                state.pendingAuthoringEntry = .target(target)
            } else {
                state.navigate(to: target)
            }
            return state
        }

        public var authoringMode: Authoring.Mode
        public let eventID: OMERecord.Event.ID
        public var eventTimeZone: TimeZone
        @Shared public var eventViewerState: EventViewerState
        @FetchAll public var stages: [OMERecord.Stage]
        public var installedFeatures: [EventFeature]
        public var selectedFeature: EventFeature

        public var scheduleViewers: [Spawn<ScheduleViewer>] = []
        public var contributorsViewer: Spawn<ContributorsViewer>?
        public var stagesViewer: Spawn<StagesViewer>?
        public var communicationsViewer: Spawn<CommunicationsViewer>?
        public var contactInfoViewer: Spawn<ContactInfoViewer>?
        public var locationViewer: Spawn<LocationViewer>?
        public var siteMapViewer: Spawn<SiteMapViewer>?
        public var postersViewer: Spawn<PostersViewer>?
        public var notificationsViewer: Spawn<NotificationsViewer>?
        public var eventSettings: Spawn<EventSettings>?
        public var eventWorkspace: Spawn<EventWorkspace>?
        public var account = Spawn(Account.State())
        public var eventSearch: Spawn<EventSearch>
        public var eventInfoViewer: Spawn<EventInfoViewer>?

        public var destination: Destination.State?
        public var pendingAuthoringEntry: EditorEntry?

        public var id: OMERecord.Event.ID { eventID }

        public var showsAuthoringControls: Bool {
            authoringMode.isAuthoring
        }

        public var needsStageDisambiguation: Bool {
            stages.count > 1
        }

        mutating func navigate(to target: EventTarget?) {
            guard let target else {
                self.eventSearch.state = EventSearch.State(eventID: eventID)
                self.contributorsViewer?.state.destination = nil
                self.stagesViewer?.state.destination = nil
                return
            }

            self.selectedFeature = target.eventFeature

            switch target {
            case let .contributor(contributorID):
                let eventID = self.eventID
                self.eventSearch.state = withEventDependencies {
                    EventSearch.State(eventID: eventID)
                }
                if self.contributorsViewer == nil {
                    self.contributorsViewer = withEventDependencies {
                        Spawn(ContributorsViewer.State(eventID: eventID))
                    }
                }
                let destination = withEventDependencies {
                    ContributorsViewer.Destination.State.contributorDetail(
                        Spawn(
                            ContributorDetail.State(
                                contributorID: contributorID,
                                eventID: eventID
                            )
                        )
                    )
                }
                self.contributorsViewer?.state.destination = destination
                self.stagesViewer?.state.destination = nil
            case .contributors:
                self.eventSearch.state = EventSearch.State(eventID: eventID)
                self.contributorsViewer?.state.destination = nil
                self.stagesViewer?.state.destination = nil
            case let .stage(stageID):
                let eventID = self.eventID
                self.eventSearch.state = withEventDependencies {
                    EventSearch.State(eventID: eventID)
                }
                self.contributorsViewer?.state.destination = nil
                if self.stagesViewer == nil {
                    self.stagesViewer = withEventDependencies {
                        Spawn(StagesViewer.State(eventID: eventID))
                    }
                }
                let destination = withEventDependencies {
                    StagesViewer.Destination.State.stageDetail(
                        Spawn(
                            StageDetail.State(
                                stageID: stageID,
                                eventID: eventID
                            )
                        )
                    )
                }
                self.stagesViewer?.state.destination = destination
            case let .performance(performanceID):
                let eventID = self.eventID
                self.eventSearch.state = EventSearch.State(eventID: eventID)
                self.contributorsViewer?.state.destination = nil
                self.stagesViewer?.state.destination = nil
                for index in self.scheduleViewers.indices {
                    self.scheduleViewers[index].state.destination = nil
                }
                guard let scheduleViewerIndex = self.scheduleViewers.firstIndex(where: {
                    $0.state.scheduleDivision == .schedule
                }) else { return }
                self.selectedFeature = .schedule(.schedule)
                self.scheduleViewers[scheduleViewerIndex].state.destination = withEventDependencies {
                    .performanceDetail(
                        Spawn(
                            PerformanceDetail.State(
                                performanceID: performanceID,
                                eventID: eventID
                            )
                        )
                    )
                }
            case .stages:
                self.eventSearch.state = EventSearch.State(eventID: eventID)
                self.contributorsViewer?.state.destination = nil
                self.stagesViewer?.state.destination = nil
            case .search:
                self.eventSearch.state = EventSearch.State.route(eventID: eventID, target: target)
                self.contributorsViewer?.state.destination = nil
                self.stagesViewer?.state.destination = nil
            case .workspace:
                self.eventSearch.state = EventSearch.State(eventID: eventID)
                self.contributorsViewer?.state.destination = nil
                self.stagesViewer?.state.destination = nil
                if self.eventWorkspace == nil {
                    self.eventWorkspace = eventWorkspaceSpawn(eventID: self.eventID)
                }
            default:
                self.eventSearch.state = EventSearch.State(eventID: eventID)
                self.contributorsViewer?.state.destination = nil
                self.stagesViewer?.state.destination = nil
            }
        }

        mutating func handleEditingIntent(_ intent: EventEditingIntent) {
            switch intent {
            case let .addPerformance(eventID, scheduleID, stageID):
                guard eventID == self.eventID else { return }
                guard let editPerformance = withEventDependencies({
                    addPerformanceState(
                        scheduleID: scheduleID,
                        stageID: stageID
                    )
                }) else { return }
                self.destination = .performanceForm(Spawn(editPerformance))

            case let .addSchedule(eventID):
                guard eventID == self.eventID else { return }
                self.destination = withEventDependencies {
                    .scheduleForm(Spawn(editScheduleState()))
                }

            case let .addPosters(eventID):
                guard eventID == self.eventID else { return }
                self.selectedFeature = .posters

            case let .copyStagesFromEvent(eventID):
                guard eventID == self.eventID else { return }
                self.selectedFeature = .stages
                self.destination = withEventDependencies {
                    .copyStagesFromEvent(Spawn(CopyStagesFromEvent.State(eventID: eventID)))
                }

            case let .createContributor(eventID):
                guard eventID == self.eventID else { return }
                self.destination = withEventDependencies {
                    .contributorForm(Spawn(EditContributor.State(eventID: eventID)))
                }

            case let .createStage(eventID):
                guard eventID == self.eventID else { return }
                self.destination = withEventDependencies {
                    .stageForm(Spawn(EditStage.State(eventID: eventID)))
                }

            case let .deletePerformance(eventID, _):
                guard eventID == self.eventID else { return }
                self.selectedFeature = .schedule(.schedule)

            case let .deletePoster(posterID),
                 let .editPoster(posterID):
                guard posterID.eventID == self.eventID.eventID,
                      posterID.organizerID == self.eventID.organizerID
                else { return }
                self.selectedFeature = .posters

            case let .editContactInfo(eventID):
                guard eventID == self.eventID else { return }
                self.destination = withEventDependencies {
                    .contactInfoForm(Spawn(EditContactInfo.State(eventID: eventID)))
                }

            case let .editContributor(eventID, contributorID):
                guard eventID == self.eventID else { return }
                self.destination = withEventDependencies {
                    .contributorForm(
                        Spawn(
                            EditContributor.State(
                                contributorID: contributorID,
                                eventID: eventID
                            )
                        )
                    )
                }

            case let .eventWorkspace(eventID):
                guard eventID == self.eventID else { return }
                self.selectedFeature = .workspace
                if self.eventWorkspace == nil {
                    self.eventWorkspace = eventWorkspaceSpawn(eventID: eventID)
                }

            case let .editEventInfo(eventID):
                guard eventID == self.eventID else { return }
                self.destination = withEventDependencies {
                    .eventInfoForm(Spawn(EditEventInfo.State(eventID: eventID)))
                }

            case let .editEventPolicies(eventID):
                guard eventID == self.eventID else { return }
                self.destination = withEventDependencies {
                    .eventPoliciesForm(Spawn(EditEventPolicies.State(eventID: eventID)))
                }

            case let .editLocation(eventID):
                guard eventID == self.eventID else { return }
                self.destination = withEventDependencies {
                    .locationForm(Spawn(EditLocation.State(eventID: eventID)))
                }

            case let .editPerformance(eventID, performanceID):
                guard eventID == self.eventID else { return }
                guard let editPerformance = withEventDependencies({
                    editPerformanceState(performanceID: performanceID)
                }) else { return }
                self.destination = .performanceForm(Spawn(editPerformance))

            case let .editReportingLink(eventID):
                guard eventID == self.eventID else { return }
                self.destination = withEventDependencies {
                    .reportingLinkForm(Spawn(EditReportingLink.State(eventID: eventID)))
                }

            case let .editStage(eventID, stageID):
                guard eventID == self.eventID else { return }
                self.destination = withEventDependencies {
                    .stageForm(
                        Spawn(
                            EditStage.State(
                                stageID: stageID,
                                eventID: eventID
                            )
                        )
                    )
                }

            case let .eventSettings(eventID):
                guard eventID == self.eventID else { return }
                self.selectedFeature = .settings
                if self.eventSettings == nil {
                    self.eventSettings = Spawn(EventSettings.State(eventID: eventID))
                }
            }
        }

        private func addPerformanceState(
            scheduleID: OMERecord.ID<OMERecord.Schedule>?,
            stageID: OMERecord.ID<OMERecord.Stage>?
        ) -> EditPerformance.State? {
            @Dependency(\.defaultDatabase) var database

            do {
                return try database.write { db in
                    let event = try OMERecord.Event
                        .where { $0.id.eq(eventID) }
                        .fetchOne(db)
                    let schedules = try ScheduleViewer.schedulesQuery(eventID: eventID).fetchAll(db)
                    let stages = try ScheduleViewer.stagesQuery(eventID: eventID).fetchAll(db)
                    let contributors = try ContributorProfile
                        .all(eventID: eventID, hydration: .none)
                        .fetchAll(db)
                    guard !stages.isEmpty else { return nil }

                    let resolvedScheduleID = scheduleID.flatMap { scheduleID in
                        schedules.contains { $0.id.scheduleID == scheduleID }
                            ? scheduleID
                            : nil
                    }
                    var schedule = resolvedScheduleID.flatMap { scheduleID in
                        schedules.first { $0.id.scheduleID == scheduleID }
                    } ?? schedules.first
                    if schedule == nil {
                        schedule = try Self.insertSingletonSchedule(
                            event: event,
                            eventID: eventID,
                            in: db
                        )
                    }
                    guard let schedule else { return nil }
                    let resolvedStageID = stageID.flatMap { stageID in
                        stages.contains { $0.id.stageID == stageID }
                            ? stageID
                            : nil
                    } ?? stages.first?.id.stageID
                    guard let resolvedStageID else { return nil }
                    let initialStartTime = try OMERecord.Performance
                        .where { $0.id.organizerID.eq(eventID.organizerID) }
                        .where { $0.id.eventID.eq(eventID.eventID) }
                        .where { $0.scheduleID.eq(schedule.id.scheduleID) }
                        .where { $0.stageID.eq(resolvedStageID) }
                        .fetchAll(db)
                        .map(\.endTime)
                        .max()

                    return EditPerformance.State(
                        eventID: eventID,
                        schedule: schedule,
                        stages: stages,
                        timeZone: eventTimeZone,
                        selectedStageID: resolvedStageID,
                        initialStartTime: initialStartTime,
                        contributors: contributors
                    )
                }
            } catch {
                return nil
            }
        }

        private static func insertSingletonSchedule(
            event: OMERecord.Event?,
            eventID: OMERecord.Event.ID,
            in db: Database
        ) throws -> OMERecord.Schedule? {
            guard let scheduleDate = event?.startDate else { return nil }
            let scheduleID = OMERecord.Schedule.ID(
                organizerID: eventID.organizerID,
                eventID: eventID.eventID,
                scheduleID: OMERecord.Schedule.singletonID
            )
            try OMERecord.Schedule.insert {
                OMERecord.Schedule.Draft(
                    id: scheduleID,
                    date: scheduleDate,
                    startsAt: nil,
                    endsAt: nil,
                    customTitle: nil
                )
            }
            .execute(db)
            return try OMERecord.Schedule
                .find(scheduleID)
                .fetchOne(db)
        }

        private func editPerformanceState(
            performanceID: OMERecord.ID<OMERecord.Performance>
        ) -> EditPerformance.State? {
            @Dependency(\.defaultDatabase) var database

            do {
                return try database.read { db in
                    let performanceRows = try PerformanceRow.all(eventID: eventID).fetchAll(db)
                    let schedules = try ScheduleViewer.schedulesQuery(eventID: eventID).fetchAll(db)
                    let stages = try ScheduleViewer.stagesQuery(eventID: eventID).fetchAll(db)
                    let contributors = try ContributorProfile
                        .all(eventID: eventID, hydration: .none)
                        .fetchAll(db)
                    guard
                        let row = performanceRows.first(where: { $0.performanceID == performanceID }),
                        let scheduleID = row.performance.scheduleID,
                        let schedule = schedules.first(where: { $0.id.scheduleID == scheduleID })
                    else { return nil }
                    let performanceContributors = try EditPerformance
                        .performanceContributorsQuery(
                            performanceID: performanceID,
                            eventID: eventID
                        )
                        .fetchAll(db)

                    return EditPerformance.State(
                        eventID: eventID,
                        schedule: schedule,
                        stages: stages,
                        timeZone: eventTimeZone,
                        performance: row.performance,
                        contributors: contributors,
                        performanceContributors: performanceContributors
                    )
                }
            } catch {
                return nil
            }
        }

        private func editScheduleState() -> EditSchedule.State {
            @Dependency(\.defaultDatabase) var database

            let initialDate: LocalDate?
            do {
                initialDate = try database.read { db in
                    try OMERecord.Event
                        .where { $0.id.eq(eventID) }
                        .fetchOne(db)?
                        .startDate
                }
            } catch {
                initialDate = nil
            }

            return EditSchedule.State(
                eventID: eventID,
                initialDate: initialDate,
                timeZone: eventTimeZone
            )
        }

        private func withEventDependencies<Value>(_ operation: () -> Value) -> Value {
            let eventID = self.eventID
            let eventTimeZone = self.eventTimeZone
            return withDependencies {
                $0.defaultEventID = eventID
                $0.defaultEventTimeZone = eventTimeZone
            } operation: {
                operation()
            }
        }

        private func eventWorkspaceSpawn(
            eventID: OMERecord.Event.ID
        ) -> Spawn<EventWorkspace> {
            withDependencies {
                updateEventWorkspaceDependencies(eventID: eventID, dependencies: &$0)
            } operation: {
                Spawn(EventWorkspace.State(eventID: eventID))
            }
        }

        private static func eventTimeZone(eventID: OMERecord.Event.ID) -> TimeZone {
            @Dependency(\.defaultDatabase) var database
            return (
                try? database.read { db in
                    try OMERecord.Event
                        .where { $0.id.eq(eventID) }
                        .fetchOne(db)?
                        .timeZone
                }
            ) ?? .current
        }

        private static func authoringMode(eventID: OMERecord.Event.ID) -> Authoring.Mode {
            @Dependency(\.authoringPolicy) var authoringPolicy
            return (
                try? authoringPolicy.mode(.event(eventID))
            ) ?? .attendee
        }
    }

    public enum Action {
        case closeButtonTapped
        case destination(Destination.Action)
        case eventSearch(EventSearch.Action)
        case sourceDataRefreshCompleted(SourceDataRefreshRequest)
    }

    public enum EditorEntry: Equatable, Sendable {
        case feature(EventFeature)
        case intent(EventEditingIntent)
        case target(EventTarget)
    }

    @Feature
    public enum Destination {
        case contactInfoForm(Spawn<EditContactInfo>)
        case contributorForm(Spawn<EditContributor>)
        case copyStagesFromEvent(Spawn<CopyStagesFromEvent>)
        case eventInfoForm(Spawn<EditEventInfo>)
        case eventPoliciesForm(Spawn<EditEventPolicies>)
        case locationForm(Spawn<EditLocation>)
        case performanceForm(Spawn<EditPerformance>)
        case reportingLinkForm(Spawn<EditReportingLink>)
        case scheduleForm(Spawn<EditSchedule>)
        case stageForm(Spawn<EditStage>)
    }

    private func enterOrAuthorizeAuthoringEntry(_ entry: EditorEntry, state: inout State) {
        let previousAuthoringMode = state.authoringMode
        state.refreshAuthoringMode()
        if state.authoringMode != previousAuthoringMode {
            state.reloadFeaturesForAuthoringMode()
        }
        guard !state.showsAuthoringControls else {
            state.pendingAuthoringEntry = nil
            store.withDependencies {
                state.enterAuthoringEntry(entry)
            }
            return
        }
        state.setAuthoringMode(.authoring(.all))
        state.pendingAuthoringEntry = nil
        store.withDependencies {
            state.enterAuthoringEntry(entry)
        }
    }

    public var body: some Feature {
//        let _ = Self._logChanges()
        Update { state, action in
            switch action {
            case .closeButtonTapped:
                store.addTask {
                    try store.dismiss()
                }

            case .destination:
                break

            case .eventSearch:
                break

            case let .sourceDataRefreshCompleted(request):
                guard request.eventID == state.eventID else { return }
                var sourceWorkspaceSummary: Fetch<SourceWorkspaceSummary>?
                withDependencies {
                    updateEventWorkspaceDependencies(
                        eventID: request.eventID,
                        dependencies: &$0
                    )
                } operation: {
                    state.reloadAfterSourceDataRefresh()
                    sourceWorkspaceSummary = state.eventWorkspace?
                        .state
                        .$sourceWorkspaceSummary
                }
                guard let sourceWorkspaceSummary else { return }
                store.addTask {
                    let _: Void? = await store.withErrorHandling(
                        fallbackMessage: .sourceDataRefreshFailed,
                        operation: .sourceDataRefresh
                    ) {
                        try await sourceWorkspaceSummary.load()
                    }
                }
            }
        }
        .onChange(of: store.selectedFeature) { _, feature, state in
            guard feature.isEditorFeature else { return }
            enterOrAuthorizeAuthoringEntry(.feature(feature), state: &state)
        }
        .onMount { state in
            let mountedAuthoringMode = state.authoringMode
            state.refreshAuthoringMode()
            if mountedAuthoringMode.isAuthoring, !state.authoringMode.isAuthoring {
                state.authoringMode = mountedAuthoringMode
            }
            state.reloadFeaturesForAuthoringMode()
            guard let pendingAuthoringEntry = state.pendingAuthoringEntry else { return }
            enterOrAuthorizeAuthoringEntry(pendingAuthoringEntry, state: &state)
        }
        .onEvent(NavigationRequested.self) { request, state in
            if case let .event(eventID, target) = request, eventID == state.eventID {
                if let target, target.eventFeature.isEditorFeature {
                    enterOrAuthorizeAuthoringEntry(.target(target), state: &state)
                } else {
                    state.navigate(to: target)
                }
            }
        }
        .onEvent(EventEditingRequested.self) { intent, state in
            if intent.eventID == state.eventID {
                enterOrAuthorizeAuthoringEntry(.intent(intent), state: &state)
            }
        }
        .onEvent(SourceDataRefreshRequested.self) { request, state in
            guard request.eventID == state.eventID else { return }
            store.addTask(id: sourceDataRefreshTask) {
                let result: Void? = await store.withErrorHandling(
                    fallbackMessage: .sourceDataRefreshFailed,
                    operation: .sourceDataRefresh
                ) {
                    try await sourceDataRefresh.refresh(request.sourceBaselineID)
                }
                guard result != nil else { return }
                try store.send(.sourceDataRefreshCompleted(request))
            }
        }
        .forEach(\.scheduleViewers) {
            ScheduleViewer()
        }
        .ifLet(\.contributorsViewer) {
            ContributorsViewer()
        }
        .ifLet(\.stagesViewer) {
            StagesViewer()
        }
        .spawn(\.eventSearch) {
            EventSearch()
        }
        .ifLet(\.communicationsViewer) {
            CommunicationsViewer()
        }
        .ifLet(\.contactInfoViewer) {
            ContactInfoViewer()
        }
        .ifLet(\.locationViewer) {
            LocationViewer()
        }
        .ifLet(\.siteMapViewer) {
            SiteMapViewer()
        }
        .ifLet(\.postersViewer) {
            PostersViewer()
        }
        .ifLet(\.notificationsViewer) {
            NotificationsViewer()
        }
        .ifLet(\.eventSettings) {
            EventSettings()
        }
        .ifLet(\.eventWorkspace) {
            EventWorkspace()
                .transformDependency(\.self) { (dependencies: inout DependencyValues) in
                    updateEventWorkspaceDependencies(
                        eventID: store.eventID,
                        dependencies: &dependencies
                    )
                }
        }
        .spawn(\.account) {
            Account()
        }
        .ifLet(\.eventInfoViewer) {
            EventInfoViewer()
        }
        .ifLet(\.destination, action: \.destination) {
            Destination.body
                .dependency(\.defaultEventID, store.eventID)
                .dependency(\.defaultEventTimeZone, store.eventTimeZone)
        }
        .dependency(\.defaultEventID, store.eventID)
        .dependency(\.defaultEventTimeZone, store.eventTimeZone)
    }
}

extension EventViewer.Destination.StoreEnumeration: @MainActor Identifiable {
    public typealias ID = AnyHashable

    @MainActor
    public var id: ID {
        switch self {
        case let .contactInfoForm(store):
            destinationID("contactInfoForm", store.eventID)
        case let .contributorForm(store):
            destinationID("contributorForm", store.eventID, store.mode.contributorID)
        case let .copyStagesFromEvent(store):
            destinationID("copyStagesFromEvent", store.eventID)
        case let .eventInfoForm(store):
            destinationID("eventInfoForm", store.eventID)
        case let .eventPoliciesForm(store):
            destinationID("eventPoliciesForm", store.eventID)
        case let .locationForm(store):
            destinationID("locationForm", store.eventID)
        case let .performanceForm(store):
            destinationID("performanceForm", store.eventID, store.schedule.id.scheduleID, store.performanceID)
        case let .reportingLinkForm(store):
            destinationID("reportingLinkForm", store.eventID)
        case let .scheduleForm(store):
            destinationID("scheduleForm", store.eventID)
        case let .stageForm(store):
            destinationID("stageForm", store.eventID, store.stageID)
        }
    }

    private func destinationID(_ components: AnyHashable...) -> AnyHashable {
        AnyHashable(components)
    }
}

public struct EventViewerView: View {
    public init(store: StoreOf<EventViewer>) {
        self.store = store
    }

    @Bindable var store: StoreOf<EventViewer>

    public var body: some View {
        tabContent
            .environment(\.needsStageDisambiguation, store.needsStageDisambiguation)
            .sheet(item: $store.scope(\.destination, action: \.destination)) { _ in
                if let destinationStore = store.scope(\.destination, action: \.destination) {
                    NavigationStack {
                        destinationContent(EventViewer.Destination.switch(store: destinationStore))
                    }
                    .environment(\.needsStageDisambiguation, store.needsStageDisambiguation)
                }
            }
    }

    @ViewBuilder
    private func destinationContent(
        _ destinationStore: EventViewer.Destination.StoreEnumeration
    ) -> some View {
        switch destinationStore {
        case let .copyStagesFromEvent(copyStore):
            CopyStagesFromEventView(store: copyStore)
        case let .contributorForm(formStore):
            EditContributorView(store: formStore)
        case let .stageForm(formStore):
            EditStageView(store: formStore)
        case let .contactInfoForm(formStore):
            EditContactInfoView(store: formStore)
        case let .eventInfoForm(formStore):
            EditEventInfoView(store: formStore)
        case let .eventPoliciesForm(formStore):
            EditEventPoliciesView(store: formStore)
        case let .locationForm(formStore):
            EditLocationView(store: formStore)
        case let .performanceForm(formStore):
            EditPerformanceView(store: formStore)
        case let .reportingLinkForm(formStore):
            EditReportingLinkView(store: formStore)
        case let .scheduleForm(formStore):
            EditScheduleView(store: formStore)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        #if os(iOS)
        if #available(iOS 18.0, *) {
            TabFeaturesViewer(store: store)
        } else {
            legacyiOSTabView
        }
        #elseif os(macOS)
        if #available(macOS 15.0, *) {
            TabFeaturesViewer(store: store)
        } else {
            defaultTabView
        }
        #else
        defaultTabView
        #endif
    }

    @available(iOS 18.0, macOS 15.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *)
    struct TabFeaturesViewer: View {
        @Bindable var store: StoreOf<EventViewer>
        @State var tabLayout = TabFeatureLayout()

        var body: some View {
            let accountStore = store.spawn(\.account)

            TabFeaturesView(
                selection: $store.selectedFeature,
                layout: $tabLayout
            ) {
                if store.installedFeatures.contains(.search) {
                    TabFeature(.search, role: .search, navigation: .stack) {
                        EventSearchView(store: store.spawn(\.eventSearch))
                    }
                }

                for featureStore in store.spawn(\.scheduleViewers) {
                    let feature = EventViewer.EventFeature.schedule(featureStore.scheduleDivision)
                    TabFeature(
                        feature,
                        title: feature.title,
                        systemImage: feature.systemImage,
                        labelTint: feature.labelTint,
                        navigation: .stack
                    ) {
                        ScheduleViewerView(
                            store: featureStore,
                            selectedScheduleID: store.state.$eventViewerState.selectedScheduleID,
                            showsAuthoringControls: store.showsAuthoringControls
                        )
                    }
                }

                if let featureStore = store.spawn(\.contributorsViewer) {
                    TabFeature(
                        .contributors,
                        title: EventViewer.EventFeature.contributors.title,
                        systemImage: EventViewer.EventFeature.contributors.systemImage,
                        labelTint: EventViewer.EventFeature.contributors.labelTint,
                        navigation: .stack
                    ) {
                        ContributorsViewerView(
                            store: featureStore,
                            showsAuthoringControls: store.showsAuthoringControls
                        )
                    }
                }

                if let featureStore = store.spawn(\.stagesViewer) {
                    TabFeature(
                        .stages,
                        title: EventViewer.EventFeature.stages.title,
                        systemImage: EventViewer.EventFeature.stages.systemImage,
                        labelTint: EventViewer.EventFeature.stages.labelTint,
                        navigation: .stack
                    ) {
                        StagesViewerView(
                            store: featureStore,
                            showsAuthoringControls: store.showsAuthoringControls
                        )
                    }
                }

                if let featureStore = store.spawn(\.communicationsViewer) {
                    TabFeature(
                        .communications,
                        title: EventViewer.EventFeature.communications.title,
                        systemImage: EventViewer.EventFeature.communications.systemImage,
                        labelTint: EventViewer.EventFeature.communications.labelTint,
                        navigation: .stack
                    ) {
                        CommunicationsViewerView(store: featureStore)
                    }
                }

                Section("Event") {
                    if let featureStore = store.spawn(\.contactInfoViewer) {
                        TabFeature(
                            .contactInfo,
                            title: EventViewer.EventFeature.contactInfo.title,
                            systemImage: EventViewer.EventFeature.contactInfo.systemImage,
                            labelTint: EventViewer.EventFeature.contactInfo.labelTint,
                            navigation: .stack
                        ) {
                            ContactInfoViewerView(
                                store: featureStore,
                                showsAuthoringControls: store.showsAuthoringControls
                            )
                        }
                    }

                    if let featureStore = store.spawn(\.locationViewer) {
                        TabFeature(
                            .location,
                            title: EventViewer.EventFeature.location.title,
                            systemImage: EventViewer.EventFeature.location.systemImage,
                            labelTint: EventViewer.EventFeature.location.labelTint,
                            navigation: .stack
                        ) {
                            LocationViewerView(
                                store: featureStore,
                                showsAuthoringControls: store.showsAuthoringControls
                            )
                        }
                    }

                    if let featureStore = store.spawn(\.siteMapViewer) {
                        TabFeature(
                            .siteMap,
                            title: EventViewer.EventFeature.siteMap.title,
                            systemImage: EventViewer.EventFeature.siteMap.systemImage,
                            labelTint: EventViewer.EventFeature.siteMap.labelTint,
                            navigation: .stack
                        ) {
                            SiteMapViewerView(store: featureStore)
                        }
                    }
                }

                if let featureStore = store.spawn(\.postersViewer) {
                    TabFeature(
                        .posters,
                        title: EventViewer.EventFeature.posters.title,
                        systemImage: EventViewer.EventFeature.posters.systemImage,
                        labelTint: EventViewer.EventFeature.posters.labelTint,
                        navigation: .stack
                    ) {
                        PostersViewerView(
                            store: featureStore,
                            showsAuthoringControls: store.showsAuthoringControls
                        )
                    }
                }

                if let featureStore = store.spawn(\.notificationsViewer) {
                    TabFeature(
                        .notifications,
                        title: EventViewer.EventFeature.notifications.title,
                        systemImage: EventViewer.EventFeature.notifications.systemImage,
                        labelTint: EventViewer.EventFeature.notifications.labelTint,
                        navigation: .stack
                    ) {
                        NotificationsViewerView(store: featureStore)
                    }
                }

                if let featureStore = store.spawn(\.eventSettings) {
                    TabFeature(
                        .settings,
                        title: EventViewer.EventFeature.settings.title,
                        systemImage: EventViewer.EventFeature.settings.systemImage,
                        labelTint: EventViewer.EventFeature.settings.labelTint,
                        navigation: .stack
                    ) {
                        EventSettingsView(store: featureStore)
                    }
                }

                if let featureStore = store.spawn(\.eventWorkspace) {
                    TabFeature(
                        .workspace,
                        title: EventViewer.EventFeature.workspace.title,
                        systemImage: EventViewer.EventFeature.workspace.systemImage,
                        labelTint: EventViewer.EventFeature.workspace.labelTint,
                        badgeValue: featureStore.changeCount,
                        navigation: .stack
                    ) {
                        EventWorkspaceView(store: featureStore)
                    }
                }

                if let featureStore = store.spawn(\.eventInfoViewer) {
                    TabFeature(
                        .about,
                        title: EventViewer.EventFeature.about.title,
                        systemImage: EventViewer.EventFeature.about.systemImage,
                        labelTint: EventViewer.EventFeature.about.labelTint,
                        navigation: .stack
                    ) {
                        EventInfoViewerView(
                            store: featureStore,
                            showsAuthoringControls: store.showsAuthoringControls
                        )
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button {
                                    store.send(.closeButtonTapped)
                                } label: {
                                    Label("Close", systemImage: "xmark")
                                        .labelStyle(.iconOnly)
                                }
                            }
                        }
                    }
                }

            }
            .more {
                EmptyView()
            } toolbar: {
                #if os(macOS) && !SKIP
                ToolbarItem(placement: .automatic) {
                    AccountPicker(store: accountStore)
                }
                #else
                ToolbarItem(placement: .topBarLeading) {
                    AccountPicker(store: accountStore)
                }
                #endif

                #if os(macOS) && !SKIP
                ToolbarItem(placement: .primaryAction) {
                    Button("Exit") {
                        store.send(.closeButtonTapped)
                    }
                }
                #else
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Exit") {
                        store.send(.closeButtonTapped)
                    }
                }
                #endif
            }
        }

    }

    #if os(iOS)
    private var legacyiOSTabView: some View {
        TabView(selection: $store.selectedFeature) {
            ForEach(store.spawn(\.scheduleViewers)) { featureStore in
                let feature = EventViewer.EventFeature.schedule(featureStore.scheduleDivision)
                viewerTab(feature) {
                    ScheduleViewerView(
                        store: featureStore,
                        selectedScheduleID: store.state.$eventViewerState.selectedScheduleID,
                        showsAuthoringControls: store.showsAuthoringControls
                    )
                }
                .tag(feature)
            }

            if let featureStore = store.spawn(\.contributorsViewer) {
                viewerTab(.contributors) {
                    ContributorsViewerView(
                        store: featureStore,
                        showsAuthoringControls: store.showsAuthoringControls
                    )
                }
                .tag(EventViewer.EventFeature.contributors)
            }

            if let featureStore = store.spawn(\.stagesViewer) {
                viewerTab(.stages) {
                    StagesViewerView(
                        store: featureStore,
                        showsAuthoringControls: store.showsAuthoringControls
                    )
                }
                .tag(EventViewer.EventFeature.stages)
            }

            if let featureStore = store.spawn(\.communicationsViewer) {
                viewerTab(.communications) {
                    CommunicationsViewerView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.communications)
            }

            if let featureStore = store.spawn(\.contactInfoViewer) {
                viewerTab(.contactInfo) {
                    ContactInfoViewerView(
                        store: featureStore,
                        showsAuthoringControls: store.showsAuthoringControls
                    )
                }
                .tag(EventViewer.EventFeature.contactInfo)
            }

            if let featureStore = store.spawn(\.locationViewer) {
                viewerTab(.location) {
                    LocationViewerView(
                        store: featureStore,
                        showsAuthoringControls: store.showsAuthoringControls
                    )
                }
                .tag(EventViewer.EventFeature.location)
            }

            if store.installedFeatures.contains(.search) {
                viewerTab(.search) {
                    EventSearchView(store: store.spawn(\.eventSearch))
                }
                .tag(EventViewer.EventFeature.search)
            }

            if let featureStore = store.spawn(\.siteMapViewer) {
                viewerTab(.siteMap) {
                    SiteMapViewerView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.siteMap)
            }

            if let featureStore = store.spawn(\.postersViewer) {
                viewerTab(.posters) {
                    PostersViewerView(
                        store: featureStore,
                        showsAuthoringControls: store.showsAuthoringControls
                    )
                }
                .tag(EventViewer.EventFeature.posters)
            }

            if let featureStore = store.spawn(\.notificationsViewer) {
                viewerTab(.notifications) {
                    NotificationsViewerView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.notifications)
            }

            if let featureStore = store.spawn(\.eventSettings) {
                viewerTab(.settings) {
                    EventSettingsView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.settings)
            }

            if let featureStore = store.spawn(\.eventWorkspace) {
                viewerTab(.workspace, badgeValue: featureStore.changeCount) {
                    EventWorkspaceView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.workspace)
            }

            if let featureStore = store.spawn(\.eventInfoViewer) {
                viewerTab(.about) {
                    EventInfoViewerView(
                        store: featureStore,
                        showsAuthoringControls: store.showsAuthoringControls
                    )
                }
                .tag(EventViewer.EventFeature.about)
            }

        }
    }
    #endif

    private var defaultTabView: some View {
        TabView(selection: $store.selectedFeature) {
            ForEach(store.spawn(\.scheduleViewers)) { featureStore in
                let feature = EventViewer.EventFeature.schedule(featureStore.scheduleDivision)
                viewerTab(feature) {
                    ScheduleViewerView(
                        store: featureStore,
                        selectedScheduleID: store.state.$eventViewerState.selectedScheduleID,
                        showsAuthoringControls: store.showsAuthoringControls
                    )
                }
                .tag(feature)
            }

            if let featureStore = store.spawn(\.contributorsViewer) {
                viewerTab(.contributors) {
                    ContributorsViewerView(
                        store: featureStore,
                        showsAuthoringControls: store.showsAuthoringControls
                    )
                }
                .tag(EventViewer.EventFeature.contributors)
            }

            if let featureStore = store.spawn(\.stagesViewer) {
                viewerTab(.stages) {
                    StagesViewerView(
                        store: featureStore,
                        showsAuthoringControls: store.showsAuthoringControls
                    )
                }
                .tag(EventViewer.EventFeature.stages)
            }

            if let featureStore = store.spawn(\.communicationsViewer) {
                viewerTab(.communications) {
                    CommunicationsViewerView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.communications)
            }

            if let featureStore = store.spawn(\.contactInfoViewer) {
                viewerTab(.contactInfo) {
                    ContactInfoViewerView(
                        store: featureStore,
                        showsAuthoringControls: store.showsAuthoringControls
                    )
                }
                .tag(EventViewer.EventFeature.contactInfo)
            }

            if let featureStore = store.spawn(\.locationViewer) {
                viewerTab(.location) {
                    LocationViewerView(
                        store: featureStore,
                        showsAuthoringControls: store.showsAuthoringControls
                    )
                }
                .tag(EventViewer.EventFeature.location)
            }

            if let featureStore = store.spawn(\.siteMapViewer) {
                viewerTab(.siteMap) {
                    SiteMapViewerView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.siteMap)
            }

            if let featureStore = store.spawn(\.postersViewer) {
                viewerTab(.posters) {
                    PostersViewerView(
                        store: featureStore,
                        showsAuthoringControls: store.showsAuthoringControls
                    )
                }
                .tag(EventViewer.EventFeature.posters)
            }

            if let featureStore = store.spawn(\.notificationsViewer) {
                viewerTab(.notifications) {
                    NotificationsViewerView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.notifications)
            }

            if let featureStore = store.spawn(\.eventSettings) {
                viewerTab(.settings) {
                    EventSettingsView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.settings)
            }

            if let featureStore = store.spawn(\.eventWorkspace) {
                viewerTab(.workspace, badgeValue: featureStore.changeCount) {
                    EventWorkspaceView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.workspace)
            }

            if let featureStore = store.spawn(\.eventInfoViewer) {
                viewerTab(.about) {
                    EventInfoViewerView(
                        store: featureStore,
                        showsAuthoringControls: store.showsAuthoringControls
                    )
                }
                .tag(EventViewer.EventFeature.about)
            }

            if store.installedFeatures.contains(.search) {
                viewerTab(.search) {
                    EventSearchView(store: store.spawn(\.eventSearch))
                }
                .tag(EventViewer.EventFeature.search)
            }
        }
    }

    private func viewerTab<Content: View>(
        _ feature: EventViewer.EventFeature,
        badgeValue: Int? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationStack {
            content()
                .toolbar {
                    if feature == .about {
                        ToolbarItem(placement: .cancellationAction) {
                            Button {
                                store.send(.closeButtonTapped)
                            } label: {
                                Label("Close", systemImage: "xmark")
                                    .labelStyle(.iconOnly)
                            }
                        }
                    }
                }
        }
            .tabItem {
                Label(feature.title, systemImage: feature.systemImage)
            }
            .badge(badgeValue ?? 0)
    }

}

private extension EventViewer.State {
    mutating func enterAuthoringEntry(_ entry: EventViewer.EditorEntry) {
        switch entry {
        case let .feature(feature):
            selectAuthoringFeature(feature)

        case let .intent(intent):
            handleEditingIntent(intent)

        case let .target(target):
            navigate(to: target)
        }
    }

    mutating func selectAuthoringFeature(_ feature: EventViewer.EventFeature) {
        guard installedFeatures.contains(feature) else { return }
        selectedFeature = feature
        switch feature {
        case .settings:
            if eventSettings == nil {
                eventSettings = Spawn(EventSettings.State(eventID: eventID))
            }

        case .workspace:
            if eventWorkspace == nil {
                eventWorkspace = eventWorkspaceSpawn(eventID: eventID)
            }

        case .about,
             .communications,
             .contactInfo,
             .contributors,
             .location,
             .notifications,
             .posters,
             .schedule,
             .search,
             .siteMap,
             .stages:
            break
        }
    }
}

private extension EventEditingIntent {
    var eventID: OMERecord.Event.ID {
        switch self {
        case let .addPerformance(eventID, _, _),
             let .addPosters(eventID),
             let .addSchedule(eventID),
             let .copyStagesFromEvent(eventID),
             let .createContributor(eventID),
             let .createStage(eventID),
             let .deletePerformance(eventID, _),
             let .editContactInfo(eventID),
             let .editContributor(eventID, _),
             let .editEventInfo(eventID),
             let .editEventPolicies(eventID),
             let .editLocation(eventID),
             let .editPerformance(eventID, _),
             let .editReportingLink(eventID),
             let .editStage(eventID, _),
             let .eventSettings(eventID),
             let .eventWorkspace(eventID):
            return eventID

        case let .deletePoster(posterID),
             let .editPoster(posterID):
            return OMERecord.Event.ID(
                organizerID: posterID.organizerID,
                eventID: posterID.eventID
            )
        }
    }
}

struct ViewerPlaceholderView: View {
    let title: String
    let systemImage: String
    let description: LocalizedStringKey

    var body: some View {
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description: Text(description)
        )
        .navigationTitle(title)
    }
}

#Preview {
    EventViewerView(
        store: Store(
            initialState: EventViewer.State(
                eventID: .init(
                    organizerID: OMERecord.Organizer.ID("did:web:example.com")!,
                    eventID: .init("preview")
                )
            )
        ) {
            EventViewer()
        }
    )
}
