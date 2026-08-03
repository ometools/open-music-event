import ComposableArchitecture2
import ComposableAuthoring
import ComposableWorkspace
import Dependencies
import ErrorHandling
import IssueReporting
import Sharing
import OpenMusicEventDatabase
import OpenMusicEventEditors
import OpenMusicEventAuthentication
import OpenMusicEventComponents
import OpenMusicEventSourceEditing
import OpenMusicEventViewers
import SQLiteData
import SourceEditing
import SwiftUI
import SwiftUITabFeatures
import Tagged

#if !SKIP && !os(Android)
import CoreImage
import CoreImage.CIFilterBuiltins
#endif

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
    static var liveValue: SharedReader<TimeZone> {
        SharedReader(value: .current)
    }

    static var testValue: SharedReader<TimeZone> {
        SharedReader(value: TimeZone(secondsFromGMT: 0)!)
    }
}

extension DependencyValues {
    var defaultEventID: OMERecord.Event.ID {
        get { self[DefaultEventIDKey.self] }
        set { self[DefaultEventIDKey.self] = newValue }
    }

    var defaultEventTimeZone: SharedReader<TimeZone> {
        get { self[DefaultEventTimeZoneKey.self] }
        set { self[DefaultEventTimeZoneKey.self] = newValue }
    }
}

extension OMERecord.Event {
  static var defaultEvent: some SelectStatementOf<OMERecord.Event> {
    @Dependency(\.defaultEventID) var defaultEventID
    return Self.where { $0.id.eq(defaultEventID) }
  }
}

extension OpenMusicEventViewers.EventFeature {
    static func defaultFeatures(authoringAccess: AuthoringAccess) -> [Self] {
        let authoringFeatures = authoringAccess.canEditContent ? editorFeatures : []
        return defaultReadOnlyFeatures.filter { $0 != .search && $0 != .about }
            + authoringFeatures
            + [.search, .about]
    }

    static func features(
        eventID: OMERecord.Event.ID,
        authoringAccess: AuthoringAccess
    ) -> [Self] {
        @Dependency(\.defaultDatabase) var database
        let stages = (try? database.read { db in
            try ScheduleViewer.stagesQuery(eventID: eventID).fetchAll(db)
        }) ?? []
        return features(
            scheduleDivisions: ScheduleViewer.scheduleDivisions(stages: stages),
            authoringAccess: authoringAccess
        )
    }

    static func features(
        scheduleDivisions: [ScheduleDivision],
        authoringAccess: AuthoringAccess
    ) -> [Self] {
        let divisions = scheduleDivisions.isEmpty ? [.schedule] : scheduleDivisions
        return divisions.map(Self.schedule) + defaultFeatures(authoringAccess: authoringAccess).filter {
            $0.scheduleDivision == nil
        }
    }
}

@Feature
public struct EventViewer {
    public init() {}

    public typealias EventFeature = OpenMusicEventViewers.EventFeature

