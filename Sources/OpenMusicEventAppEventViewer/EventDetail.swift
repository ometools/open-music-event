import OpenMusicEventLexicon
import ComposableArchitecture2
import ComposableNotifications
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
import SwiftUI
import SwiftUITabFeatures
import Tagged

#if !SKIP && !os(Android)
import CoreImage
import CoreImage.CIFilterBuiltins
#endif

public struct EventDetailDismissalRequested: FeatureEventKey {
    public typealias Value = Event.ID

    public init() {}
}

struct EventDetailContext: Sendable {
    let eventID: Event.ID
}

extension EventDetailContext: DependencyKey {
    static var liveValue: Self {
        Self(
            eventID: unimplemented(
                "EventDetailContext.eventID",
                placeholder: Event.ID("at://did:web:example.com/events.openmusic.event/3jzfcijpj2z2a")!
            )
        )
    }

    static var testValue: Self {
        Self(
            eventID: unimplemented(
                "EventDetailContext.eventID",
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
        get { self[EventDetailContext.self].eventID }
        set { self[EventDetailContext.self] = EventDetailContext(eventID: newValue) }
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
            .inMemory("open-music-event.authoring-grant." + eventID.description),
            default: nil
        ]
    }
}

public extension SharedReaderKey
where Self == InMemoryKey<EventWorkspaceSession?>.Default {
    static var defaultEventWorkspaceSession: Self {
        @Dependency(\.defaultEventID) var eventID
        return Self[
            .inMemory("open-music-event.workspace-session." + eventID.description),
            default: nil
        ]
    }
}

extension SharedReader where Value == EventWorkspaceSession? {
    static func eventWorkspaceSession(for eventID: Event.ID) -> Self {
        withDependencies {
            $0.defaultEventID = eventID
        } operation: {
            Self(.defaultEventWorkspaceSession)
        }
    }
}

extension Event {
  static var defaultEvent: some SelectStatementOf<Event> {
    @Dependency(EventDetailContext.self) var eventViewer
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
        let divisions: [ScheduleDivision] = (try? database.read { db -> [ScheduleDivision] in
            let event = try Event.find(eventID).fetchOne(db)
            let programs = try Program.where { $0.event.eq(eventID) }.fetchAll(db)
            return ScheduleList.scheduleDivisions(event: event, programs: programs)
        }) ?? []
        return features(
            scheduleDivisions: divisions,
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
public struct EventDetail {
    public init() {}

    public typealias EventFeature = OpenMusicEventViewers.EventFeature

    public enum ScheduleLaunchAction: Equatable, Sendable {
        case jumpToCurrentTime
    }

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.date.now) var now
    @Dependency(\.getSelectedOAuthSessionID) var getSelectedOAuthSessionID
    @Dependency(\.getOptionalDefaultSession) var getOptionalDefaultSession
    @Dependency(\.uuid) var uuid
    public struct State: Identifiable {
        public init(eventID: Event.ID) {
            let session = SharedReader<EventWorkspaceSession?>.eventWorkspaceSession(for: eventID)
            let account = CurrentWorkspaceAccount()
            self.init(
                eventID: eventID,
                features: EventFeature.features(
                    eventID: eventID,
                    authoringAccess: account.validated(
                        session.wrappedValue,
                        for: eventID
                    ) == nil ? .attendee : .authoring(.owner)
                )
            )
        }

        public init(
            eventID: Event.ID,
            features: [EventFeature],
            pendingAuthoringEntry: EditorEntry? = nil,
            pendingScheduleLaunchAction: ScheduleLaunchAction? = nil
        ) {
            self._workspaceSession = .eventWorkspaceSession(for: eventID)
            self.currentWorkspaceAccount = CurrentWorkspaceAccount()
            self.eventID = eventID
            self._event = FetchOne(
                Event.where { $0.id.eq(eventID) }
            )
            self.eventViewerState = EventDetailState(id: eventID)
            self._persistedEventViewerState = FetchOne(
                wrappedValue: nil,
                EventDetailState.none
            )
            self._stages = FetchAll(ScheduleList.stagesQuery(eventID: eventID))
            self._programs = FetchAll(Program.where { $0.event.eq(eventID) })
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
            let existingLocationViewer = self.locationViewer
            let existingNotificationsViewer = self.notificationsViewer
            let existingPostersViewer = self.postersViewer
            let existingScheduleViewers = self.scheduleViewers
            let existingSiteMapViewer = self.siteMapViewer
            let existingEventPlaceList = self.eventPlaceList

            self.scheduleViewers = []
            self.contributorsViewer = nil
            self.eventPlaceList = nil
            self.communicationsViewer = nil
            self.contactInfoViewer = nil
            self.locationViewer = nil
            self.siteMapViewer = nil
            self.postersViewer = nil
            self.notificationsViewer = nil
            self.eventSettings = nil
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
                                ScheduleList.State(
                                    eventID: eventID,
                                    scheduleDivision: division
                                )
                            )
                        )
                    case .contributors:
                        self.contributorsViewer = existingContributorsViewer
                            ?? Spawn(ContributorList.State(eventID: eventID))
                    case .stages:
                        self.eventPlaceList = existingEventPlaceList
                            ?? Spawn(EventPlaceList.State(eventID: eventID))
                    case .communications:
                        self.communicationsViewer = existingCommunicationsViewer
                            ?? SocialCategoryList.State(eventID: eventID)
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
            self.selectedFeature = features.first { $0.description == selectedFeature.description }
                ?? features.first ?? .schedule(.schedule)
            self.installFeatureStores(features)
        }

        public static func route(
            eventID: Event.ID,
            target: EventTarget?,
            pendingScheduleLaunchAction: ScheduleLaunchAction? = nil
        ) -> Self {
            let session = SharedReader<EventWorkspaceSession?>.eventWorkspaceSession(for: eventID)
            let account = CurrentWorkspaceAccount()
            let access: AuthoringAccess = account.validated(
                session.wrappedValue,
                for: eventID
            ) == nil ? .attendee : .authoring(.owner)
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
        public var workspaceSession: EventWorkspaceSession?
        @DebugSnapshotIgnored
        let currentWorkspaceAccount: CurrentWorkspaceAccount
        @Trigger public var authoringAuthorizationInvalidated
        public let eventID: Event.ID
        @FetchOne public var event: Event?
        public var eventViewerState: EventDetailState
        @FetchOne var persistedEventViewerState: EventDetailState?
        @FetchAll public var stages: [EventPlace]
        @FetchAll public var programs: [Program]
        @FetchAll public var reactions: [PerformanceReaction]
        @FetchAll public var reactionUsage: [PerformanceReactionEmojiUsage]
        public var installedFeatures: [EventFeature]
        public var selectedFeature: EventFeature

        public var scheduleViewers: [Spawn<ScheduleList>] = []
        public var contributorsViewer: Spawn<ContributorList>?
        public var eventPlaceList: Spawn<EventPlaceList>?
        public var communicationsViewer: SocialCategoryList.State?
        public var contactInfoViewer: Spawn<ContactInfoViewer>?
        public var locationViewer: Spawn<LocationViewer>?
        public var siteMapViewer: Spawn<SiteMapViewer>?
        public var postersViewer: Spawn<PostersViewer>?
        public var notificationsViewer: Spawn<NotificationsViewer>?
        public var eventSettings: Spawn<EventSettings>?
        public var canonicalWorkspace: CanonicalEventWorkspace.State?
        public var account = Spawn(Account.State())
        public var eventSearch: Spawn<EventSearch>
        public var eventInfoViewer: Spawn<EventInfoViewer>?

        public var destination: Destination.State?
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
            if validatedWorkspaceSession != nil { return .authoring(.owner) }
            return .attendee
        }

        public var validatedWorkspaceSession: EventWorkspaceSession? {
            currentWorkspaceAccount.validated(workspaceSession, for: eventID)
        }

        public var showsAuthoringControls: Bool {
            validatedWorkspaceSession != nil
        }

        public var needsStageDisambiguation: Bool {
            stages.count > 1
        }

        mutating func navigate(to target: EventTarget?) {
            guard let target else {
                self.eventSearch.state = EventSearch.State(eventID: eventID)
                self.contributorsViewer?.state.destination = nil
                self.eventPlaceList?.state.destination = nil
                return
            }

            self.selectedFeature = target.eventFeature

            switch target {
            case let .channel(channelID):
                let eventID = self.eventID
                if self.communicationsViewer == nil {
                    self.communicationsViewer = withEventDependencies {
                        SocialCategoryList.State(eventID: eventID)
                    }
                }
                let destination: SocialCategoryList.Destination.State = withEventDependencies {
                    .channelDetail(
                        SocialCategoryDetail.State(
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
                        SocialCategoryList.State(eventID: eventID)
                    }
                }
                let destination: SocialCategoryList.Destination.State = withEventDependencies {
                    .channelDetail(
                        SocialCategoryDetail.State(
                            channelID: channelID,
                            eventID: eventID,
                            destination: .postDetail(
                                SocialPostDetail.State(postID: postID, eventID: eventID)
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
                        Spawn(ContributorList.State(eventID: eventID))
                    }
                }
                let destination = withEventDependencies {
                    ContributorList.Destination.State.contributorDetail(
                        Spawn(
                            ContributorDetail.State(
                                contributorID: contributorID
                            )
                        )
                    )
                }
                self.contributorsViewer?.state.destination = destination
                self.eventPlaceList?.state.destination = nil
            case .contributors:
                self.eventSearch.state = EventSearch.State(eventID: eventID)
                self.contributorsViewer?.state.destination = nil
                self.eventPlaceList?.state.destination = nil
            case let .stage(stageID):
                let eventID = self.eventID
                self.eventSearch.state = withEventDependencies {
                    EventSearch.State(eventID: eventID)
                }
                self.contributorsViewer?.state.destination = nil
                if self.eventPlaceList == nil {
                    self.eventPlaceList = withEventDependencies {
                        Spawn(EventPlaceList.State(eventID: eventID))
                    }
                }
                let destination = withEventDependencies {
                    EventPlaceList.Destination.State.stageDetail(
                        Spawn(
                            EventPlaceDetail.State(
                                eventPlaceID: stageID
                            )
                        )
                    )
                }
                self.eventPlaceList?.state.destination = destination
            case let .performance(performanceID):
                let eventID = self.eventID
                self.eventSearch.state = EventSearch.State(eventID: eventID)
                self.contributorsViewer?.state.destination = nil
                self.eventPlaceList?.state.destination = nil
                for index in self.scheduleViewers.indices {
                    self.scheduleViewers[index].state.destination = nil
                }
                @Dependency(\.defaultDatabase) var database
                let programID = try? database.read { db in
                    try ProgramItem.find(performanceID).fetchOne(db)?.program
                }
                guard let scheduleViewerIndex = self.scheduleViewers.firstIndex(where: {
                    $0.state.scheduleDivision.programID == programID
                }) ?? self.scheduleViewers.indices.first else { return }
                self.selectedFeature = .schedule(self.scheduleViewers[scheduleViewerIndex].state.scheduleDivision)
                self.scheduleViewers[scheduleViewerIndex].state.destination = withEventDependencies {
                    .performanceDetail(
                        Spawn(
                            ProgramItemDetail.State(
                                performanceID: performanceID
                            )
                        )
                    )
                }
            case .stages:
                self.eventSearch.state = EventSearch.State(eventID: eventID)
                self.contributorsViewer?.state.destination = nil
                self.eventPlaceList?.state.destination = nil
            case .search:
                self.eventSearch.state = EventSearch.State.route(eventID: eventID, target: target)
                self.contributorsViewer?.state.destination = nil
                self.eventPlaceList?.state.destination = nil
            case .workspace:
                self.eventSearch.state = EventSearch.State(eventID: eventID)
                self.contributorsViewer?.state.destination = nil
                self.eventPlaceList?.state.destination = nil
            default:
                self.eventSearch.state = EventSearch.State(eventID: eventID)
                self.contributorsViewer?.state.destination = nil
                self.eventPlaceList?.state.destination = nil
            }
        }

        mutating func handleEditingIntent(_ intent: EventEditingIntent) {
            switch intent {
            case let .addPerformance(eventID, scheduleID, programID, stageID):
                guard eventID == self.eventID else { return }
                guard let editPerformance = withEventDependencies({
                    addPerformanceState(
                        scheduleID: scheduleID,
                        programID: programID,
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
                    .contributorForm(ContributorForm.State(eventID: eventID))
                }

            case let .createPlace(eventID):
                guard eventID == self.eventID else { return }
                self.destination = withEventDependencies {
                    .eventPlaceForm(EventPlaceForm.State(eventID: eventID))
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
                        ContributorForm.State(
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

            case let .editPlace(eventID, placeID):
                guard eventID == self.eventID else { return }
                self.destination = withEventDependencies {
                    .eventPlaceForm(
                        EventPlaceForm.State(
                            eventPlaceID: placeID,
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
            programID: Program.ID?,
            stageID: EventPlace.ID?
        ) -> ProgramItemForm.State? {
            @Dependency(\.defaultDatabase) var database

            do {
                return try database.write { db in
                    let event = try Event
                        .where { $0.id.eq(eventID) }
                        .fetchOne(db)
                    var schedules = ScheduleList.orderedSchedules(
                        event: event,
                        schedules: try ScheduleList.schedulesQuery(eventID: eventID).fetchAll(db)
                    )
                    let loadedPrograms = try Program.where { $0.event.eq(eventID) }.fetchAll(db)
                    let programsByID = Dictionary(uniqueKeysWithValues: loadedPrograms.map { ($0.id, $0) })
                    var programs = (event?.programs ?? []).compactMap { programsByID[$0] }
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
                    let selectedProgram = programs.first(where: { $0.id == programID }) ?? programs.first
                    let resolvedStageID = stageID.flatMap { stageID in
                        selectedProgram?.eventPlaces.contains(stageID) == true ? stageID : nil
                    } ?? selectedProgram?.eventPlaces.first
                    let initialStartTime: Date?
                    if let schedule {
                        initialStartTime = try ProgramItem
                            .where { $0.event.eq(eventID) }
                            .where { $0.schedule.eq(schedule.id) }
                            .fetchAll(db)
                            .filter { $0.eventPlace == resolvedStageID }
                            .compactMap(\.endDate)
                            .max()
                    } else {
                        initialStartTime = nil
                    }

                    return ProgramItemForm.State(
                        eventID: eventID,
                        schedule: schedule,
                        schedules: schedules,
                        programs: programs,
                        stages: stages,
                        timeZone: eventTimeZone,
                        selectedProgramID: selectedProgram?.id,
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
        ) -> ProgramItemForm.State? {
            @Dependency(\.defaultDatabase) var database

            do {
                return try database.read { db in
                    let event = try Event.find(eventID).fetchOne(db)
                    let performanceRows = try PerformanceRow.all(eventID: eventID).fetchAll(db)
                    let schedules = ScheduleList.orderedSchedules(
                        event: event,
                        schedules: try ScheduleList.schedulesQuery(eventID: eventID).fetchAll(db)
                    )
                    let programs = try Program.where { $0.event.eq(eventID) }.fetchAll(db)
                        .filter { event?.programs?.contains($0.id) == true }
                    let stages = try EventPlace.where { $0.event.eq(eventID) }.fetchAll(db)
                    let contributors = try ContributorProfile
                        .all(eventID: eventID, hydration: .none)
                        .fetchAll(db)
                    guard let row = performanceRows.first(where: {
                        $0.performanceID == performanceID
                    }) else { return nil }
                    let schedule = schedules.first { $0.id == row.performance.schedule }

                    return ProgramItemForm.State(
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

        private func editScheduleState() -> ScheduleForm.State {
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

            return ScheduleForm.State(
                eventID: eventID,
                initialDate: initialDate,
                timeZone: eventTimeZone
            )
        }

        fileprivate func withEventDependencies<Value>(_ operation: () -> Value) -> Value {
            let eventID = self.eventID
            let eventTimeZone = self.eventTimeZoneReader
            return withDependencies {
                $0[EventDetailContext.self] = EventDetailContext(eventID: eventID)
                $0.defaultEventTimeZone = eventTimeZone
            } operation: {
                operation()
            }
        }
    }

    public enum Action {
        case closeButtonTapped
        case communicationsViewer(SocialCategoryList.Action)
        case destination(Destination.Action)
        case editEventInfoButtonTapped
        case eventSearch(EventSearch.Action)
        case canonicalWorkspace(CanonicalEventWorkspace.Action)
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
        case contributorForm(ContributorForm)
        case copyStagesFromEvent(CopyStagesFromEvent)
        case eventInfoForm(EventForm)
        case locationForm(EditLocation)
        case performanceForm(ProgramItemForm)
        case scheduleForm(ScheduleForm)
        case eventPlaceForm(EventPlaceForm)
    }

    private func enterOrRequestAuthoring(_ entry: EditorEntry, state: inout State) {
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

    private func installCanonicalWorkspace(
        _ session: EventWorkspaceSession,
        state: inout State
    ) {
        guard state.validatedWorkspaceSession == session else { return }
        if state.canonicalWorkspace?.baseline != session.baseline {
            state.withEventDependencies {
                state.canonicalWorkspace = CanonicalEventWorkspace.State(
                    eventID: state.eventID,
                    baseline: session.baseline
                )
            }
        }
        state.reloadFeaturesForAuthoringAccess()
        if let pendingAuthoringEntry = state.pendingAuthoringEntry {
            enterOrRequestAuthoring(pendingAuthoringEntry, state: &state)
        }
    }

    private func sharedWorkspaceSession(
        for eventID: Event.ID
    ) -> Shared<EventWorkspaceSession?> {
        withDependencies {
            $0.defaultEventID = eventID
        } operation: {
            Shared<EventWorkspaceSession?>(.defaultEventWorkspaceSession)
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
                                key: EventDetailDismissalRequested.self,
                                value: eventID
                            )
                            await dismissal?.value
                            try store.dismiss()
                        }

                    case .communicationsViewer:
                        break

                    case .destination:
                        break

                    case .editEventInfoButtonTapped:
                        guard state.validatedWorkspaceSession != nil,
                              let event = state.event
                        else { break }
                        state.destination = state.withEventDependencies {
                            .eventInfoForm(EventForm.State(event: event))
                        }

                    case .eventSearch:
                        break

                    case .canonicalWorkspace:
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
                .onChange(of: store.selectedFeature) { _, feature, state in
                    guard feature.isEditorFeature else { return }
                    enterOrRequestAuthoring(.feature(feature), state: &state)
                }
                .onChange(of: store.event?.programs) { _, _, state in
                    state.reloadFeaturesForAuthoringAccess()
                }
                .onChange(of: store.programs) { _, _, state in
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
                    if let session = state.validatedWorkspaceSession {
                        installCanonicalWorkspace(session, state: &state)
                    } else {
                        state.reloadFeaturesForAuthoringAccess()
                    }
                    let eventID = state.eventID
                    let persistedEventViewerState = state.$persistedEventViewerState
                    store.addTask {
                        try await persistedEventViewerState.load(
                            EventDetailState.where { $0.id.eq(eventID) }
                        )
                        .task
                    }
                }
            )

            AnyFeature(
                EmptyFeature<State, Action>()
                    .onChange(of: store.workspaceSession) { _, session, state in
                        if let session, state.validatedWorkspaceSession == session {
                            installCanonicalWorkspace(session, state: &state)
                        } else {
                            state.canonicalWorkspace = nil
                            state.reloadFeaturesForAuthoringAccess()
                        }
                    }
                    .onEvent(AuthoringRequested.self) { _, state in
                        guard state.validatedWorkspaceSession == nil else { return }
                        let eventID = state.eventID
                        let sessionStorage = sharedWorkspaceSession(for: eventID)
                        let getOptionalDefaultSession = getOptionalDefaultSession
                        let database = database
                        store.addTask {
                            let _: Void? = await store.withErrorHandling(
                                fallbackMessage: .workspaceEntryFailed,
                                operation: .workspaceEntry
                            ) {
                                guard let account = getOptionalDefaultSession(),
                                      let actorID = DID(account.accountID.rawValue.description),
                                      eventID.authority == .did(actorID)
                                else { throw EventWorkspaceEntryError.ownerAccountRequired }
                                let baseline = try CanonicalWorkspaceBaseline.openOrCapture(
                                    for: eventID,
                                    from: database
                                )
                                guard let current = getOptionalDefaultSession(),
                                      DID(current.accountID.rawValue.description) == actorID
                                else { throw EventWorkspaceEntryError.ownerAccountRequired }
                                sessionStorage.withLock {
                                    $0 = EventWorkspaceSession(
                                        eventID: eventID,
                                        actorID: actorID,
                                        baseline: baseline
                                    )
                                }
                            }
                        }
                    }
                    .onEvent(AuthoringExitRequested.self) { _, state in
                        let eventID = state.eventID
                        let sessionStorage = sharedWorkspaceSession(for: eventID)
                        guard let session = state.validatedWorkspaceSession else {
                            sessionStorage.withLock { $0 = nil }
                            return
                        }
                        let database = database
                        store.addTask {
                            let _: Void? = await store.withErrorHandling(
                                fallbackMessage: .workspaceResetFailed,
                                operation: .workspaceReset
                            ) {
                                try CanonicalWorkspaceRecordChanges.reset(
                                    eventID: eventID,
                                    in: database,
                                    referenceDatabase: session.baseline
                                )
                                sessionStorage.withLock { $0 = nil }
                            }
                        }
                    }
                    .onTrigger(store.authoringAuthorizationInvalidated) { state in
                        let sessionStorage = sharedWorkspaceSession(for: state.eventID)
                        sessionStorage.withLock { $0 = nil }
                        state.canonicalWorkspace = nil
                        state.reloadFeaturesForAuthoringAccess()
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
                        ScheduleList()
                    }
                    EmptyFeature<State, Action>().ifLet(\.contributorsViewer) {
                        ContributorList()
                    }
                    EmptyFeature<State, Action>().ifLet(\.eventPlaceList) {
                        EventPlaceList()
                    }
                    EmptyFeature<State, Action>().spawn(\.eventSearch) {
                        EventSearch()
                    }
                    EmptyFeature<State, Action>().ifLet(\.communicationsViewer) {
                        SocialCategoryList()
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
                    EmptyFeature<State, Action>().ifLet(\.canonicalWorkspace) {
                        CanonicalEventWorkspace()
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
        .ifLet(\.destination) {
            Destination.body
                .dependency(EventDetailContext(eventID: store.eventID))
                .dependency(\.defaultEventTimeZone, store.eventTimeZoneReader)
        }
        .dependency(EventDetailContext(eventID: store.eventID))
        .dependency(\.defaultEventTimeZone, store.eventTimeZoneReader)
    }
}

extension EventDetail.Destination.StoreEnumeration: @MainActor Identifiable {
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
        case let .locationForm(store):
            destinationID("locationForm", store.eventID)
        case let .performanceForm(store):
            destinationID("performanceForm", store.eventID, store.performanceID)
        case let .scheduleForm(store):
            destinationID("scheduleForm", store.eventID)
        case let .eventPlaceForm(store):
            destinationID("eventPlaceForm", store.eventID, store.eventPlaceID)
        }
    }

    private func destinationID(_ components: AnyHashable...) -> AnyHashable {
        AnyHashable(components)
    }
}

public struct EventDetailView: View {
    public init(store: StoreOf<EventDetail>) {
        self.store = store
        self.accountStore = store.spawn(\.account)
    }

    @Bindable var store: StoreOf<EventDetail>
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
                        destinationContent(EventDetail.Destination.switch(store: destinationStore))
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
        _ destinationStore: EventDetail.Destination.StoreEnumeration
    ) -> some View {
        switch destinationStore {
        case let .copyStagesFromEvent(copyStore):
            CopyStagesFromEventView(store: copyStore)
        case let .eventInfoForm(formStore):
            EventFormView(store: formStore)
        case let .contributorForm(formStore):
            ContributorFormView(store: formStore)
        case let .eventPlaceForm(formStore):
            EventPlaceFormView(store: formStore)
        case let .contactInfoForm(formStore):
            EditContactInfoView(store: formStore)
        case let .locationForm(formStore):
            EditLocationView(store: formStore)
        case let .performanceForm(formStore):
            ProgramItemFormView(store: formStore)
        case let .scheduleForm(formStore):
            ScheduleFormView(store: formStore)
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
        @Bindable var store: StoreOf<EventDetail>
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
                    let feature = EventDetail.EventFeature.schedule(featureStore.scheduleDivision)
                    TabFeature(
                        feature,
                        title: feature.title,
                        systemImage: feature.systemImage,
                        labelTint: feature.labelTint,
                        navigation: .stack
                    ) {
                        ScheduleListView(
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
                        title: EventDetail.EventFeature.contributors.title,
                        systemImage: EventDetail.EventFeature.contributors.systemImage,
                        labelTint: EventDetail.EventFeature.contributors.labelTint,
                        navigation: .stack
                    ) {
                        ContributorListView(
                            store: featureStore,
                            showsAuthoringControls: store.showsAuthoringControls
                        )
                    }
                }

                if let featureStore = store.spawn(\.eventPlaceList) {
                    TabFeature(
                        .stages,
                        title: EventDetail.EventFeature.stages.title,
                        systemImage: EventDetail.EventFeature.stages.systemImage,
                        labelTint: EventDetail.EventFeature.stages.labelTint,
                        navigation: .stack
                    ) {
                        EventPlaceListView(
                            store: featureStore,
                            showsAuthoringControls: store.showsAuthoringControls
                        )
                    }
                }

                if let featureStore = store.scope(\.communicationsViewer) {
                    TabFeature(
                        .communications,
                        title: EventDetail.EventFeature.communications.title,
                        systemImage: EventDetail.EventFeature.communications.systemImage,
                        labelTint: EventDetail.EventFeature.communications.labelTint,
                        badgeValue: featureStore.unreadPostCount,
                        navigation: .stack
                    ) {
                        SocialCategoryListView(store: featureStore)
                    }
                }

                Section("Event") {
                    if let featureStore = store.spawn(\.contactInfoViewer) {
                        TabFeature(
                            .contactInfo,
                            title: EventDetail.EventFeature.contactInfo.title,
                            systemImage: EventDetail.EventFeature.contactInfo.systemImage,
                            labelTint: EventDetail.EventFeature.contactInfo.labelTint,
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
                            title: EventDetail.EventFeature.location.title,
                            systemImage: EventDetail.EventFeature.location.systemImage,
                            labelTint: EventDetail.EventFeature.location.labelTint,
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
                            systemImage: EventDetail.EventFeature.siteMap.systemImage,
                            labelTint: EventDetail.EventFeature.siteMap.labelTint,
                            navigation: .stack
                        ) {
                            SiteMapViewerView(
                                store: featureStore,
                                showsAuthoringControls: store.showsAuthoringControls
                            )
                        }
                    }
                }

                if let featureStore = store.spawn(\.postersViewer) {
                    TabFeature(
                        .posters,
                        title: EventDetail.EventFeature.posters.title,
                        systemImage: EventDetail.EventFeature.posters.systemImage,
                        labelTint: EventDetail.EventFeature.posters.labelTint,
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
                        title: EventDetail.EventFeature.notifications.title,
                        systemImage: EventDetail.EventFeature.notifications.systemImage,
                        labelTint: EventDetail.EventFeature.notifications.labelTint,
                        navigation: .stack
                    ) {
                        NotificationsViewerView(store: featureStore)
                    }
                }

                if let featureStore = store.spawn(\.eventSettings) {
                    TabFeature(
                        .settings,
                        title: EventDetail.EventFeature.settings.title,
                        systemImage: EventDetail.EventFeature.settings.systemImage,
                        labelTint: EventDetail.EventFeature.settings.labelTint,
                        badgeValue: featureStore.permissions.notificationSetupBadgeValue,
                        navigation: .stack
                    ) {
                        EventSettingsView(store: featureStore)
                    }
                }

                if let featureStore = store.scope(\.canonicalWorkspace) {
                    TabFeature(
                        .workspace,
                        title: EventDetail.EventFeature.workspace.title,
                        systemImage: EventDetail.EventFeature.workspace.systemImage,
                        labelTint: EventDetail.EventFeature.workspace.labelTint,
                        badgeValue: featureStore.badgeCount,
                        navigation: .stack
                    ) {
                        CanonicalEventWorkspaceView(
                            store: featureStore,
                            onEditEventInfo: { store.send(.editEventInfoButtonTapped) }
                        )
                    }
                }

                if let featureStore = store.spawn(\.eventInfoViewer) {
                    TabFeature(
                        .about,
                        title: EventDetail.EventFeature.about.title,
                        systemImage: EventDetail.EventFeature.about.systemImage,
                        labelTint: EventDetail.EventFeature.about.labelTint,
                        navigation: .stack
                    ) {
                        EventInfoViewerView(
                            store: featureStore,
                            showsAuthoringControls: store.showsAuthoringControls,
                            onEdit: { store.send(.editEventInfoButtonTapped) }
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
//                        title: EventDetail.EventFeature.share.title,
//                        systemImage: EventDetail.EventFeature.share.systemImage,
//                        labelTint: EventDetail.EventFeature.share.labelTint,
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
            .onChange(of: store.installedFeatures, initial: true) { _, features in
                tabLayout = EventDetail.EventFeature.preferredTabLayout(for: features)
            }
        }

    }

    #if os(iOS)
    private var legacyiOSTabView: some View {
        TabView(selection: $store.selectedFeature) {
            ForEach(store.spawn(\.scheduleViewers)) { featureStore in
                let feature = EventDetail.EventFeature.schedule(featureStore.scheduleDivision)
                viewerTab(feature) {
                    ScheduleListView(
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
                    ContributorListView(
                        store: featureStore,
                        showsAuthoringControls: store.showsAuthoringControls
                    )
                }
                .tag(EventDetail.EventFeature.contributors)
            }

            if let featureStore = store.spawn(\.eventPlaceList) {
                viewerTab(.stages) {
                    EventPlaceListView(
                        store: featureStore,
                        showsAuthoringControls: store.showsAuthoringControls
                    )
                }
                .tag(EventDetail.EventFeature.stages)
            }

            if let featureStore = store.scope(\.communicationsViewer) {
                viewerTab(
                    .communications,
                    badgeValue: featureStore.unreadPostCount
                ) {
                    SocialCategoryListView(store: featureStore)
                }
                .tag(EventDetail.EventFeature.communications)
            }

            if let featureStore = store.spawn(\.contactInfoViewer) {
                viewerTab(.contactInfo) {
                    ContactInfoViewerView(
                        store: featureStore,
                        showsAuthoringControls: store.showsAuthoringControls
                    )
                }
                .tag(EventDetail.EventFeature.contactInfo)
            }

            if let featureStore = store.spawn(\.locationViewer) {
                viewerTab(.location) {
                    LocationViewerView(
                        store: featureStore,
                        showsAuthoringControls: store.showsAuthoringControls
                    )
                }
                .tag(EventDetail.EventFeature.location)
            }

            if store.installedFeatures.contains(.search) {
                viewerTab(.search) {
                    EventSearchView(store: store.spawn(\.eventSearch))
                }
                .tag(EventDetail.EventFeature.search)
            }

            if let featureStore = store.spawn(\.siteMapViewer) {
                viewerTab(.siteMap) {
                    SiteMapViewerView(
                        store: featureStore,
                        showsAuthoringControls: store.showsAuthoringControls
                    )
                }
                .tag(EventDetail.EventFeature.siteMap)
            }

            if let featureStore = store.spawn(\.postersViewer) {
                viewerTab(.posters) {
                    PostersViewerView(
                        store: featureStore,
                        showsAuthoringControls: store.showsAuthoringControls
                    )
                }
                .tag(EventDetail.EventFeature.posters)
            }

            if let featureStore = store.spawn(\.notificationsViewer) {
                viewerTab(.notifications) {
                    NotificationsViewerView(store: featureStore)
                }
                .tag(EventDetail.EventFeature.notifications)
            }

            if let featureStore = store.spawn(\.eventSettings) {
                viewerTab(
                    .settings,
                    badgeValue: featureStore.permissions.notificationSetupBadgeValue
                ) {
                    EventSettingsView(store: featureStore)
                }
                .tag(EventDetail.EventFeature.settings)
            }

            if let featureStore = store.scope(\.canonicalWorkspace) {
                viewerTab(.workspace, badgeValue: featureStore.badgeCount) {
                    CanonicalEventWorkspaceView(
                        store: featureStore,
                        onEditEventInfo: { store.send(.editEventInfoButtonTapped) }
                    )
                }
                .tag(EventDetail.EventFeature.workspace)
            }

            if let featureStore = store.spawn(\.eventInfoViewer) {
                viewerTab(.about) {
                    EventInfoViewerView(
                        store: featureStore,
                        showsAuthoringControls: store.showsAuthoringControls,
                        onEdit: { store.send(.editEventInfoButtonTapped) }
                    )
                }
                .tag(EventDetail.EventFeature.about)
            }

        }
    }
    #endif

    private var defaultTabView: some View {
        TabView(selection: $store.selectedFeature) {
            ForEach(store.spawn(\.scheduleViewers)) { featureStore in
                let feature = EventDetail.EventFeature.schedule(featureStore.scheduleDivision)
                viewerTab(feature) {
                    ScheduleListView(
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
                    ContributorListView(
                        store: featureStore,
                        showsAuthoringControls: store.showsAuthoringControls
                    )
                }
                .tag(EventDetail.EventFeature.contributors)
            }

            if let featureStore = store.spawn(\.eventPlaceList) {
                viewerTab(.stages) {
                    EventPlaceListView(
                        store: featureStore,
                        showsAuthoringControls: store.showsAuthoringControls
                    )
                }
                .tag(EventDetail.EventFeature.stages)
            }

            if let featureStore = store.scope(\.communicationsViewer) {
                viewerTab(
                    .communications,
                    badgeValue: featureStore.unreadPostCount
                ) {
                    SocialCategoryListView(store: featureStore)
                }
                .tag(EventDetail.EventFeature.communications)
            }

            if let featureStore = store.spawn(\.contactInfoViewer) {
                viewerTab(.contactInfo) {
                    ContactInfoViewerView(
                        store: featureStore,
                        showsAuthoringControls: store.showsAuthoringControls
                    )
                }
                .tag(EventDetail.EventFeature.contactInfo)
            }

            if let featureStore = store.spawn(\.locationViewer) {
                viewerTab(.location) {
                    LocationViewerView(
                        store: featureStore,
                        showsAuthoringControls: store.showsAuthoringControls
                    )
                }
                .tag(EventDetail.EventFeature.location)
            }

            if let featureStore = store.spawn(\.siteMapViewer) {
                viewerTab(.siteMap) {
                    SiteMapViewerView(
                        store: featureStore,
                        showsAuthoringControls: store.showsAuthoringControls
                    )
                }
                .tag(EventDetail.EventFeature.siteMap)
            }

            if let featureStore = store.spawn(\.postersViewer) {
                viewerTab(.posters) {
                    PostersViewerView(
                        store: featureStore,
                        showsAuthoringControls: store.showsAuthoringControls
                    )
                }
                .tag(EventDetail.EventFeature.posters)
            }

            if let featureStore = store.spawn(\.notificationsViewer) {
                viewerTab(.notifications) {
                    NotificationsViewerView(store: featureStore)
                }
                .tag(EventDetail.EventFeature.notifications)
            }

            if let featureStore = store.spawn(\.eventSettings) {
                viewerTab(
                    .settings,
                    badgeValue: featureStore.permissions.notificationSetupBadgeValue
                ) {
                    EventSettingsView(store: featureStore)
                }
                .tag(EventDetail.EventFeature.settings)
            }

            if let featureStore = store.scope(\.canonicalWorkspace) {
                viewerTab(.workspace, badgeValue: featureStore.badgeCount) {
                    CanonicalEventWorkspaceView(
                        store: featureStore,
                        onEditEventInfo: { store.send(.editEventInfoButtonTapped) }
                    )
                }
                .tag(EventDetail.EventFeature.workspace)
            }

            if let featureStore = store.spawn(\.eventInfoViewer) {
                viewerTab(.about) {
                    EventInfoViewerView(
                        store: featureStore,
                        showsAuthoringControls: store.showsAuthoringControls,
                        onEdit: { store.send(.editEventInfoButtonTapped) }
                    )
                }
                .tag(EventDetail.EventFeature.about)
            }

            if store.installedFeatures.contains(.search) {
                viewerTab(.search) {
                    EventSearchView(store: store.spawn(\.eventSearch))
                }
                .tag(EventDetail.EventFeature.search)
            }
        }
    }

    private func viewerTab<Content: View>(
        _ feature: EventDetail.EventFeature,
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

private extension EventDetail.State {
    mutating func enterAuthoringEntry(_ entry: EventDetail.EditorEntry) {
        switch entry {
        case let .feature(feature):
            selectAuthoringFeature(feature)

        case let .intent(intent):
            handleEditingIntent(intent)

        case let .target(target):
            navigate(to: target)
        }
    }

    mutating func selectAuthoringFeature(_ feature: EventDetail.EventFeature) {
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
        case let .addPerformance(eventID, _, _, _),
             let .addPosters(eventID),
             let .addSchedule(eventID),
             let .copyStagesFromEvent(eventID),
             let .createContributor(eventID),
             let .createPlace(eventID),
             let .deletePerformance(eventID, _),
             let .editContactInfo(eventID),
             let .editContributor(eventID, _),
             let .editLocation(eventID),
             let .editPerformance(eventID, _),
             let .editPlace(eventID, _),
             let .eventSettings(eventID),
             let .eventWorkspace(eventID):
            return eventID

        }
    }
}

extension UserFacingText {
    static let workspaceEntryFailed = Self(
        "Sign in with the account that owns this event to enter Workspace.",
        fallback: "Sign in with the account that owns this event to enter Workspace."
    )
    static let workspaceBaselineSelectionFailed = Self(
        "Unable to switch Workspace.",
        fallback: "Unable to switch Workspace."
    )
}

extension ErrorOperation {
    static let workspaceEntry = Self("workspace.entry")
    static let workspaceBaselineSelection = Self("workspace.baseline.select")
}

private enum EventWorkspaceEntryError: Error {
    case ownerAccountRequired
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
    EventDetailView(
        store: Store(
            initialState: EventDetail.State(
                eventID: Event.ID("at://did:web:example.com/events.openmusic.event/3jzfcijpj2z2a")!
            )
        ) {
            EventDetail()
        }
    )
}
#endif
