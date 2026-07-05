import ATProto
import ComposableArchitecture2
import Dependencies
import Foundation
import ScheduleComponents
import SQLiteData
import SwiftUI
import Tagged

@Feature
public struct EditPerformance {
    public init() {}

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.date.now) var now

    public struct State: Identifiable {
        public struct StageOption: Equatable, Sendable {
            public init(stage: OMERecord.Stage) {
                self.id = stage.id.stageID
                self.name = stage.name
            }

            public var id: OMERecord.ID<OMERecord.Stage>
            public var name: String
            public var rawID: String { id.rawValue.rawValue }
        }

        public enum RelationshipRoleSelection: String, CaseIterable, Equatable, Hashable, Sendable {
            case performer
            case dj
            case dancer
            case visualArtist
            case soundTech
            case stageHand
            case custom

            init(role: OMERecord.Relationship.Role) {
                switch role {
                case .performer:
                    self = .performer
                case .dj:
                    self = .dj
                case .dancer:
                    self = .dancer
                case .visualArtist:
                    self = .visualArtist
                case .soundTech:
                    self = .soundTech
                case .stageHand:
                    self = .stageHand
                default:
                    self = .custom
                }
            }

            var role: OMERecord.Relationship.Role? {
                switch self {
                case .performer:
                    return .performer
                case .dj:
                    return .dj
                case .dancer:
                    return .dancer
                case .visualArtist:
                    return .visualArtist
                case .soundTech:
                    return .soundTech
                case .stageHand:
                    return .stageHand
                case .custom:
                    return nil
                }
            }

            var title: String {
                switch self {
                case .performer:
                    return "Performer"
                case .dj:
                    return "DJ"
                case .dancer:
                    return "Dancer"
                case .visualArtist:
                    return "Visual Artist"
                case .soundTech:
                    return "Sound Tech"
                case .stageHand:
                    return "Stage Hand"
                case .custom:
                    return "Custom"
                }
            }

            static var commonCases: [Self] {
                allCases.filter { $0 != .custom }
            }
        }

        public struct Contribution: Identifiable, Equatable, Sendable {
            public init(
                id: Int,
                selection: ContributorRelationshipPicker.Selection,
                billing: OMERecord.Performance.Contributors.Billing = .primary,
                roleSelection: RelationshipRoleSelection? = nil,
                customRelationshipRole: String = ""
            ) {
                self.id = id
                self.selection = selection
                self.billing = billing
                self.roleSelection = roleSelection
                self.customRelationshipRole = customRelationshipRole
            }

            public var id: Int
            public var selection: ContributorRelationshipPicker.Selection
            public var billing: OMERecord.Performance.Contributors.Billing
            public var roleSelection: RelationshipRoleSelection?
            public var customRelationshipRole: String

            var hasEmptyCustomRelationshipRole: Bool {
                roleSelection == .custom && trimmedCustomRelationshipRole.isEmpty
            }

            var trimmedCustomRelationshipRole: String {
                customRelationshipRole.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            var roleTitle: String {
                guard let roleSelection else { return "No role" }
                if roleSelection == .custom {
                    return trimmedCustomRelationshipRole.nilIfEmpty ?? roleSelection.title
                }
                return roleSelection.title
            }

            fileprivate var contributorSubject: EditPerformanceContributorSubject {
                switch selection {
                case .none:
                    return .none

                case let .existingContributor(contributorID):
                    return .contributor(contributorID)

                case let .identityOnly(actor, _):
                    return .identity(actor)

                case let .newContributor(name):
                    return .newContributor(name)

                case let .newContributorFromIdentity(identity):
                    return .newContributorFromIdentity(identity)

                case let .performanceDisplayName(name):
                    return .displayName(name)
                }
            }

            fileprivate var performanceContributorRole: OMERecord.Performance.Contributors.Role? {
                guard roleSelection != nil else { return nil }
                let role = relationshipRole
                return role == .performer
                    ? nil
                    : OMERecord.Performance.Contributors.Role(role.rawValue)
            }

            fileprivate var relationshipRole: OMERecord.Relationship.Role {
                guard let roleSelection else { return .performer }
                return roleSelection.role
                    ?? OMERecord.Relationship.Role(
                        trimmedCustomRelationshipRole.nilIfEmpty
                            ?? OMERecord.Relationship.Role.performer.rawValue
                    )
            }
        }

        public init(
            eventID: OMERecord.Event.ID,
            schedule: OMERecord.Schedule,
            stages: [OMERecord.Stage],
            timeZone: TimeZone,
            selectedStageID: OMERecord.ID<OMERecord.Stage>? = nil,
            contributors: [ContributorProfile] = []
        ) {
            let startTime = schedule.date.at(hour: 12, in: timeZone)
                ?? schedule.date.atStartOfDay(in: timeZone)
            let endTime = schedule.date.at(hour: 13, in: timeZone)
                ?? schedule.date.atStartOfDay(in: timeZone)
            self.eventID = eventID
            self.schedule = schedule
            self.contributorRelationshipPicker = ContributorRelationshipPicker.State(
                contributors: contributors
            )
            self.selectedStageID = selectedStageID.flatMap { selectedStageID in
                stages.contains { $0.id.stageID == selectedStageID }
                    ? selectedStageID
                    : nil
            } ?? stages.first?.id.stageID
            self.stageOptions = stages.map(StageOption.init)
            self.timeRangeSelection = DateTimeRangeSelection(
                start: startTime,
                end: endTime,
                timeZone: timeZone,
                anchorDate: schedule.date.atStartOfDay(in: timeZone),
                preferredWindow: Self.preferredWindow(for: schedule)
            )
            self.timeZone = timeZone
        }

        public init(
            eventID: OMERecord.Event.ID,
            schedule: OMERecord.Schedule,
            stages: [OMERecord.Stage],
            timeZone: TimeZone,
            performance: OMERecord.Performance,
            contributors: [ContributorProfile] = [],
            performanceContributors: [OMERecord.Performance.Contributors] = []
        ) {
            self.init(
                eventID: eventID,
                schedule: schedule,
                stages: stages,
                timeZone: timeZone,
                selectedStageID: performance.stageID,
                contributors: contributors
            )
            self.description = performance.description ?? ""
            self.performanceID = performance.id.performanceID
            self.selectedStageID = performance.stageID
            self.timeRangeSelection.end = performance.endTime
            self.timeRangeSelection.start = performance.startTime
            self.title = performance.title
            self.loadContributions(performanceContributors)
            self.titleIsGenerated = !self.generatedTitle.isEmpty && self.title == self.generatedTitle
        }

        public let eventID: OMERecord.Event.ID
        public let schedule: OMERecord.Schedule
        public let stageOptions: [StageOption]
        @DebugSnapshotIgnored
        public let timeZone: TimeZone

        var contributorRelationshipPicker: ContributorRelationshipPicker.State
        public var contributions: [Contribution] = []
        public var description = ""
        public var errorMessage: String?
        var generatedTitle = ""
        public var isSaving = false
        var nextContributionID = 0
        public var performanceID: OMERecord.ID<OMERecord.Performance>?
        public var selectedStageID: OMERecord.ID<OMERecord.Stage>?
        var titleIsGenerated = true
        public var timeRangeSelection: DateTimeRangeSelection
        public var title = ""

        public var id: String {
            [
                schedule.id.organizerID.description,
                schedule.id.eventID.rawValue.rawValue,
                schedule.id.scheduleID.rawValue.rawValue,
                performanceID?.rawValue.rawValue ?? "new",
            ]
            .joined(separator: ":")
        }

        public var canSubmit: Bool {
            !isSaving && validationMessage == nil
        }

        public var isCreating: Bool {
            performanceID == nil
        }

        public var navigationTitle: String {
            isCreating ? "New Performance" : "Edit Performance"
        }

        public var submitButtonTitle: String {
            isCreating ? "Create" : "Save"
        }

        public var endTimeSelection: Date {
            get { timeRangeSelection.end }
            set { timeRangeSelection.end = newValue }
        }

        public var startTimeSelection: Date {
            get { timeRangeSelection.start }
            set { timeRangeSelection.start = newValue }
        }

        public var trimmedDescription: String {
            description.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        public var trimmedTitle: String {
            title.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        public var validationMessage: String? {
            if trimmedTitle.isEmpty {
                return "Enter a title."
            }
            if selectedStageID == nil {
                return "Choose a stage."
            }
            if endTimeSelection <= startTimeSelection {
                return "End time must be after the start time."
            }
            if contributions.contains(where: \.hasEmptyCustomRelationshipRole) {
                return "Enter a relationship role."
            }
            return nil
        }

        var primaryContributions: [Contribution] {
            contributions.filter { $0.billing == .primary }
        }

        var supportingContributions: [Contribution] {
            contributions.filter { $0.billing == .supporting }
        }

        mutating func appendContribution(
            selection: ContributorRelationshipPicker.Selection,
            billing: OMERecord.Performance.Contributors.Billing? = nil,
            roleSelection: RelationshipRoleSelection? = nil,
            customRelationshipRole: String = ""
        ) {
            guard !selection.isNone else { return }
            contributions.append(
                Contribution(
                    id: nextContributionID,
                    selection: selection,
                    billing: billing ?? defaultBillingForNewContribution,
                    roleSelection: roleSelection,
                    customRelationshipRole: customRelationshipRole
                )
            )
            nextContributionID += 1
            refreshGeneratedTitle()
        }

        mutating func deleteContribution(id: Int) {
            contributions.removeAll { $0.id == id }
            refreshGeneratedTitle()
        }

        mutating func setContributionBilling(
            id: Int,
            billing: OMERecord.Performance.Contributors.Billing
        ) {
            guard let index = contributions.firstIndex(where: { $0.id == id }) else { return }
            contributions[index].billing = billing
            refreshGeneratedTitle()
        }

        mutating func setContributionCustomRole(id: Int, customRelationshipRole: String) {
            guard let index = contributions.firstIndex(where: { $0.id == id }) else { return }
            contributions[index].customRelationshipRole = customRelationshipRole
        }

        mutating func setContributionRole(
            id: Int,
            roleSelection: RelationshipRoleSelection?
        ) {
            guard let index = contributions.firstIndex(where: { $0.id == id }) else { return }
            contributions[index].roleSelection = roleSelection
            if roleSelection != .custom {
                contributions[index].customRelationshipRole = ""
            }
        }

        mutating func setTitleFromEditor(_ title: String) {
            self.title = title
            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                titleIsGenerated = true
                refreshGeneratedTitle()
            } else {
                titleIsGenerated = title == generatedTitle
            }
        }

        private mutating func refreshGeneratedTitle() {
            let shouldReplaceTitle = titleIsGenerated
                && (trimmedTitle.isEmpty || title == generatedTitle)
            let newGeneratedTitle = generatedPerformanceTitle()
            generatedTitle = newGeneratedTitle

            if shouldReplaceTitle {
                title = newGeneratedTitle
                titleIsGenerated = true
            } else if title != newGeneratedTitle {
                titleIsGenerated = false
            }
        }

        private var defaultBillingForNewContribution: OMERecord.Performance.Contributors.Billing {
            contributions.contains { $0.billing == .primary }
                ? .supporting
                : .primary
        }

        private func generatedPerformanceTitle() -> String {
            primaryContributions
                .compactMap { contribution in
                    contributorRelationshipPicker
                        .summary(for: contribution.selection)?
                        .title
                        .nilIfEmpty
                }
                .joined(separator: " b2b ")
        }

        private mutating func loadContributions(
            _ performanceContributors: [OMERecord.Performance.Contributors]
        ) {
            for contributor in performanceContributors.sorted(by: { $0.sortIndex < $1.sortIndex }) {
                guard let selection = Self.selection(for: contributor) else { continue }
                let role = contributor.role.map { OMERecord.Relationship.Role($0.rawValue) }
                let roleSelection = role.map(RelationshipRoleSelection.init(role:))
                appendContribution(
                    selection: selection,
                    billing: contributor.billing,
                    roleSelection: roleSelection,
                    customRelationshipRole: roleSelection == .custom ? role?.rawValue ?? "" : ""
                )
            }
        }

        private static func selection(
            for contributor: OMERecord.Performance.Contributors
        ) -> ContributorRelationshipPicker.Selection? {
            if let contributorID = contributor.contributorID {
                return .existingContributor(contributorID)
            }
            if let contributorActor = contributor.contributorActor {
                return .identityOnly(
                    actor: contributorActor,
                    displayTitle: contributorActor.description
                )
            }
            if let anonymousName = contributor.anonymousName {
                return .performanceDisplayName(name: anonymousName)
            }
            return nil
        }

        private static func preferredWindow(for schedule: OMERecord.Schedule) -> DateInterval? {
            guard let startsAt = schedule.startsAt,
                  let endsAt = schedule.endsAt,
                  endsAt > startsAt
            else { return nil }
            return DateInterval(start: startsAt, end: endsAt)
        }
    }

    public enum Action {
        case contributionBillingButtonTapped(
            Int,
            OMERecord.Performance.Contributors.Billing
        )
        case contributionCustomRoleChanged(Int, String)
        case contributionDeleteButtonTapped(Int)
        case contributionRoleButtonTapped(Int, State.RelationshipRoleSelection?)
        case contributorRelationshipPicker(ContributorRelationshipPicker.Action)
        case saveButtonTapped
        case titleTextChanged(String)
    }

    public var body: some Feature {
        Scope(\.contributorRelationshipPicker, action: \.contributorRelationshipPicker) {
            ContributorRelationshipPicker()
        }
        Update { state, action in
            switch action {
            case let .contributionBillingButtonTapped(id, billing):
                state.setContributionBilling(
                    id: id,
                    billing: billing
                )

            case let .contributionCustomRoleChanged(id, customRelationshipRole):
                state.setContributionCustomRole(
                    id: id,
                    customRelationshipRole: customRelationshipRole
                )

            case let .contributionDeleteButtonTapped(id):
                state.deleteContribution(id: id)

            case let .contributionRoleButtonTapped(id, roleSelection):
                state.setContributionRole(
                    id: id,
                    roleSelection: roleSelection
                )

            case let .contributorRelationshipPicker(action):
                switch action {
                case .createContributorButtonTapped,
                     .existingContributorTapped(_),
                     .identityCreateContributorButtonTapped(_),
                     .identityLinkOnlyButtonTapped(_),
                     .performanceDisplayNameButtonTapped:
                    let selection = state.contributorRelationshipPicker.selection
                    state.appendContribution(selection: selection)
                    if !selection.isNone {
                        state.contributorRelationshipPicker.resetSearch()
                    }

                case .actorSearchResponse,
                     .actorSearchSubmitted,
                     .clearSelectionButtonTapped,
                     .searchQueryChanged:
                    break
                }

            case .saveButtonTapped:
                guard !state.isSaving else { return }
                guard let validationMessage = state.validationMessage else {
                    guard let stageID = state.selectedStageID else {
                        state.errorMessage = "Choose a stage."
                        return
                    }

                    state.errorMessage = nil
                    state.isSaving = true
                    let request = EditPerformanceSaveRequest(
                        state: state,
                        stageID: stageID,
                        createdAt: Self.relationshipCreatedAt(now)
                    )

                    store.addTask {
                        do {
                            try database.write { db in
                                try EditPerformanceDrafts.save(request, in: db)
                            }
                            try store.modify {
                                $0.errorMessage = nil
                                $0.isSaving = false
                            }
                            try store.dismiss()
                        } catch {
                            try store.modify {
                                $0.errorMessage = request.errorMessage
                                $0.isSaving = false
                            }
                        }
                    }
                    return
                }

                state.errorMessage = validationMessage

            case let .titleTextChanged(title):
                state.setTitleFromEditor(title)
            }
        }
    }

    static func performanceContributorsQuery(
        performanceID: OMERecord.ID<OMERecord.Performance>,
        eventID: OMERecord.Event.ID
    ) -> some SelectStatementOf<OMERecord.Performance.Contributors> {
        OMERecord.Performance.Contributors
            .where { $0.performanceID.organizerID.eq(eventID.organizerID) }
            .where { $0.performanceID.eventID.eq(eventID.eventID) }
            .where { $0.performanceID.performanceID.eq(performanceID) }
            .order { $0.sortIndex }
    }

    private static func relationshipCreatedAt(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

fileprivate enum EditPerformanceContributorSubject: Equatable, Sendable {
    case none
    case contributor(OMERecord.ID<OMERecord.Contributor>)
    case identity(OMERecord.Contributor.Actor)
    case newContributor(String)
    case newContributorFromIdentity(ContributorRelationshipPicker.SelectedActorIdentity)
    case displayName(String)

    var identityDID: DID? {
        guard case let .identity(actor) = self,
              case let .did(did) = actor.identifier
        else { return nil }
        return did
    }
}

fileprivate struct EditPerformanceSaveRequest: Sendable {
    var contributions: [EditPerformance.State.Contribution]
    var createdAt: String
    var description: String?
    var endTime: Date
    var eventID: OMERecord.Event.ID
    var performanceID: OMERecord.ID<OMERecord.Performance>?
    var scheduleID: OMERecord.ID<OMERecord.Schedule>
    var stageID: OMERecord.ID<OMERecord.Stage>
    var startTime: Date
    var title: String

    init(
        state: EditPerformance.State,
        stageID: OMERecord.ID<OMERecord.Stage>,
        createdAt: String
    ) {
        self.contributions = state.contributions
        self.createdAt = createdAt
        self.description = state.trimmedDescription.nilIfEmpty
        self.endTime = state.endTimeSelection
        self.eventID = state.eventID
        self.performanceID = state.performanceID
        self.scheduleID = state.schedule.id.scheduleID
        self.stageID = stageID
        self.startTime = state.startTimeSelection
        self.title = state.trimmedTitle
    }

    var errorMessage: String {
        performanceID == nil
            ? "Unable to create performance."
            : "Unable to save performance."
    }
}

fileprivate enum EditPerformanceDrafts {
    static func save(_ request: EditPerformanceSaveRequest, in db: Database) throws {
        var request = request
        try resolveContributorSubjects(in: &request, db: db)

        if let performanceID = request.performanceID {
            try update(request, performanceID: performanceID, in: db)
        } else {
            try insert(request, in: db)
        }
    }

    static func insert(_ request: EditPerformanceSaveRequest, in db: Database) throws {
        let performanceID = try performanceID(for: request, in: db)
        try OMERecord.Performance.insert {
            performanceDraft(
                for: request,
                performanceID: performanceID
            )
        }
        .execute(db)

        let contributorDrafts = contributorDrafts(
            for: request,
            performanceID: performanceID
        )
        if !contributorDrafts.isEmpty {
            try OMERecord.Performance.Contributors.insert {
                contributorDrafts
            }
            .execute(db)
        }
        let relationshipDrafts = relationshipDrafts(
            for: request,
            performanceID: performanceID
        )
        if !relationshipDrafts.isEmpty {
            try OMERecord.Relationship.insert {
                relationshipDrafts
            }
            .execute(db)
        }
    }

    static func update(
        _ request: EditPerformanceSaveRequest,
        performanceID: OMERecord.ID<OMERecord.Performance>,
        in db: Database
    ) throws {
        let id = OMERecord.Performance.ID(
            organizerID: request.eventID.organizerID,
            eventID: request.eventID.eventID,
            performanceID: performanceID
        )
        guard try OMERecord.Performance.find(id).fetchOne(db) != nil else {
            throw EditPerformanceSaveError()
        }

        try OMERecord.Performance
            .find(id)
            .update {
                $0.description = #bind(request.description)
                $0.endTime = #bind(request.endTime)
                $0.scheduleID = #bind(request.scheduleID)
                $0.stageID = #bind(request.stageID)
                $0.startTime = #bind(request.startTime)
                $0.title = #bind(request.title)
            }
            .execute(db)

        try OMERecord.Performance.Contributors
            .where { $0.performanceID.organizerID.eq(request.eventID.organizerID) }
            .where { $0.performanceID.eventID.eq(request.eventID.eventID) }
            .where { $0.performanceID.performanceID.eq(performanceID) }
            .delete()
            .execute(db)
        try deletePerformanceRelationships(
            performanceID: id,
            in: db
        )

        let contributorDrafts = contributorDrafts(
            for: request,
            performanceID: performanceID
        )
        if !contributorDrafts.isEmpty {
            try OMERecord.Performance.Contributors.insert {
                contributorDrafts
            }
            .execute(db)
        }

        let relationshipDrafts = relationshipDrafts(
            for: request,
            performanceID: performanceID
        )
        if !relationshipDrafts.isEmpty {
            try OMERecord.Relationship.insert {
                relationshipDrafts
            }
            .execute(db)
        }
    }

    static func performanceID(
        for request: EditPerformanceSaveRequest,
        in db: Database
    ) throws -> OMERecord.ID<OMERecord.Performance> {
        let base = performanceIDBase(for: request)
        var candidate = base
        var suffix = 2

        while try PerformanceDetail.performanceQuery(
            performanceID: localID(candidate),
            eventID: request.eventID
        )
        .fetchOne(db) != nil {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }

        return localID(candidate)
    }

    static func performanceDraft(
        for request: EditPerformanceSaveRequest,
        performanceID: OMERecord.ID<OMERecord.Performance>
    ) -> OMERecord.Performance.Draft {
        OMERecord.Performance.Draft(
            id: OMERecord.Performance.ID(
                organizerID: request.eventID.organizerID,
                eventID: request.eventID.eventID,
                performanceID: performanceID
            ),
            stageID: request.stageID,
            scheduleID: request.scheduleID,
            startTime: request.startTime,
            endTime: request.endTime,
            title: request.title,
            description: request.description,
            recordings: []
        )
    }

    static func contributorDrafts(
        for request: EditPerformanceSaveRequest,
        performanceID: OMERecord.ID<OMERecord.Performance>
    ) -> [OMERecord.Performance.Contributors.Draft] {
        var drafts: [OMERecord.Performance.Contributors.Draft] = []
        let scopedPerformanceID = OMERecord.Performance.ID(
            organizerID: request.eventID.organizerID,
            eventID: request.eventID.eventID,
            performanceID: performanceID
        )

        for (sortIndex, contribution) in request.contributions.enumerated() {
            switch contribution.contributorSubject {
            case .none:
                break

            case let .contributor(contributorID):
                drafts.append(
                    OMERecord.Performance.Contributors.Draft(
                        performanceID: scopedPerformanceID,
                        contributorID: contributorID,
                        anonymousName: nil,
                        contributorActor: nil,
                        billing: contribution.billing,
                        role: contribution.performanceContributorRole,
                        sortIndex: sortIndex
                    )
                )

            case let .identity(actor):
                drafts.append(
                    OMERecord.Performance.Contributors.Draft(
                        performanceID: scopedPerformanceID,
                        contributorID: nil,
                        anonymousName: nil,
                        contributorActor: actor,
                        billing: contribution.billing,
                        role: contribution.performanceContributorRole,
                        sortIndex: sortIndex
                    )
                )

            case .newContributor, .newContributorFromIdentity:
                break

            case let .displayName(name):
                drafts.append(
                    OMERecord.Performance.Contributors.Draft(
                        performanceID: scopedPerformanceID,
                        contributorID: nil,
                        anonymousName: name,
                        contributorActor: nil,
                        billing: contribution.billing,
                        role: contribution.performanceContributorRole,
                        sortIndex: sortIndex
                    )
                )
            }
        }

        return drafts
    }

    static func relationshipDrafts(
        for request: EditPerformanceSaveRequest,
        performanceID: OMERecord.ID<OMERecord.Performance>
    ) -> [OMERecord.Relationship] {
        let scopedPerformanceID = OMERecord.Performance.ID(
            organizerID: request.eventID.organizerID,
            eventID: request.eventID.eventID,
            performanceID: performanceID
        )
        let object = OMERecord.Relationship.RecordReference(performanceID: scopedPerformanceID)
        var relationships: [OMERecord.Relationship] = []

        for contribution in request.contributions {
            switch contribution.contributorSubject {
            case .none, .displayName:
                break

            case let .contributor(contributorID):
                let scopedContributorID = OMERecord.Contributor.ID(
                    organizerID: request.eventID.organizerID,
                    eventID: request.eventID.eventID,
                    contributorID: contributorID
                )
                relationships.append(
                    OMERecord.Relationship(
                        subject: .record(.init(contributorID: scopedContributorID)),
                        role: contribution.relationshipRole,
                        object: .record(object),
                        createdAt: request.createdAt
                    )
                )

            case let .identity(actor):
                guard case let .did(did) = actor.identifier else { break }
                relationships.append(
                    OMERecord.Relationship(
                        subject: .identity(did: did),
                        role: contribution.relationshipRole,
                        object: .record(object),
                        createdAt: request.createdAt
                    )
                )

            case .newContributor, .newContributorFromIdentity:
                break
            }
        }

        return relationships
    }

    static func resolveContributorSubjects(
        in request: inout EditPerformanceSaveRequest,
        db: Database
    ) throws {
        for index in request.contributions.indices {
            switch request.contributions[index].contributorSubject {
            case .none, .contributor, .displayName, .identity:
                break

            case let .newContributor(name):
                let contributorID = try contributorID(for: name, eventID: request.eventID, in: db)
                try insertContributor(
                    contributorID: contributorID,
                    did: nil,
                    eventID: request.eventID,
                    name: name,
                    in: db
                )
                request.contributions[index].selection = .existingContributor(contributorID)

            case let .newContributorFromIdentity(identity):
                if let contributorID = try contributorID(
                    matching: identity.did,
                    eventID: request.eventID,
                    in: db
                ) {
                    request.contributions[index].selection = .existingContributor(contributorID)
                    continue
                }

                let contributorID = try contributorID(
                    for: identity.contributorName,
                    eventID: request.eventID,
                    in: db
                )
                try insertContributor(
                    contributorID: contributorID,
                    did: identity.did,
                    eventID: request.eventID,
                    name: identity.contributorName,
                    in: db
                )
                request.contributions[index].selection = .existingContributor(contributorID)
            }
        }
    }

    static func contributorID(
        matching did: DID,
        eventID: OMERecord.Event.ID,
        in db: Database
    ) throws -> OMERecord.ID<OMERecord.Contributor>? {
        try OMERecord.Contributor
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .fetchAll(db)
            .first { $0.did == did }?
            .id.contributorID
    }

    static func contributorID(
        for name: String,
        eventID: OMERecord.Event.ID,
        in db: Database
    ) throws -> OMERecord.ID<OMERecord.Contributor> {
        let base = slug(for: name)
        var candidate = base
        var suffix = 2

        while try ContributorDetail.contributorQuery(
            contributorID: OMERecord.ID<OMERecord.Contributor>(.init(candidate)),
            eventID: eventID
        )
        .fetchOne(db) != nil {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }

        return OMERecord.ID<OMERecord.Contributor>(.init(candidate))
    }

    static func insertContributor(
        contributorID: OMERecord.ID<OMERecord.Contributor>,
        did: DID?,
        eventID: OMERecord.Event.ID,
        name: String,
        in db: Database
    ) throws {
        try OMERecord.Contributor.insert {
            OMERecord.Contributor.Draft(
                id: OMERecord.Contributor.ID(
                    organizerID: eventID.organizerID,
                    eventID: eventID.eventID,
                    contributorID: contributorID
                ),
                name: name,
                did: did,
                bio: nil,
                images: nil,
                links: nil
            )
        }
        .execute(db)
    }

    static func deletePerformanceRelationships(
        performanceID: OMERecord.Performance.ID,
        in db: Database
    ) throws {
        let recordURI = OMERecord.Relationship.RecordReference(performanceID: performanceID).uri.description
        try db.execute(
            sql: #"""
            DELETE FROM "relationships"
            WHERE json_extract("object", '$.uri') = ?
            """#,
            arguments: [recordURI]
        )
    }

    private static func localID(_ string: String) -> OMERecord.ID<OMERecord.Performance> {
        OMERecord.ID<OMERecord.Performance>(.init(string))
    }

    private static func performanceIDBase(for request: EditPerformanceSaveRequest) -> String {
        [
            request.scheduleID.rawValue.rawValue,
            request.stageID.rawValue.rawValue,
            slug(for: request.title),
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "-")
    }

    private static func slug(for string: String) -> String {
        let normalized = string
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
        let words = normalized
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return words.isEmpty ? "performance" : words.joined(separator: "-")
    }
}

private struct EditPerformanceSaveError: Error {}

public struct EditPerformanceView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.needsStageDisambiguation) var needsStageDisambiguation
    @Bindable var store: StoreOf<EditPerformance>

    public init(store: StoreOf<EditPerformance>) {
        self.store = store
    }

    public var body: some View {
        Form {
            lineupSection
            performanceSection
            timeSection
            messages
        }
        .disabled(store.isSaving)
        .navigationTitle(store.navigationTitle)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if store.isSaving {
                    ProgressView()
                } else {
                    Button(store.submitButtonTitle) {
                        store.send(.saveButtonTapped)
                    }
                    .disabled(!store.canSubmit)
                }
            }
        }
    }

    private var performanceSection: some View {
        Section("Performance") {
            TextField("Title", text: performanceTitleBinding, prompt: Text("Artist Set"))
            TextField("Description", text: $store.description, axis: .vertical)
                .lineLimit(3...8)
        }
    }

    private var lineupSection: some View {
        Section("Lineup") {
            if needsStageDisambiguation {
                Picker("Stage", selection: $store.selectedStageID) {
                    ForEach(store.stageOptions, id: \.rawID) { stage in
                        Text(stage.name).tag(Optional(stage.id))
                    }
                }
            }

            contributionRows(store.primaryContributions + store.supportingContributions)
            ContributorRelationshipPickerRows(
                store: store.scope(
                    \.contributorRelationshipPicker,
                    action: \.contributorRelationshipPicker
                )
            )
        }
    }

    private var timeSection: some View {
        Section("Time") {
            DateTimeRangePicker(selection: $store.timeRangeSelection)
        }
    }

    private func customRelationshipRoleBinding(for contributionID: Int) -> Binding<String> {
        Binding(
            get: {
                store.contributions.first { $0.id == contributionID }?
                    .customRelationshipRole
                    ?? ""
            },
            set: { customRelationshipRole in
                store.send(
                    .contributionCustomRoleChanged(
                        contributionID,
                        customRelationshipRole
                    )
                )
            }
        )
    }

    @ViewBuilder
    private func contributionRows(
        _ contributions: [EditPerformance.State.Contribution]
    ) -> some View {
        if !contributions.isEmpty {
            ForEach(contributions) { contribution in
                let summary = store.contributorRelationshipPicker.summary(
                    for: contribution.selection
                )
                EditPerformanceContributionRow(
                    title: summary?.title ?? "Contributor",
                    subtitle: summary?.subtitle,
                    isPrimary: contribution.billing == .primary,
                    roleTitle: contribution.roleTitle,
                    roleSelection: contribution.roleSelection,
                    roleChanged: { roleSelection in
                        store.send(
                            .contributionRoleButtonTapped(
                                contribution.id,
                                roleSelection
                            )
                        )
                    }
                )
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        store.send(.contributionDeleteButtonTapped(contribution.id))
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    if contribution.billing == .supporting {
                        Button {
                            store.send(
                                .contributionBillingButtonTapped(
                                    contribution.id,
                                    .primary
                                )
                            )
                        } label: {
                            Label("Primary", systemImage: "star.fill")
                        }
                    }
                }
                .contextMenu {
                    if contribution.billing == .primary {
                        Button("Remove as primary") {
                            store.send(
                                .contributionBillingButtonTapped(
                                    contribution.id,
                                    .supporting
                                )
                            )
                        }
                    } else {
                        Button("Set as primary") {
                            store.send(
                                .contributionBillingButtonTapped(
                                    contribution.id,
                                    .primary
                                )
                            )
                        }
                    }
                }

                if contribution.roleSelection == .custom {
                    TextField(
                        "Custom Role",
                        text: customRelationshipRoleBinding(for: contribution.id),
                        prompt: Text("performer")
                    )
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                }
            }
        }
    }

    private var performanceTitleBinding: Binding<String> {
        Binding(
            get: { store.title },
            set: { store.send(.titleTextChanged($0)) }
        )
    }

    @ViewBuilder
    private var messages: some View {
        if let validationMessage = store.validationMessage {
            Section {
                Text(validationMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        if let errorMessage = store.errorMessage {
            Section {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }
}

struct EditPerformanceContributionRow: View {
    let title: String
    let subtitle: String?
    let isPrimary: Bool
    let roleTitle: String
    let roleSelection: EditPerformance.State.RelationshipRoleSelection?
    let roleChanged: (EditPerformance.State.RelationshipRoleSelection?) -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if isPrimary {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.tint)
                            .accessibilityLabel("Primary contributor")
                    }
                    Text(title)
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()

            Picker("Role", selection: roleSelectionBinding) {
                Text("No role")
                    .tag(EditPerformance.State.RelationshipRoleSelection?.none)
                ForEach(
                    EditPerformance.State.RelationshipRoleSelection.allCases,
                    id: \.self
                ) { role in
                    Text(title(for: role))
                        .tag(Optional(role))
                }
            }
            .labelsHidden()
        }
        .padding(.vertical, 2)
    }

    private var roleSelectionBinding: Binding<EditPerformance.State.RelationshipRoleSelection?> {
        Binding(
            get: { roleSelection },
            set: { roleChanged($0) }
        )
    }

    private func title(
        for role: EditPerformance.State.RelationshipRoleSelection
    ) -> String {
        role == .custom && roleSelection == .custom
            ? roleTitle
            : role.title
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