    public enum ScheduleLaunchAction: Equatable, Sendable {
        case jumpToCurrentTime
    }

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.date.now) var now
    @Dependency(\.getSelectedOAuthSessionID) var getSelectedOAuthSessionID
    @Dependency(\.sourceDataRefresh) var sourceDataRefresh
    @Dependency(\.uuid) var uuid
    @FeatureEnvironment(WorkspaceContext<SourceWorkspaceDatabase, SourcePatch>.self)
    var workspace
    @StoreTaskID var sourceDataRefreshTask

    public struct State: Identifiable, OpenMusicEventWorkspaceContentState {
        public init(eventID: OMERecord.Event.ID) {
            let authoringGrant = Self.authoringGrant()
            self.init(
                eventID: eventID,
                authoringGrant: authoringGrant,
                features: EventFeature.features(
                    eventID: eventID,
                    authoringAccess: authoringGrant.wrappedValue?.access ?? .attendee
                )
            )
        }

        public init(
            eventID: OMERecord.Event.ID,
            authoringGrant: SharedReader<AuthoringGrant?>,
            features: [EventFeature],
            pendingAuthoringEntry: EditorEntry? = nil,
            pendingScheduleLaunchAction: ScheduleLaunchAction? = nil
        ) {
            self._authoringGrant = authoringGrant
            self.eventID = eventID
            self._event = FetchOne(
                OMERecord.Event.where { $0.id.eq(eventID) }
            )
            self.eventViewerState = EventViewerState(id: eventID)
            self._persistedEventViewerState = FetchOne(
                wrappedValue: nil,
                EventViewerState.none
            )
            self._stages = FetchAll(ScheduleViewer.stagesQuery(eventID: eventID))
            self._reactions = FetchAll(
                PerformanceReaction.forEvent(eventID: eventID)
            )
            self._reactionUsage = FetchAll(
                PerformanceReactionEmojiUsage.ranked
            )
            self.installedFeatures = features
            self.selectedFeature = features.first ?? .schedule(.schedule)
            self.eventSearch = Spawn(EventSearch.State(eventID: eventID))
            self.pendingAuthoringEntry = pendingAuthoringEntry
            self.pendingScheduleLaunchAction = pendingScheduleLaunchAction
            self.installFeatureStores(features)
        }

        private mutating func installFeatureStores(_ features: [EventFeature]) {
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
            self.eventWorkspace = existingEventWorkspace
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
                        break
                    case .search:
                        self.eventSearch = existingEventSearch
                    case .about:
                        self.eventInfoViewer = existingEventInfoViewer
                            ?? Spawn(EventInfoViewer.State(eventID: eventID))
//                    case .share:
//                        break
                    }
                }
            }
        }

        mutating func reloadFeaturesForAuthoringAccess(
            preserving selectedFeature: EventFeature? = nil
        ) {
            let selectedFeature = selectedFeature ?? self.selectedFeature
            let features = withEventDependencies {
                EventFeature.features(
                    eventID: eventID,
                    authoringAccess: authoringAccess
                )
            }
            self.installedFeatures = features
            self.selectedFeature = features.contains(selectedFeature)
                ? selectedFeature
                : features.first ?? .schedule(.schedule)
            self.installFeatureStores(features)
        }

        public static func route(
            eventID: OMERecord.Event.ID,
            target: EventTarget?,
            pendingScheduleLaunchAction: ScheduleLaunchAction? = nil
        ) -> Self {
            let authoringGrant = Self.authoringGrant()
            let access = authoringGrant.wrappedValue?.access ?? .attendee
            var state = Self(
                eventID: eventID,
                authoringGrant: authoringGrant,
                features: EventFeature.features(
                    eventID: eventID,
                    authoringAccess: access
                ),
                pendingScheduleLaunchAction: pendingScheduleLaunchAction
            )
            if let target, target.eventFeature.isEditorFeature, !state.showsAuthoringControls {
                state.pendingAuthoringEntry = .target(target)
            } else {
                state.navigate(to: target)
            }
            return state
        }

        @SharedReader public var authoringGrant: AuthoringGrant?
        @Trigger public var authoringAuthorizationInvalidated
        @Trigger<WorkspaceProposal> public var workspaceProposalRecorded
        @Trigger public var workspaceSourcePrepared
        public let eventID: OMERecord.Event.ID
        @FetchOne public var event: OMERecord.Event?
        public var eventViewerState: EventViewerState
        @FetchOne var persistedEventViewerState: EventViewerState?
        @FetchAll public var stages: [OMERecord.Stage]
        @FetchAll public var reactions: [PerformanceReaction]
        @FetchAll public var reactionUsage: [PerformanceReactionEmojiUsage]
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
        public var eventWorkspace: EventWorkspace.State?
        public var account = Spawn(Account.State())
        public var eventSearch: Spawn<EventSearch>
        public var eventInfoViewer: Spawn<EventInfoViewer>?

        public var destination: Destination.State?
        public var pendingAuthoringEntry: EditorEntry?
        public var pendingScheduleLaunchAction: ScheduleLaunchAction?

        public var id: OMERecord.Event.ID { eventID }

        public var eventTimeZone: TimeZone {
            event?.timeZone ?? .current
        }

        var eventTimeZoneReader: SharedReader<TimeZone> {
            $event.sharedReader.read { $0?.timeZone ?? .current }
        }

        public var authoringAccess: AuthoringAccess {
            authoringGrant?.access ?? .attendee
        }

        public var showsAuthoringControls: Bool {
            authoringAccess.canEditContent
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
                self.destination = .performanceForm(editPerformance)

            case let .addSchedule(eventID):
                guard eventID == self.eventID else { return }
                self.destination = withEventDependencies {
                    .scheduleForm(editScheduleState())
                }

            case let .addPosters(eventID):
                guard eventID == self.eventID else { return }
                self.selectedFeature = .posters

            case let .copyStagesFromEvent(eventID):
                guard eventID == self.eventID else { return }
                self.selectedFeature = .stages
                self.destination = withEventDependencies {
                    .copyStagesFromEvent(CopyStagesFromEvent.State(eventID: eventID))
                }

            case let .createContributor(eventID):
                guard eventID == self.eventID else { return }
                self.destination = withEventDependencies {
                    .contributorForm(EditContributor.State(eventID: eventID))
                }

            case let .createStage(eventID):
                guard eventID == self.eventID else { return }
                self.destination = withEventDependencies {
                    .stageForm(EditStage.State(eventID: eventID))
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
                    .contactInfoForm(EditContactInfo.State(eventID: eventID))
                }

            case let .editContributor(eventID, contributorID):
                guard eventID == self.eventID else { return }
                self.destination = withEventDependencies {
                    .contributorForm(
                        EditContributor.State(
                            contributorID: contributorID,
                            eventID: eventID
                        )
                    )
                }

            case let .eventWorkspace(eventID):
                guard eventID == self.eventID else { return }
                self.selectedFeature = .workspace

            case let .editEventInfo(eventID):
                guard eventID == self.eventID else { return }
                self.destination = withEventDependencies {
                    .eventInfoForm(EditEventInfo.State(eventID: eventID))
                }

            case let .editEventPolicies(eventID):
                guard eventID == self.eventID else { return }
                self.destination = withEventDependencies {
                    .eventPoliciesForm(EditEventPolicies.State(eventID: eventID))
                }

            case let .editLocation(eventID):
                guard eventID == self.eventID else { return }
                self.destination = withEventDependencies {
                    .locationForm(EditLocation.State(eventID: eventID))
                }

            case let .editPerformance(eventID, performanceID):
                guard eventID == self.eventID else { return }
                guard let editPerformance = withEventDependencies({
                    editPerformanceState(performanceID: performanceID)
                }) else { return }
                self.destination = .performanceForm(editPerformance)

            case let .editStage(eventID, stageID):
                guard eventID == self.eventID else { return }
                self.destination = withEventDependencies {
                    .stageForm(
                        EditStage.State(
                            stageID: stageID,
                            eventID: eventID
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
                    var schedules = try ScheduleViewer.schedulesQuery(eventID: eventID).fetchAll(db)
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
                    if schedule == nil,
                       let insertedSchedule = try Self.insertSingletonSchedule(
                           event: event,
                           eventID: eventID,
                           in: db
                       ) {
                        schedules.append(insertedSchedule)
                        schedule = insertedSchedule
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
                        schedules: schedules,
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
                        schedules: schedules,
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
            let eventTimeZone = self.eventTimeZoneReader
            return withDependencies {
                $0.defaultEventID = eventID
                $0.defaultEventTimeZone = eventTimeZone
            } operation: {
                operation()
            }
        }

        private static func authoringGrant() -> SharedReader<AuthoringGrant?> {
            @Dependency(ComposableAuthoring.AuthoringContext<AuthoringGrant>.self)
            var authoring
            return authoring.grant
        }
    }

    public enum Action {
        case closeButtonTapped
        case destination(Destination.Action)
        case eventSearch(EventSearch.Action)
        case eventWorkspace(EventWorkspace.Action)
        case reactionButtonTapped(OMERecord.Performance.ID, PerformanceReaction.Emoji)
    }

    public enum EditorEntry: Equatable, Sendable {
        case feature(EventFeature)
        case intent(EventEditingIntent)
        case target(EventTarget)
    }

    @Feature
    public enum Destination {
        case contactInfoForm(EditContactInfo)
        case contributorForm(EditContributor)
        case copyStagesFromEvent(CopyStagesFromEvent)
        case eventInfoForm(EditEventInfo)
        case eventPoliciesForm(EditEventPolicies)
        case locationForm(EditLocation)
        case performanceForm(EditPerformance)
        case scheduleForm(EditSchedule)
        case stageForm(EditStage)
    }

    private func enterOrRequestAuthoring(_ entry: EditorEntry, state: inout State) {
        guard !state.showsAuthoringControls else {
            state.pendingAuthoringEntry = nil
            store.withDependencies {
                state.enterAuthoringEntry(entry)
            }
            return
        }
        state.pendingAuthoringEntry = entry
        store.addTask {
            let task = try store.post(key: AuthoringRequested.self, value: ())
            await task?.value
        }
    }

    public var body: some Feature {
//        let _ = Self._logChanges()
        Features {
            AnyFeature(
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

                    case .eventWorkspace:
                        break

                    case let .reactionButtonTapped(performanceID, emoji):
                        let id = uuid()
                        let date = now
                        let userDID = getSelectedOAuthSessionID()?.rawValue
                        store.addTask {
                            do {
                                try await database.write { db in
                                    try PerformanceReaction.toggle(
                                        performanceID: performanceID,
                                        emoji: emoji,
                                        id: id,
                                        date: date,
                                        userDID: userDID,
                                        in: db
                                    )
                                }
                            } catch {
                                reportIssue(error)
                            }
                        }

                    }
                }
                .onChange(of: store.authoringGrant) { oldGrant, newGrant, state in
                    let oldValue = oldGrant?.access ?? .attendee
                    let newValue = newGrant?.access ?? .attendee
                    guard oldValue != newValue else { return }
                    state.reloadFeaturesForAuthoringAccess()
                    guard newValue.canEditContent,
                          let pendingAuthoringEntry = state.pendingAuthoringEntry
                    else { return }
                    enterOrRequestAuthoring(pendingAuthoringEntry, state: &state)
                }
                .onChange(of: store.selectedFeature) { _, feature, state in
                    guard feature.isEditorFeature else { return }
                    enterOrRequestAuthoring(.feature(feature), state: &state)
                }
                .onChange(of: store.stages) { _, _, state in
                    state.reloadFeaturesForAuthoringAccess()
                }
                .onChange(of: store.persistedEventViewerState) {
                    _, persistedState, state in
                    guard let persistedState,
                          persistedState != state.eventViewerState
                    else { return }
                    state.eventViewerState = persistedState
                }
                .onChange(of: store.eventViewerState) {
                    oldViewerState, viewerState, state in
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
                    state.reloadFeaturesForAuthoringAccess()
                    let eventID = state.eventID
                    let persistedEventViewerState = state.$persistedEventViewerState
                    store.addTask {
                        try await persistedEventViewerState.load(
                            EventViewerState.where { $0.id.eq(eventID) }
                        )
                        .task
                    }
                }
                .onTrigger(store.workspaceSourcePrepared) { state in
                    guard state.showsAuthoringControls,
                          state.eventWorkspace == nil,
                          let source = workspace.source.wrappedValue
                    else { return }
                    state.eventWorkspace = withDependencies {
                        $0.defaultDatabase = source.database
                    } operation: {
                        EventWorkspace.State(eventID: state.eventID)
                    }
                }
                .onTrigger(store.workspaceProposalRecorded) { proposal, state in
                    guard state.eventWorkspace != nil else { return }
                    state.eventWorkspace?.reviews.pendingCreatedReviewID = proposal.id.rawValue
                    store.addTask {
                        let refresh = try store.send(
                            .eventWorkspace(.reviews(.refreshButtonTapped))
                        )
                        await refresh?.value
                    }
                }
            )

            AnyFeature(
                EmptyFeature<State, Action>()
                    .onEvent(ScheduleDivisionRequested.self) { division, state in
                        let feature = EventFeature.schedule(division)
                        guard state.installedFeatures.contains(feature) else { return }
                        state.selectedFeature = feature
                    }
                    .onEvent(SourceDataRefreshRequested.self) { request, state in
                        guard request.eventID == state.eventID else { return }
                        if workspace.source.wrappedValue != nil {
                            store.addTask(id: sourceDataRefreshTask) {
                                let reconciliation = try store.post(
                                    key: WorkspaceReconciliationRequested.self,
                                    value: ()
                                )
                                await reconciliation?.value
                            }
                            return
                        }
                        store.addTask(id: sourceDataRefreshTask) {
                            let result: Void? = await store.withErrorHandling(
                                fallbackMessage: .sourceDataRefreshFailed,
                                operation: .sourceDataRefresh
                            ) {
                                try await sourceDataRefresh.refresh(request.sourceBaselineID)
                            }
                            _ = result
                        }
                    }
            )

            AnyFeature(
                Features {
                    EmptyFeature<State, Action>().forEach(\.scheduleViewers) {
                        ScheduleViewer()
                    }
                    EmptyFeature<State, Action>().ifLet(\.contributorsViewer) {
                        ContributorsViewer()
                    }
                    EmptyFeature<State, Action>().ifLet(\.stagesViewer) {
                        StagesViewer()
                    }
                    EmptyFeature<State, Action>().spawn(\.eventSearch) {
                        EventSearch()
                    }
                    EmptyFeature<State, Action>().ifLet(\.communicationsViewer) {
                        CommunicationsViewer()
                    }
                    EmptyFeature<State, Action>().ifLet(\.contactInfoViewer) {
                        ContactInfoViewer()
                    }
                    EmptyFeature<State, Action>().ifLet(\.locationViewer) {
                        LocationViewer()
                    }
                    EmptyFeature<State, Action>().ifLet(\.siteMapViewer) {
                        SiteMapViewer()
                    }
                }
            )

            AnyFeature(
                Features {
                    EmptyFeature<State, Action>().ifLet(\.postersViewer) {
                        PostersViewer()
                    }
                    EmptyFeature<State, Action>().ifLet(\.notificationsViewer) {
                        NotificationsViewer()
                    }
                    EmptyFeature<State, Action>().ifLet(\.eventSettings) {
                        EventSettings()
                    }
                    EmptyFeature<State, Action>().ifLet(
                        \.eventWorkspace,
                        action: \.eventWorkspace
                    ) {
                        EventWorkspace()
                    }
                    EmptyFeature<State, Action>().spawn(\.account) {
                        Account()
                    }
                    EmptyFeature<State, Action>().ifLet(\.eventInfoViewer) {
                        EventInfoViewer()
                    }
                }
                .onEvent(NavigationRequested.self) { request, state in
                    guard case let .event(eventID, target) = request,
                          eventID == state.eventID
                    else { return }
                    if let target, target.eventFeature.isEditorFeature {
                        enterOrRequestAuthoring(.target(target), state: &state)
                    } else {
                        state.navigate(to: target)
                    }
                }
                .onEvent(EventEditingRequested.self) { intent, state in
                    guard intent.eventID == state.eventID else { return }
                    enterOrRequestAuthoring(.intent(intent), state: &state)
                }
            )
        }
        .ifLet(\.destination, action: \.destination) {
            Destination.body
                .dependency(\.defaultEventID, store.eventID)
                .dependency(\.defaultEventTimeZone, store.eventTimeZoneReader)
        }
        .dependency(\.defaultEventID, store.eventID)
        .dependency(\.defaultEventTimeZone, store.eventTimeZoneReader)
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
            destinationID("performanceForm", store.eventID, store.performanceID)
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
    public init(
        store: StoreOf<EventViewer>,
        authoringAdmission: ComposableAuthoring.AuthoringAdmission? = nil
    ) {
        self.store = store
        self.authoringAdmission = authoringAdmission
        self.accountStore = store.spawn(\.account)
    }

    @Bindable var store: StoreOf<EventViewer>
    @Bindable var accountStore: StoreOf<Account>
    let authoringAdmission: ComposableAuthoring.AuthoringAdmission?

    public var body: some View {
        tabContent
            .environment(\.needsStageDisambiguation, store.needsStageDisambiguation)
            .environment(\.performanceReactionMenuContext, reactionMenuContext)
            .sheet(item: $store.scope(\.destination, action: \.destination)) { _ in
                if let destinationStore = store.scope(\.destination, action: \.destination) {
                    NavigationStack {
                        destinationContent(EventViewer.Destination.switch(store: destinationStore))
                    }
                    .environment(\.needsStageDisambiguation, store.needsStageDisambiguation)
                }
            }
            .sheet(
                item: $accountStore.presentation,
                onDismiss: { accountStore.send(.accountPresentationDismissed) }
            ) { _ in
                AccountPresentationView(store: accountStore)
            }
    }

    var reactionMenuContext: PerformanceReactionMenuContext {
        PerformanceReactionMenuContext(
            reactions: store.reactions,
            usage: store.reactionUsage,
            toggle: { performanceID, emoji in
                store.send(.reactionButtonTapped(performanceID, emoji))
            }
        )
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
        case let .scheduleForm(formStore):
            EditScheduleView(store: formStore)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        #if os(Android)
        TabFeaturesViewer(
            store: store,
            authoringAdmission: authoringAdmission
        )
        #elseif os(iOS)
        if #available(iOS 18.0, *) {
            TabFeaturesViewer(
                store: store,
                authoringAdmission: authoringAdmission
            )
        } else {
            legacyiOSTabView
        }
        #elseif os(macOS)
        if #available(macOS 15.0, *) {
            TabFeaturesViewer(
                store: store,
                authoringAdmission: authoringAdmission
            )
        } else {
            defaultTabView
        }
        #else
        defaultTabView
        #endif
    }

    #if !os(Android)
    @available(iOS 18.0, macOS 15.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *)
    #endif
    struct TabFeaturesViewer: View {
        @Bindable var store: StoreOf<EventViewer>
        let authoringAdmission: ComposableAuthoring.AuthoringAdmission?
        @State var tabLayout = TabFeatureLayout()

        var body: some View {
            let accountStore = store.spawn(\.account)

            TabFeaturesView(
                selection: $store.selectedFeature,
                layout: $tabLayout
            ) {
                if store.installedFeatures.contains(.search) {
                    TabFeature(.search, role: .search) {
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
                            selectedScheduleID: $store.eventViewerState.selectedScheduleID,
                            pendingScheduleLaunchAction: $store.pendingScheduleLaunchAction,
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
                        EventSettingsView(
                            store: featureStore,
                            authoringAccess: store.authoringAccess,
                            authoringAdmission: authoringAdmission
                        )
                    }
                }

                if let featureStore = store.scope(\.eventWorkspace, action: \.eventWorkspace) {
                    TabFeature(
                        .workspace,
                        title: EventViewer.EventFeature.workspace.title,
                        systemImage: EventViewer.EventFeature.workspace.systemImage,
                        labelTint: EventViewer.EventFeature.workspace.labelTint,
                        badgeValue: featureStore.changeCount,
                        navigation: .stack
                    ) {
                        EventWorkspaceView(
                            store: featureStore,
                            accountStore: accountStore,
                            authoringAccess: store.authoringAccess
                        )
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

//                if store.installedFeatures.contains(.share) {
//                    TabFeature(
//                        .share,
//                        title: EventViewer.EventFeature.share.title,
//                        systemImage: EventViewer.EventFeature.share.systemImage,
//                        labelTint: EventViewer.EventFeature.share.labelTint,
//                        navigation: .stack
//                    ) {
//                        TestFlightShareView()
//                    }
//                    .allowedOnTabBar(false)
//                }

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
                    Button("Exit", systemImage: "xmark") {
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
                        selectedScheduleID: $store.eventViewerState.selectedScheduleID,
                        pendingScheduleLaunchAction: $store.pendingScheduleLaunchAction,
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
                    EventSettingsView(
                        store: featureStore,
                        authoringAccess: store.authoringAccess,
                        authoringAdmission: authoringAdmission
                    )
                }
                .tag(EventViewer.EventFeature.settings)
            }

            if let featureStore = store.scope(\.eventWorkspace, action: \.eventWorkspace) {
                viewerTab(.workspace, badgeValue: featureStore.changeCount) {
                    EventWorkspaceView(
                        store: featureStore,
                        accountStore: accountStore,
                        authoringAccess: store.authoringAccess
                    )
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
                        selectedScheduleID: $store.eventViewerState.selectedScheduleID,
                        pendingScheduleLaunchAction: $store.pendingScheduleLaunchAction,
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
                    EventSettingsView(
                        store: featureStore,
                        authoringAccess: store.authoringAccess,
                        authoringAdmission: authoringAdmission
                    )
                }
                .tag(EventViewer.EventFeature.settings)
            }

            if let featureStore = store.scope(\.eventWorkspace, action: \.eventWorkspace) {
                viewerTab(.workspace, badgeValue: featureStore.changeCount) {
                    EventWorkspaceView(
                        store: featureStore,
                        accountStore: accountStore,
                        authoringAccess: store.authoringAccess
                    )
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
            break

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
//             .share,
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

    init(
        title: String,
        systemImage: String,
        description: LocalizedStringKey
    ) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }

    var body: some View {
        ContentUnavailableView {
            Label(
                title,
                mappedSystemImage: systemImage
            )
        } description: {
            Text(description)
        }
        .navigationTitle(title)
    }
}

struct TestFlightShareView: View {
    static let testFlightURL = URL(string: "https://testflight.apple.com/join/s8N5G6jf")!

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                #if !SKIP && !os(Android)
                Image(decorative: qrCode, scale: 1, orientation: .up)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 280)
                #endif

                Text("Scan to join the TestFlight")
                    .font(.headline)

                Link(Self.testFlightURL.absoluteString, destination: Self.testFlightURL)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
        .navigationTitle("Share")
    }

    #if !SKIP && !os(Android)
    var qrCode: CGImage {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(Self.testFlightURL.absoluteString.utf8)
        filter.correctionLevel = "H"
        return CIContext().createCGImage(
            filter.outputImage!,
            from: filter.outputImage!.extent
        )!
    }
    #endif
}

#if !os(Android)
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
#endif
