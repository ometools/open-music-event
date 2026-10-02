import OpenMusicEventLexicon
import ATProto
import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventComponents
import OpenMusicEventDatabase
import ScheduleComponents
import SQLiteData
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif
import Tagged

@Feature
public struct ProgramItemForm {
    public init() {}

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.date.now) var now

    public struct State: Identifiable {
        public struct StageOption: Equatable, Sendable {
            public init(stage: EventPlace) {
                self.id = stage.id
                self.name = stage.name
            }

            public var id: EventPlace.ID
            public var name: String
            public var rawID: String { id.description }
        }

        public enum RelationshipRoleSelection: String, CaseIterable, Equatable, Hashable, Sendable {
            case performer
            case dj
            case dancer
            case visualArtist
            case soundTech
            case stageHand
            case custom

            init(role: String) {
                switch role {
                case "performer":
                    self = .performer
                case "dj":
                    self = .dj
                case "dancer":
                    self = .dancer
                case "visualArtist":
                    self = .visualArtist
                case "soundTech":
                    self = .soundTech
                case "stageHand":
                    self = .stageHand
                default:
                    self = .custom
                }
            }

            var role: String? {
                switch self {
                case .performer:
                    return "performer"
                case .dj:
                    return "dj"
                case .dancer:
                    return "dancer"
                case .visualArtist:
                    return "visualArtist"
                case .soundTech:
                    return "soundTech"
                case .stageHand:
                    return "stageHand"
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
                billing: Open<ProgramItem.Billing> = .known(.primary),
                roleSelection: RelationshipRoleSelection? = nil,
                customRelationshipRole: String = "",
                creditName: String? = nil
            ) {
                self.id = id
                self.selection = selection
                self.billing = billing
                self.roleSelection = roleSelection
                self.customRelationshipRole = customRelationshipRole
                self.creditName = creditName
            }

            public var id: Int
            public var selection: ContributorRelationshipPicker.Selection
            public var billing: Open<ProgramItem.Billing>
            public var roleSelection: RelationshipRoleSelection?
            public var customRelationshipRole: String
            public var creditName: String?

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

            fileprivate var role: String? {
                guard let roleSelection else { return nil }
                return roleSelection.role ?? trimmedCustomRelationshipRole.nilIfEmpty
            }
        }

        public typealias MediaEntry = RecordMediaEditing.MediaEntry
        public typealias MediaDraft = RecordMediaEditing.MediaDraft

        public init(
            eventID: Event.ID,
            schedule: Schedule?,
            schedules: [Schedule],
            programs: [Program],
            stages: [EventPlace],
            timeZone: TimeZone,
            selectedProgramID: Program.ID? = nil,
            selectedStageID: EventPlace.ID? = nil,
            initialStartTime: Date? = nil,
            contributors: [ContributorProfile] = []
        ) {
            @Dependency(\.date.now) var now
            let defaultStartTime = schedule?.date.at(hour: 12, in: timeZone)
                ?? schedule?.date.atStartOfDay(in: timeZone)
                ?? now
            let startTime = initialStartTime ?? defaultStartTime
            let endTime = initialStartTime.map { $0.addingTimeInterval(60 * 60) }
                ?? schedule?.date.at(hour: 13, in: timeZone)
                ?? schedule?.date.atStartOfDay(in: timeZone)
                ?? startTime.addingTimeInterval(60 * 60)
            self.eventID = eventID
            self.schedule = schedule
            self.schedules = schedules
            self.programs = programs
            self.isAssignedToSchedule = schedule != nil
            self.hasStartTime = schedule != nil
            self.hasEndTime = schedule != nil
            self.contributorRelationshipPicker = ContributorRelationshipPicker.State(
                contributors: contributors
            )
            let resolvedProgramID = selectedProgramID ?? programs.first(where: {
                selectedStageID.map($0.eventPlaces.contains) == true
            })?.id ?? programs.first?.id
            self.selectedProgramID = resolvedProgramID
            self.selectedStageID = selectedStageID.flatMap { selectedStageID in
                stages.contains { $0.id == selectedStageID }
                    && programs.first(where: { $0.id == resolvedProgramID })?
                        .eventPlaces.contains(selectedStageID) == true
                    ? selectedStageID
                    : nil
            } ?? stages.first(where: { stage in
                programs.first(where: { $0.id == resolvedProgramID })?
                    .eventPlaces.contains(stage.id) == true
            })?.id
            self.allStageOptions = stages.map(StageOption.init)
            self.timeRangeSelection = DateTimeRangeSelection(
                start: startTime,
                end: endTime,
                timeZone: timeZone,
                anchorDate: schedule?.date.atStartOfDay(in: timeZone) ?? startTime,
                preferredWindow: nil
            )
            self.timeZone = timeZone
        }

        public init(
            eventID: Event.ID,
            schedule: Schedule?,
            schedules: [Schedule],
            programs: [Program],
            stages: [EventPlace],
            timeZone: TimeZone,
            performance: ProgramItem,
            contributors: [ContributorProfile] = []
        ) {
            self.init(
                eventID: eventID,
                schedule: schedule,
                schedules: schedules,
                programs: programs,
                stages: stages,
                timeZone: timeZone,
                selectedStageID: performance.eventPlace,
                contributors: contributors
            )
            self.description = performance.description ?? ""
            self.performanceID = performance.id
            self.selectedProgramID = performance.program
            self.selectedStageID = performance.eventPlace
            if let assignedSchedule = schedules.first(where: { $0.id == performance.schedule }) {
                self.selectedScheduleID = assignedSchedule.id
            } else {
                self.selectedScheduleID = nil
            }
            self.isAssignedToSchedule = performance.schedule != nil
            self.hasStartTime = performance.startsAt != nil
            self.hasEndTime = performance.endsAt != nil
            self.timeRangeSelection.end = performance.endDate ?? performance.startDate ?? self.timeRangeSelection.end
            self.timeRangeSelection.start = performance.startDate ?? self.timeRangeSelection.start
            self.title = performance.title
            self.mediaEntries = (performance.media ?? []).map { MediaEntry(value: $0) }
            self.loadContributions(performance.credits ?? [])
            self.titleIsGenerated = !self.generatedTitle.isEmpty && self.title == self.generatedTitle
        }

        public let eventID: Event.ID
        public var schedule: Schedule?
        public let schedules: [Schedule]
        public let programs: [Program]
        public let allStageOptions: [StageOption]
        @DebugSnapshotIgnored
        public let timeZone: TimeZone

        @DebugSnapshotTracked
        var contributorRelationshipPicker: ContributorRelationshipPicker.State
        public var contributions: [Contribution] = []
        public var description = ""
        public var destination: Destination.State?
        public var errorMessage: String?
        @DebugSnapshotTracked
        var generatedTitle = ""
        public var isSaving = false
        public var isAssignedToSchedule = true
        public var hasStartTime = true
        public var hasEndTime = true
        public var editingContributionID: Int?
        @DebugSnapshotTracked
        var nextContributionID = 0
        public var performanceID: ProgramItem.ID?
        public var selectedProgramID: Program.ID?
        public var selectedStageID: EventPlace.ID?
        public var mediaEntries: [MediaEntry] = []
        public var mediaDraft: MediaDraft? = nil
        @DebugSnapshotTracked
        var titleIsGenerated = true
        public var timeRangeSelection: DateTimeRangeSelection
        public var title = ""

        public var id: String {
            "\(eventID.description):\(performanceID?.description ?? "new")"
        }

        public var stageOptions: [StageOption] {
            guard let program = programs.first(where: { $0.id == selectedProgramID }) else { return [] }
            return allStageOptions.filter { program.eventPlaces.contains($0.id) }
        }

        mutating func selectProgram(_ programID: Program.ID?) {
            guard let program = programs.first(where: { $0.id == programID }) else { return }
            selectedProgramID = program.id
            if let selectedStageID, !program.eventPlaces.contains(selectedStageID) {
                self.selectedStageID = nil
            }
        }

        public var selectedScheduleID: Schedule.ID? {
            get { schedule?.id }
            set {
                guard newValue != schedule?.id else { return }
                guard let newValue else {
                    schedule = nil
                    return
                }
                guard let selectedSchedule = schedules.first(where: { $0.id == newValue }) else {
                    return
                }

                let startDayOffset = timeRangeSelection.startDayOffset
                schedule = selectedSchedule
                timeRangeSelection.anchorDate = selectedSchedule.date.atStartOfDay(in: timeZone)
                timeRangeSelection.preferredWindow = nil
                timeRangeSelection.setStartDayOffset(startDayOffset)
            }
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
            if mediaDraft != nil {
                return "Finish editing media."
            }
            if trimmedTitle.isEmpty {
                return "Enter a title."
            }
            if selectedProgramID == nil {
                return "Choose a program."
            }
            if isAssignedToSchedule && schedule == nil {
                return "Choose a festival day."
            }
            if let selectedStageID, !stageOptions.contains(where: { $0.id == selectedStageID }) {
                return "Choose a place in this program."
            }
            if isAssignedToSchedule && hasStartTime && hasEndTime
                && endTimeSelection <= startTimeSelection {
                return "End time must be after the start time."
            }
            if contributions.contains(where: \.hasEmptyCustomRelationshipRole) {
                return "Enter a relationship role."
            }
            if contributions.contains(where: {
                $0.creditName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true
            }) {
                return "Enter a contributor name."
            }
            return nil
        }

        mutating func editMedia(id: MediaEntry.ID) {
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

        var primaryContributions: [Contribution] {
            contributions.filter { $0.billing == .known(.primary) }
        }

        var supportingContributions: [Contribution] {
            contributions.filter { $0.billing != .known(.primary) }
        }

        mutating func appendContribution(
            selection: ContributorRelationshipPicker.Selection,
            billing: Open<ProgramItem.Billing>? = nil,
            roleSelection: RelationshipRoleSelection? = nil,
            customRelationshipRole: String = "",
            creditName: String? = nil
        ) {
            guard !selection.isNone else { return }
            contributions.append(
                Contribution(
                    id: nextContributionID,
                    selection: selection,
                    billing: billing ?? defaultBillingForNewContribution,
                    roleSelection: roleSelection,
                    customRelationshipRole: customRelationshipRole,
                    creditName: creditName
                )
            )
            nextContributionID += 1
            refreshGeneratedTitle()
        }

        mutating func updateContributionSelection(
            id: Int,
            selection: ContributorRelationshipPicker.Selection
        ) {
            guard let index = contributions.firstIndex(where: { $0.id == id }) else { return }
            contributions[index].selection = selection
            contributions[index].creditName = nil
            refreshGeneratedTitle()
        }

        mutating func deleteContribution(id: Int) {
            contributions.removeAll { $0.id == id }
            if editingContributionID == id { editingContributionID = nil }
            refreshGeneratedTitle()
        }

        mutating func editContribution(id: Int) {
            guard let index = contributions.firstIndex(where: { $0.id == id }) else { return }
            if contributions[index].creditName == nil {
                contributions[index].creditName = contributorRelationshipPicker
                    .summary(for: contributions[index].selection)?.title
            }
            editingContributionID = id
        }

        mutating func moveContribution(id: Int, offset: Int) {
            guard let index = contributions.firstIndex(where: { $0.id == id }),
                  contributions.indices.contains(index + offset) else { return }
            contributions.swapAt(index, index + offset)
        }

        mutating func setContributionName(id: Int, name: String) {
            guard let index = contributions.firstIndex(where: { $0.id == id }) else { return }
            contributions[index].creditName = name
            refreshGeneratedTitle()
        }

        mutating func setContributionBilling(
            id: Int,
            billing: Open<ProgramItem.Billing>
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

        private var defaultBillingForNewContribution: Open<ProgramItem.Billing> {
            contributions.contains { $0.billing == .known(.primary) }
                ? .known(.supporting)
                : .known(.primary)
        }

        private func generatedPerformanceTitle() -> String {
            primaryContributions
                .compactMap { contribution in
                    contribution.creditName ?? contributorRelationshipPicker
                        .summary(for: contribution.selection)?
                        .title
                        .nilIfEmpty
                }
                .joined(separator: " b2b ")
        }

        private mutating func loadContributions(
            _ credits: [ProgramItem.Credit]
        ) {
            for contributor in credits {
                let selection: ContributorRelationshipPicker.Selection = contributor.contributor
                    .map(ContributorRelationshipPicker.Selection.existingContributor)
                    ?? .performanceDisplayName(name: contributor.name)
                let roleSelection = contributor.role.map(RelationshipRoleSelection.init(role:))
                appendContribution(
                    selection: selection,
                    billing: contributor.billing,
                    roleSelection: roleSelection,
                    customRelationshipRole: roleSelection == .custom ? contributor.role ?? "" : "",
                    creditName: contributor.name
                )
            }
        }

    }

    public enum Action {
        case addExternalMediaButtonTapped
        case addImageButtonTapped
        case addRecordMediaButtonTapped
        case contributionBillingButtonTapped(
            Int,
            Open<ProgramItem.Billing>
        )
        case contributionCustomRoleChanged(Int, String)
        case contributionDeleteButtonTapped(Int)
        case contributionEditButtonTapped(Int)
        case contributionEditDoneButtonTapped
        case contributionMoveButtonTapped(Int, Int)
        case contributionNameChanged(Int, String)
        case contributionRoleButtonTapped(Int, State.RelationshipRoleSelection?)
        case contributorRelationshipPicker(ContributorRelationshipPicker.Action)
        case destination(Destination.Action)
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
        case programChanged(Program.ID?)
        case saveButtonTapped
        case titleTextChanged(String)
    }

    @Feature
    public enum Destination {
        case imageInfo(Spawn<ImageInfo>)
        case importImages(Spawn<ImportImages>)
    }

    public var body: some Feature {
        Scope(\.contributorRelationshipPicker) {
            ContributorRelationshipPicker()
        }
        Update { state, action in
            switch action {
            case .addExternalMediaButtonTapped:
                state.mediaDraft = State.MediaDraft(kind: .external)

            case .addImageButtonTapped:
                state.destination = .importImages(
                    Spawn(ImportImages.State(configuration: .programItemImages))
                )

            case .addRecordMediaButtonTapped:
                state.mediaDraft = State.MediaDraft(kind: .record)

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

            case let .contributionEditButtonTapped(id):
                state.editContribution(id: id)

            case .contributionEditDoneButtonTapped:
                state.editingContributionID = nil

            case let .contributionMoveButtonTapped(id, offset):
                state.moveContribution(id: id, offset: offset)

            case let .contributionNameChanged(id, name):
                state.setContributionName(id: id, name: name)

            case .destination:
                break

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

            case let .programChanged(programID):
                state.selectProgram(programID)

            case .saveButtonTapped:
                guard !state.isSaving else { return }
                guard let validationMessage = state.validationMessage else {
                    guard let programID = state.selectedProgramID else {
                        state.errorMessage = "Choose a program."
                        return
                    }

                    state.errorMessage = nil
                    state.isSaving = true
                    let request = ProgramItemFormSaveRequest(
                        state: state,
                        programID: programID
                    )
                    let createdAt = now

                    store.addTask {
                        do {
                            try database.write { db in
                                try ProgramItemFormDrafts.save(request, createdAt: createdAt, in: db)
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
        .ifLet(\.destination) {
            EmptyFeature()
                .ifCaseLet(\.importImages) { ImportImages() }
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
        }
        .onEvent(ImportedImagesSubmitted.self) { images, state in
            guard case .importImages = state.destination else { return }
            state.mediaEntries.append(contentsOf: images.map { State.MediaEntry(importedImage: $0) })
        }
    }

}

fileprivate struct ProgramItemFormSaveRequest: Sendable {
    let contributions: [ProgramItemForm.State.Contribution]
    let description: String?
    let endTime: Date?
    let eventID: Event.ID
    let mediaEntries: [ProgramItemForm.State.MediaEntry]
    let performanceID: ProgramItem.ID?
    let programID: Program.ID
    let scheduleID: Schedule.ID?
    let stageID: EventPlace.ID?
    let startTime: Date?
    let title: String

    init(state: ProgramItemForm.State, programID: Program.ID) {
        contributions = state.contributions
        description = state.trimmedDescription.nilIfEmpty
        endTime = state.isAssignedToSchedule && state.hasStartTime && state.hasEndTime
            ? state.endTimeSelection : nil
        eventID = state.eventID
        mediaEntries = state.mediaEntries
        performanceID = state.performanceID
        self.programID = programID
        scheduleID = state.isAssignedToSchedule ? state.selectedScheduleID : nil
        stageID = state.selectedStageID
        startTime = state.isAssignedToSchedule && state.hasStartTime
            ? state.startTimeSelection : nil
        title = state.trimmedTitle
    }

    var errorMessage: String {
        performanceID == nil ? "Unable to create performance." : "Unable to save performance."
    }

    func preparedMedia() throws -> [Open<OME.Media>]? {
        try RecordMediaEditing.preparedMedia(mediaEntries)
    }
}

fileprivate enum ProgramItemFormDrafts {
    static func save(
        _ request: ProgramItemFormSaveRequest,
        createdAt: Date,
        in db: Database
    ) throws {
        let credits = try request.contributions.compactMap {
            try credit(for: $0, eventID: request.eventID, createdAt: createdAt, in: db)
        }
        let start = request.startTime.map {
            ATProto.DateTime(rawValue: ISO8601DateFormatter().string(from: $0))
        }
        let end = request.endTime.map {
            ATProto.DateTime(rawValue: ISO8601DateFormatter().string(from: $0))
        }
        var fields: ProgramItemRecordEditing.Fields
        if let performanceID = request.performanceID {
            guard let item = try ProgramItem.find(performanceID).fetchOne(db),
                  item.event == request.eventID
            else { throw ProgramItemFormSaveError() }
            fields = ProgramItemRecordEditing.Fields(item)
        } else {
            fields = ProgramItemRecordEditing.Fields(
                program: request.programID,
                title: request.title
            )
        }
        fields.program = request.programID
        fields.title = request.title
        fields.description = request.description
        fields.schedule = request.scheduleID
        fields.eventPlace = request.stageID
        fields.startsAt = start
        fields.endsAt = end
        fields.credits = credits.isEmpty ? nil : credits
        fields.media = try request.preparedMedia()

        if let performanceID = request.performanceID {
            try ProgramItemRecordEditing.update(
                performanceID,
                eventID: request.eventID,
                fields: fields,
                in: db
            )
        } else {
            _ = try ProgramItemRecordEditing.create(
                eventID: request.eventID,
                fields: fields,
                createdAt: createdAt,
                in: db
            )
        }
    }

    private static func credit(
        for contribution: ProgramItemForm.State.Contribution,
        eventID: Event.ID,
        createdAt: Date,
        in db: Database
    ) throws -> ProgramItem.Credit? {
        let name: String
        let contributorID: Contributor.ID?
        switch contribution.selection {
        case .none:
            return nil

        case let .existingContributor(id):
            guard let contributor = try Contributor.find(id).fetchOne(db),
                  contributor.event == eventID
            else { throw ContributorRecordEditing.Error.contributorUnavailable }
            name = contribution.creditName ?? contributor.name
            contributorID = id

        case let .identityOnly(actor, displayTitle):
            name = contribution.creditName ?? displayTitle ?? actor.description
            contributorID = try resolvedContributorID(
                for: actor,
                name: name,
                eventID: eventID,
                createdAt: createdAt,
                in: db
            )

        case let .newContributor(newName):
            name = contribution.creditName ?? newName
            contributorID = try ContributorRecordEditing.create(
                eventID: eventID,
                fields: .init(name: name),
                createdAt: createdAt,
                in: db
            )

        case let .newContributorFromIdentity(identity):
            name = contribution.creditName ?? identity.contributorName
            contributorID = try resolvedContributorID(
                for: identity.did,
                name: name,
                eventID: eventID,
                createdAt: createdAt,
                in: db
            )

        case let .performanceDisplayName(displayName):
            name = contribution.creditName ?? displayName
            contributorID = nil
        }

        return ProgramItem.Credit(
            name: name,
            contributor: contributorID,
            billing: contribution.billing,
            role: contribution.role
        )
    }

    private static func resolvedContributorID(
        for did: DID,
        name: String,
        eventID: Event.ID,
        createdAt: Date,
        in db: Database
    ) throws -> Contributor.ID {
        if let contributor = try Contributor
            .where({ $0.event.eq(eventID) })
            .fetchAll(db)
            .first(where: { $0.subject == did }) {
            return contributor.id
        }
        return try ContributorRecordEditing.create(
            eventID: eventID,
            fields: .init(name: name, subject: did),
            createdAt: createdAt,
            in: db
        )
    }
}

private struct ProgramItemFormSaveError: Error {}

public struct ProgramItemFormView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails
    @Bindable var store: StoreOf<ProgramItemForm>

    public init(store: StoreOf<ProgramItemForm>) {
        self.store = store
    }

    public var body: some View {
        Form {
            lineupSection
            performanceSection
            timeSection
            mediaSection
            messages
        }
        .disabled(store.isSaving)
        .navigationTitle(store.navigationTitle)
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
                    isInProgress: store.isSaving,
                    isDisabled: !store.canSubmit
                ) {
                    store.send(.saveButtonTapped)
                }
            }
        }
        .sheet(item: $store.scope(\.destination).importImages) { importStore in
            NavigationStack { ImportImagesView(store: importStore) }
        }
        .sheet(item: $store.scope(\.destination).imageInfo) { imageInfoStore in
            NavigationStack { ImageInfoView(store: imageInfoStore) }
        }
    }

    private var performanceSection: some View {
        Section("Performance") {
            TextField("Title", text: performanceTitleBinding, prompt: Text("Artist Set"))
            PortableTextField("Description", text: $store.description, axis: .vertical)
                .portableLineLimit(3...8)
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

    private var lineupSection: some View {
        Section("Lineup") {
            if store.programs.count > 1 {
                Picker("Program", selection: programSelection) {
                    ForEach(store.programs) { program in
                        Text(program.title).tag(Optional(program.id))
                    }
                }
            }
            if !store.stageOptions.isEmpty {
                Picker("Place", selection: $store.selectedStageID) {
                    Text("Unplaced").tag(EventPlace.ID?.none)
                    ForEach(store.stageOptions, id: \.rawID) { stage in
                        Text(stage.name).tag(Optional(stage.id))
                    }
                }
            }

            contributionRows(store.contributions)
            ContributorRelationshipPickerRows(
                store: store.scope(\.contributorRelationshipPicker)
            )
        }
    }

    private var timeSection: some View {
        Section("Time") {
            Toggle("Assign festival day", isOn: $store.isAssignedToSchedule)
            if store.isAssignedToSchedule {
                if store.schedules.count > 1 || store.schedule == nil {
                    Picker("Schedule", selection: $store.selectedScheduleID) {
                        Text("Choose a day").tag(Schedule.ID?.none)
                        ForEach(store.schedules) { schedule in
                            Text(ScheduleList.scheduleTitle(schedule, in: store.timeZone))
                                .tag(Optional(schedule.id))
                        }
                    }
                } else if let schedule = store.schedule {
                    LabeledContent(
                        "Schedule",
                        value: ScheduleList.scheduleTitle(schedule, in: store.timeZone)
                    )
                }
                Toggle("Set start time", isOn: $store.hasStartTime)
                if store.hasStartTime {
                    Toggle("Set end time", isOn: $store.hasEndTime)
                    if store.hasEndTime {
                        DateTimeRangePicker(selection: $store.timeRangeSelection)
                    } else {
                        DatePicker(
                            "Starts",
                            selection: $store.timeRangeSelection.startClockTimeSelection,
                            displayedComponents: .hourAndMinute
                        )
                        .environment(\.timeZone, store.timeZone)
                        if store.timeRangeSelection.shouldChooseStartDayExplicitly {
                            Picker("Start Day", selection: $store.timeRangeSelection.startDayOffset) {
                                ForEach(store.timeRangeSelection.startDayOffsetOptions, id: \.self) { offset in
                                    Text(offset == 0 ? "Same day" : offset == 1 ? "Next day" : "Previous day")
                                        .tag(offset)
                                }
                            }
                        }
                    }
                }
            }
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
        _ contributions: [ProgramItemForm.State.Contribution]
    ) -> some View {
        if !contributions.isEmpty {
            ForEach(contributions) { contribution in
                let summary = store.contributorRelationshipPicker.summary(
                    for: contribution.selection,
                    showsTechnicalDetails: showsTechnicalDetails
                )
                ProgramItemFormContributionRow(
                    title: contribution.creditName ?? summary?.title ?? "Contributor",
                    subtitle: summary?.subtitle,
                    isPrimary: contribution.billing == .known(.primary),
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
                    if contribution.billing != .known(.primary) {
                        Button {
                            store.send(
                                .contributionBillingButtonTapped(
                                    contribution.id,
                                    .known(.primary)
                                )
                            )
                        } label: {
                            Label("Primary", systemImage: "star.fill")
                        }
                    }
                }
                .contextMenu {
                    Button("Edit") {
                        store.send(.contributionEditButtonTapped(contribution.id))
                    }
                    let index = store.contributions.firstIndex(where: { $0.id == contribution.id })
                    if let index, index > 0 {
                        Button("Move Up") {
                            store.send(.contributionMoveButtonTapped(contribution.id, -1))
                        }
                    }
                    if let index, index + 1 < store.contributions.count {
                        Button("Move Down") {
                            store.send(.contributionMoveButtonTapped(contribution.id, 1))
                        }
                    }
                    if contribution.billing == .known(.primary) {
                        Button("Remove as primary") {
                            store.send(
                                .contributionBillingButtonTapped(
                                    contribution.id,
                                    .known(.supporting)
                                )
                            )
                        }
                    } else {
                        Button("Set as primary") {
                            store.send(
                                .contributionBillingButtonTapped(
                                    contribution.id,
                                    .known(.primary)
                                )
                            )
                        }
                    }
                    Button("Delete", role: .destructive) {
                        store.send(.contributionDeleteButtonTapped(contribution.id))
                    }
                }

                if store.editingContributionID == contribution.id {
                    HStack {
                        TextField(
                            "Credit Name",
                            text: contributionNameBinding(for: contribution.id)
                        )
                        Button("Done") {
                            store.send(.contributionEditDoneButtonTapped)
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

    private func contributionNameBinding(for id: Int) -> Binding<String> {
        Binding(
            get: { store.contributions.first(where: { $0.id == id })?.creditName ?? "" },
            set: { store.send(.contributionNameChanged(id, $0)) }
        )
    }

    private var programSelection: Binding<Program.ID?> {
        Binding(
            get: { store.selectedProgramID },
            set: { store.send(.programChanged($0)) }
        )
    }

    @ViewBuilder
    private var messages: some View {
        if store.mediaDraft == nil, let validationMessage = store.validationMessage {
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

struct ProgramItemFormContributionRow: View {
    let title: String
    let subtitle: String?
    let isPrimary: Bool
    let roleTitle: String
    let roleSelection: ProgramItemForm.State.RelationshipRoleSelection?
    let roleChanged: (ProgramItemForm.State.RelationshipRoleSelection?) -> Void

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
                    .tag(ProgramItemForm.State.RelationshipRoleSelection?.none)
                ForEach(
                    ProgramItemForm.State.RelationshipRoleSelection.allCases,
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

    private var roleSelectionBinding: Binding<ProgramItemForm.State.RelationshipRoleSelection?> {
        Binding(
            get: { roleSelection },
            set: { roleChanged($0) }
        )
    }

    private func title(
        for role: ProgramItemForm.State.RelationshipRoleSelection
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
