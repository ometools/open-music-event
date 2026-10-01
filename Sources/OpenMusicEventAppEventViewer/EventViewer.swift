import OpenMusicEventLexicon
import ComposableArchitecture2
import ComposableAuthoring
import ComposableNotifications
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

public struct EventViewerDismissalRequested: FeatureEventKey {
    public typealias Value = Event.ID

    public init() {}
}

struct EventViewerContext: Sendable {
    let eventID: Event.ID
}

extension EventViewerContext: DependencyKey {
    static var liveValue: Self {
        Self(
            eventID: unimplemented(
                "EventViewerContext.eventID",
                placeholder: Event.ID("at://did:web:example.com/events.openmusic.event/3jzfcijpj2z2a")!
            )
        )
    }

    static var testValue: Self {
        Self(
            eventID: unimplemented(
                "EventViewerContext.eventID",
                placeholder: Event.ID("at://did:web:example.com/events.openmusic.event/3jzfcijpj2z2a")!
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
    public var defaultEventID: Event.ID {
        get { self[EventViewerContext.self].eventID }
        set { self[EventViewerContext.self] = EventViewerContext(eventID: newValue) }
    }

    var defaultEventTimeZone: SharedReader<TimeZone> {
        get { self[DefaultEventTimeZoneKey.self] }
        set { self[DefaultEventTimeZoneKey.self] = newValue }
    }
}

public extension SharedReaderKey
where Self == InMemoryKey<AuthoringGrant?>.Default {
    static var defaultAuthoringGrant: Self {
        @Dependency(\.defaultEventID) var eventID
        return Self[
            .inMemory(
                "open-music-event.authoring-grant." + eventID.description
            ),
            default: nil
        ]
    }
}

extension SharedReader where Value == AuthoringGrant? {
    static func authoringGrant(for eventID: Event.ID) -> Self {
        withDependencies {
            $0.defaultEventID = eventID
        } operation: {
            Self(.defaultAuthoringGrant)
        }
    }
}

extension Event {
  static var defaultEvent: some SelectStatementOf<Event> {
    @Dependency(EventViewerContext.self) var eventViewer
    return Self.where { $0.id.eq(eventViewer.eventID) }
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
        eventID: Event.ID,
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
    @Dependency(\.uuid) var uuid
    @FeatureEnvironment(WorkspaceContext<SourceWorkspaceResource>.self)
    var workspace

    public struct State: Identifiable, OpenMusicEventWorkspaceContentState {
        public init(eventID: Event.ID) {
            let authoringGrant = SharedReader<AuthoringGrant?>.authoringGrant(for: eventID)
            self.init(
                eventID: eventID,
                features: EventFeature.features(
                    eventID: eventID,
                    authoringAccess: authoringGrant.wrappedValue?.access ?? .attendee
                )
            )
        }

        public init(
            eventID: Event.ID,
            features: [EventFeature],
            pendingAuthoringEntry: EditorEntry? = nil,
            pendingScheduleLaunchAction: ScheduleLaunchAction? = nil
        ) {
            self._authoringGrant = .authoringGrant(for: eventID)
            self.eventID = eventID
            self._event = FetchOne(
                Event.where { $0.id.eq(eventID) }
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
                            ?? CommunicationsViewer.State(eventID: eventID)
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
                            ?? Spawn(PostersViewer.State())
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
            eventID: Event.ID,
            target: EventTarget?,
            pendingScheduleLaunchAction: ScheduleLaunchAction? = nil
        ) -> Self {
            let authoringGrant = SharedReader<AuthoringGrant?>.authoringGrant(for: eventID)
            let access = authoringGrant.wrappedValue?.access ?? .attendee
            var state = Self(
                eventID: eventID,
                features: EventFeature.features(
                    eventID: eventID,
                    authoringAccess: access
                ),
                pendingScheduleLaunchAction: pendingScheduleLaunchAction
            )
            if let target, target.eventFeature.isEditorFeature,
               !state.authoringAccess.canEditContent {
                state.pendingAuthoringEntry = .target(target)
            } else {
                state.navigate(to: target)
            }
            return state
        }

        @SharedReader
        public var authoringGrant: AuthoringGrant?
        @Trigger public var authoringAuthorizationInvalidated
        @Trigger<WorkspaceFailure> public var workspaceBaselineSelectionFailed
        @Trigger<WorkspaceFailure> public var workspaceChangesPublicationFailed
        @Trigger<WorkspaceBranchReference> public var workspaceChangesPublished
        @Trigger public var workspaceChangesPublishing
        @Trigger<WorkspaceFailure> public var workspaceProposalPublicationFailed
        @Trigger public var workspaceProposalPublishing
        @Trigger<WorkspaceProposal> public var workspaceProposalRecorded
        @Trigger public var workspaceSourcePrepared
        public let eventID: Event.ID
        @FetchOne public var event: Event?
        public var eventViewerState: EventViewerState
        @FetchOne var persistedEventViewerState: EventViewerState?
        @FetchAll public var stages: [EventPlace]
        @FetchAll public var reactions: [PerformanceReaction]
        @FetchAll public var reactionUsage: [PerformanceReactionEmojiUsage]
        public var installedFeatures: [EventFeature]
        public var selectedFeature: EventFeature

        public var scheduleViewers: [Spawn<ScheduleViewer>] = []
        public var contributorsViewer: Spawn<ContributorsViewer>?
        public var stagesViewer: Spawn<StagesViewer>?
        public var communicationsViewer: CommunicationsViewer.State?
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
        public var isEditing = false
        public var pendingAuthoringEntry: EditorEntry?
        public var pendingScheduleLaunchAction: ScheduleLaunchAction?

        public var id: Event.ID { eventID }

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
            isEditing
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
            case let .channel(channelID):
                let eventID = self.eventID
                if self.communicationsViewer == nil {
                    self.communicationsViewer = withEventDependencies {
                        CommunicationsViewer.State(eventID: eventID)
                    }
                }
                let destination: CommunicationsViewer.Destination.State = withEventDependencies {
                    .channelDetail(
                        CommunicationChannelDetail.State(
                            channelID: channelID,
                            eventID: eventID
                        )
                    )
                }
                self.communicationsViewer?.destination = destination
            case let .post(channelID, postID):
                let eventID = self.eventID
                if self.communicationsViewer == nil {
                    self.communicationsViewer = withEventDependencies {
                        CommunicationsViewer.State(eventID: eventID)
                    }
                }
                let destination: CommunicationsViewer.Destination.State = withEventDependencies {
                    .channelDetail(
                        CommunicationChannelDetail.State(
                            channelID: channelID,
                            eventID: eventID,
                            destination: .postDetail(
                                CommsPostDetail.State(postID: postID, eventID: eventID)
                            )
                        )
                    )
                }
                self.communicationsViewer?.destination = destination
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
                                contributorID: contributorID
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
                                stageID: stageID
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
                                performanceID: performanceID
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
            scheduleID: Schedule.ID?,
            stageID: EventPlace.ID?
        ) -> EditPerformance.State? {
            @Dependency(\.defaultDatabase) var database

            do {
                return try database.write { db in
                    let event = try Event
                        .where { $0.id.eq(eventID) }
                        .fetchOne(db)
                    var schedules = try ScheduleViewer.schedulesQuery(eventID: eventID).fetchAll(db)
                    var programs = try Program.where { $0.event.eq(eventID) }.fetchAll(db)
                        .filter { event?.programs?.contains($0.id) == true }
                    let stages = try EventPlace.where { $0.event.eq(eventID) }.fetchAll(db)
                    let contributors = try ContributorProfile
                        .all(eventID: eventID, hydration: .none)
                        .fetchAll(db)
                    if programs.isEmpty,
                       event?.programs?.isEmpty != false,
                       event != nil {
                        let stageIDs = stages.compactMap { place -> EventPlace.ID? in
                            guard case .known(.stage(_)) = place.kind else { return nil }
                            return place.id
                        }
                        @Dependency(\.date.now) var now
                        let programID = try ProgramRecordEditing.create(
                            eventID: eventID,
                            title: "Schedule",
                            eventPlaces: stageIDs,
                            createdAt: now,
                            in: db
                        )
                        if let program = try Program.find(programID).fetchOne(db) {
                            programs.append(program)
                        }
                    }
                    guard !programs.isEmpty else { return nil }

                    let resolvedScheduleID = scheduleID.flatMap { scheduleID in
                        schedules.contains { $0.id == scheduleID }
                            ? scheduleID
                            : nil
                    }
                    var schedule = resolvedScheduleID.flatMap { scheduleID in
                        schedules.first { $0.id == scheduleID }
                    } ?? schedules.first
                    if schedule == nil,
                       let insertedSchedule = try Self.insertInitialSchedule(
                           event: event,
                           eventID: eventID,
                           in: db
                       ) {
                        schedules.append(insertedSchedule)
                        schedule = insertedSchedule
                    }
                    guard let schedule else { return nil }
                    let resolvedStageID = stageID.flatMap { stageID in
                        stages.contains { $0.id == stageID }
                            ? stageID
                            : nil
                    } ?? stages.first?.id
                    let initialStartTime = try ProgramItem
                        .where { $0.event.eq(eventID) }
                        .where { $0.schedule.eq(schedule.id) }
                        .fetchAll(db)
                        .filter { $0.eventPlace == resolvedStageID }
                        .compactMap(\.endDate)
                        .max()

                    return EditPerformance.State(
                        eventID: eventID,
                        schedule: schedule,
                        schedules: schedules,
                        programs: programs,
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

        private static func insertInitialSchedule(
            event: Event?,
            eventID: Event.ID,
            in db: Database
        ) throws -> Schedule? {
            guard let event,
                  let start = event.start?.date(in: event.timeZone)
            else { return nil }
            let scheduleDate = LocalDate(start, in: event.timeZone)
            @Dependency(\.date.now) var now
            let scheduleID = try ScheduleRecordEditing.create(
                eventID: eventID,
                date: scheduleDate,
                title: nil,
                createdAt: now,
                in: db
            )
            return try Schedule
                .find(scheduleID)
                .fetchOne(db)
        }

        private func editPerformanceState(
            performanceID: ProgramItem.ID
        ) -> EditPerformance.State? {
            @Dependency(\.defaultDatabase) var database

            do {
                return try database.read { db in
                    let event = try Event.find(eventID).fetchOne(db)
                    let performanceRows = try PerformanceRow.all(eventID: eventID).fetchAll(db)
                    let schedules = try ScheduleViewer.schedulesQuery(eventID: eventID).fetchAll(db)
                    let programs = try Program.where { $0.event.eq(eventID) }.fetchAll(db)
                        .filter { event?.programs?.contains($0.id) == true }
                    let stages = try EventPlace.where { $0.event.eq(eventID) }.fetchAll(db)
                    let contributors = try ContributorProfile
                        .all(eventID: eventID, hydration: .none)
                        .fetchAll(db)
                    guard
                        let row = performanceRows.first(where: { $0.performanceID == performanceID }),
                        let scheduleID = row.performance.schedule,
                        let schedule = schedules.first(where: { $0.id == scheduleID })
                    else { return nil }

                    return EditPerformance.State(
                        eventID: eventID,
                        schedule: schedule,
                        schedules: schedules,
                        programs: programs,
                        stages: stages,
                        timeZone: eventTimeZone,
                        performance: row.performance,
                        contributors: contributors
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
                    try Event
                        .where { $0.id.eq(eventID) }
                        .fetchOne(db)?
                        .start?
                        .date(in: eventTimeZone)
                        .map { LocalDate($0, in: eventTimeZone) }
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

        fileprivate func withEventDependencies<Value>(_ operation: () -> Value) -> Value {
            let eventID = self.eventID
            let eventTimeZone = self.eventTimeZoneReader
            return withDependencies {
                $0[EventViewerContext.self] = EventViewerContext(eventID: eventID)
                $0.defaultEventTimeZone = eventTimeZone
            } operation: {
                operation()
            }
        }
    }

    public enum Action {
        case closeButtonTapped
        case communicationsViewer(CommunicationsViewer.Action)
        case destination(Destination.Action)
        case eventSearch(EventSearch.Action)
        case eventWorkspace(EventWorkspace.Action)
        case reactionButtonTapped(ProgramItem.ID, PerformanceReaction.Emoji)
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
        case locationForm(EditLocation)
        case performanceForm(EditPerformance)
        case scheduleForm(EditSchedule)
        case stageForm(EditStage)
    }

    private func enterOrRequestAuthoring(_ entry: EditorEntry, state: inout State) {
        if case .intent = entry {
            state.isEditing = true
            state.pendingAuthoringEntry = nil
            store.withDependencies {
                state.enterAuthoringEntry(entry)
            }
            return
        }
        guard !state.authoringAccess.canEditContent else {
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

    private func installAuthorizedWorkspace(
        _ grant: AuthoringGrant,
        state: inout State
    ) {
        if state.eventWorkspace?.workspace.id != grant.workspaceID {
            do {
                let sourceWorkspace = try SourceWorkspace(id: grant.workspaceID)
                state.withEventDependencies {
                    state.eventWorkspace = EventWorkspace.State(
                        workspace: sourceWorkspace,
                        eventID: state.eventID,
                        workspaceState: workspace.state
                    )
                }
            } catch {
                reportIssue(error)
                return
            }
        }
        state.reloadFeaturesForAuthoringAccess()
        if let pendingAuthoringEntry = state.pendingAuthoringEntry {
            enterOrRequestAuthoring(pendingAuthoringEntry, state: &state)
        }
    }

    private func installPreparedSource(
        _ source: SourceWorkspaceResource,
        state: inout State
    ) {
        guard state.eventWorkspace?.workspace.id == source.workspace.id else { return }
        precondition(
            source.applicationDatabaseID == ObjectIdentifier(database),
            "A prepared source must use EventViewer's application database."
        )
        state.withEventDependencies {
            state.eventWorkspace?.changes = WorkspaceChanges.State(
                workspace: source.workspace,
                referenceDatabase: source.referenceDatabase
            )
        }
    }

    public var body: some Feature {
//        let _ = Self._logChanges()
        Features {
            AnyFeature(
                Update { state, action in
                    switch action {
                    case .closeButtonTapped:
                        let eventID = state.eventID
                        store.addTask {
                            let dismissal = try store.post(
                                key: EventViewerDismissalRequested.self,
                                value: eventID
                            )
                            await dismissal?.value
                            try store.dismiss()
                        }

                    case .communicationsViewer:
                        break

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
                    if let newGrant, newValue.canEditContent {
                        installAuthorizedWorkspace(newGrant, state: &state)
                    } else if oldValue != newValue {
                        state.reloadFeaturesForAuthoringAccess()
                    }
                }
                .onChange(of: store.selectedFeature) { _, feature, state in
                    guard feature.isEditorFeature else { return }
                    enterOrRequestAuthoring(.feature(feature), state: &state)
                }
                .onChange(of: store.stages) { _, _, state in
                    state.reloadFeaturesForAuthoringAccess()
                }
                .onChange(of: store.persistedEventViewerState) {
                    oldPersistedState, persistedState, state in
                    guard let persistedState else { return }
                    state.eventViewerState.mergePersistedChanges(
                        from: oldPersistedState,
                        to: persistedState
                    )
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
                    if let grant = state.authoringGrant,
                       grant.access.canEditContent
                    {
                        installAuthorizedWorkspace(grant, state: &state)
                    } else {
                        state.reloadFeaturesForAuthoringAccess()
                    }
                    let eventID = state.eventID
                    let persistedEventViewerState = state.$persistedEventViewerState
                    store.addTask {
                        try await persistedEventViewerState.load(
                            EventViewerState.where { $0.id.eq(eventID) }
                        )
                        .task
                    }
                }
                .onChange(
                    of: workspace.session?.source.workspace.id,
                    initial: true
                ) { _, _, state in
                    guard let source = workspace.session?.source else { return }
                    installPreparedSource(source, state: &state)
                }
                .onTrigger(store.workspaceSourcePrepared) { state in
                    guard let source = workspace.session?.source else { return }
                    installPreparedSource(source, state: &state)
                }
                .onChange(
                    of: workspace.state.wrappedValue.baseline?.revision,
                    initial: true
                ) { oldRevision, revision, state in
                    guard oldRevision != revision,
                          let summary = state.eventWorkspace?.changes.$summary
                    else { return }
                    // The reference database is deliberately outside defaultDatabase observation.
                    // A branch revision is its explicit invalidation boundary.
                    store.addTask {
                        try await summary.load()
                    }
                }
                .onTrigger(store.workspaceProposalPublishing) { state in
                    state.eventWorkspace?.changes.proposalDraft?.publicationProgress = .publishing
                }
                .onTrigger(store.workspaceChangesPublishing) { state in
                    state.eventWorkspace?.changes.proposalDraft?.publicationProgress = .publishing
                }
                .onTrigger(store.workspaceChangesPublicationFailed) { failure, state in
                    state.eventWorkspace?.changes.proposalDraft?.publicationProgress = .failed(
                        failure.message
                    )
                }
                .onTrigger(store.workspaceChangesPublished) { _, state in
                    state.eventWorkspace?.changes.proposalDraft = nil
                }
                .onTrigger(store.workspaceProposalPublicationFailed) { failure, state in
                    state.eventWorkspace?.changes.proposalDraft?.publicationProgress = .failed(
                        failure.message
                    )
                }
                .onTrigger(store.workspaceBaselineSelectionFailed) { failure, _ in
                    store.addTask {
                        let _: Void? = await store.withErrorHandling(
                            fallbackMessage: .workspaceBaselineSelectionFailed,
                            operation: .workspaceBaselineSelection
                        ) {
                            throw failure
                        }
                    }
                }
                .onTrigger(store.workspaceProposalRecorded) { proposal, state in
                    guard state.eventWorkspace != nil else { return }
                    state.eventWorkspace?.changes.proposalDraft = nil
                    state.eventWorkspace?.openProposalList(proposal)
                    let targetBranch = proposal.target.branch
                    store.addTask {
                        let reset = try store.post(
                            key: WorkspacePublishedRequested.self,
                            value: targetBranch
                        )
                        await reset?.value
                        let refresh = try store.send(
                            .eventWorkspace(.reviews(.proposalRecorded))
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
                    EmptyFeature<State, Action>().ifLet(\.eventWorkspace) {
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
                .onEvent(EventEditingModeRequested.self) { isEditing, state in
                    state.isEditing = isEditing
                }
            )
        }
        .ifLet(\.destination) {
            Destination.body
                .dependency(EventViewerContext(eventID: store.eventID))
                .dependency(\.defaultEventTimeZone, store.eventTimeZoneReader)
        }
        .dependency(EventViewerContext(eventID: store.eventID))
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
    public init(store: StoreOf<EventViewer>) {
        self.store = store
        self.accountStore = store.spawn(\.account)
    }

    @Bindable var store: StoreOf<EventViewer>
    @Bindable var accountStore: StoreOf<Account>

    public var body: some View {
        tabContent
            .accessibilityIdentifier(
                "view.event.\(store.eventID.rkey?.rawValue ?? store.eventID.description)"
            )
            .environment(\.needsStageDisambiguation, store.needsStageDisambiguation)
            .environment(
                \.eventTimePresentation,
                store.event.map { EventTimePresentation(timeZone: $0.timeZone) }
            )
            .environment(\.performanceReactionMenuContext, reactionMenuContext)
            .sheet(item: $store.scope(\.destination)) { _ in
                if let destinationStore = store.scope(\.destination) {
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
        TabFeaturesViewer(store: store)
        #elseif os(iOS)
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

    #if !os(Android)
    @available(iOS 18.0, macOS 15.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *)
    #endif
    struct TabFeaturesViewer: View {
        @Bindable var store: StoreOf<EventViewer>
        @State var tabLayout = TabFeatureLayout(
            preferredIDs: [
                .init("schedule"),
                .init("schedule:workshop"),
                .init("communications"),
            ]
        )

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

                if let featureStore = store.scope(\.communicationsViewer) {
                    TabFeature(
                        .communications,
                        title: EventViewer.EventFeature.communications.title,
                        systemImage: EventViewer.EventFeature.communications.systemImage,
                        labelTint: EventViewer.EventFeature.communications.labelTint,
                        badgeValue: featureStore.unreadPostCount,
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
                            title: featureStore.featureTitle,
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
                        badgeValue: featureStore.permissions.notificationSetupBadgeValue,
                        navigation: .stack
                    ) {
                        EventSettingsView(store: featureStore, isEditing: store.isEditing)
                    }
                }

                if let featureStore = store.scope(\.eventWorkspace) {
                    TabFeature(
                        .workspace,
                        title: EventViewer.EventFeature.workspace.title,
                        systemImage: EventViewer.EventFeature.workspace.systemImage,
                        labelTint: EventViewer.EventFeature.workspace.labelTint,
                        badgeValue: featureStore.badgeCount,
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
                        EventInfoViewerView(store: featureStore)
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

            if let featureStore = store.scope(\.communicationsViewer) {
                viewerTab(
                    .communications,
                    badgeValue: featureStore.unreadPostCount
                ) {
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
                viewerTab(
                    .settings,
                    badgeValue: featureStore.permissions.notificationSetupBadgeValue
                ) {
                    EventSettingsView(store: featureStore, isEditing: store.isEditing)
                }
                .tag(EventViewer.EventFeature.settings)
            }

            if let featureStore = store.scope(\.eventWorkspace) {
                viewerTab(.workspace, badgeValue: featureStore.badgeCount) {
                    EventWorkspaceView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.workspace)
            }

            if let featureStore = store.spawn(\.eventInfoViewer) {
                viewerTab(.about) {
                    EventInfoViewerView(store: featureStore)
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

            if let featureStore = store.scope(\.communicationsViewer) {
                viewerTab(
                    .communications,
                    badgeValue: featureStore.unreadPostCount
                ) {
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
                viewerTab(
                    .settings,
                    badgeValue: featureStore.permissions.notificationSetupBadgeValue
                ) {
                    EventSettingsView(store: featureStore, isEditing: store.isEditing)
                }
                .tag(EventViewer.EventFeature.settings)
            }

            if let featureStore = store.scope(\.eventWorkspace) {
                viewerTab(.workspace, badgeValue: featureStore.badgeCount) {
                    EventWorkspaceView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.workspace)
            }

            if let featureStore = store.spawn(\.eventInfoViewer) {
                viewerTab(.about) {
                    EventInfoViewerView(store: featureStore)
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
    var eventID: Event.ID {
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
             let .editLocation(eventID),
             let .editPerformance(eventID, _),
             let .editStage(eventID, _),
             let .eventSettings(eventID),
             let .eventWorkspace(eventID):
            return eventID

        }
    }
}

extension UserFacingText {
    static let workspaceBaselineSelectionFailed = Self(
        "Unable to switch Workspace.",
        fallback: "Unable to switch Workspace."
    )
}

extension ErrorOperation {
    static let workspaceBaselineSelection = Self("workspace.baseline.select")
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
                eventID: Event.ID("at://did:web:example.com/events.openmusic.event/3jzfcijpj2z2a")!
            )
        ) {
            EventViewer()
        }
    )
}
#endif
