import ComposableArchitecture2
import Dependencies
import Foundation
import SQLiteData
import SwiftUI
import Tagged

@Feature
public struct EditPerformance {
    public init() {}

    @Dependency(\.defaultDatabase) var database

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

        public init(
            eventID: OMERecord.Event.ID,
            schedule: OMERecord.Schedule,
            stages: [OMERecord.Stage],
            timeZone: TimeZone
        ) {
            self.endTimeSelection = schedule.date.at(hour: 13, in: timeZone)
                ?? schedule.date.atStartOfDay(in: timeZone)
            self.eventID = eventID
            self.schedule = schedule
            self.selectedStageID = stages.first?.id.stageID
            self.stageOptions = stages.map(StageOption.init)
            self.startTimeSelection = schedule.date.at(hour: 12, in: timeZone)
                ?? schedule.date.atStartOfDay(in: timeZone)
            self.timeZone = timeZone
        }

        public init(
            eventID: OMERecord.Event.ID,
            schedule: OMERecord.Schedule,
            stages: [OMERecord.Stage],
            timeZone: TimeZone,
            performance: OMERecord.Performance
        ) {
            self.init(
                eventID: eventID,
                schedule: schedule,
                stages: stages,
                timeZone: timeZone
            )
            self.description = performance.description ?? ""
            self.endTimeSelection = performance.endTime
            self.performanceID = performance.id.performanceID
            self.selectedStageID = performance.stageID
            self.startTimeSelection = performance.startTime
            self.title = performance.title
        }

        public let eventID: OMERecord.Event.ID
        public let schedule: OMERecord.Schedule
        public let stageOptions: [StageOption]
        @DebugSnapshotIgnored
        public let timeZone: TimeZone

        public var anonymousContributorName = ""
        public var contributorIDString = ""
        public var description = ""
        public var endTimeSelection: Date
        public var errorMessage: String?
        public var isSaving = false
        public var performanceID: OMERecord.ID<OMERecord.Performance>?
        public var selectedStageID: OMERecord.ID<OMERecord.Stage>?
        public var startTimeSelection: Date
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

        public var trimmedAnonymousContributorName: String {
            anonymousContributorName.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        public var trimmedContributorIDString: String {
            contributorIDString.trimmingCharacters(in: .whitespacesAndNewlines)
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
            if isCreating,
               !trimmedContributorIDString.isEmpty,
               !Self.isValidLocalID(trimmedContributorIDString) {
                return "Use a contributor ID like artist-name."
            }
            return nil
        }

        private static func isValidLocalID(_ value: String) -> Bool {
            !value.isEmpty
                && value != "."
                && value != ".."
                && !value.contains("/")
                && !value.contains("\\")
        }
    }

    public enum Action {
        case saveButtonTapped
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
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
                        stageID: stageID
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
            }
        }
    }
}

fileprivate struct EditPerformanceSaveRequest: Sendable {
    var anonymousContributorName: String?
    var contributorIDString: String?
    var description: String?
    var endTime: Date
    var eventID: OMERecord.Event.ID
    var performanceID: OMERecord.ID<OMERecord.Performance>?
    var scheduleID: OMERecord.ID<OMERecord.Schedule>
    var stageID: OMERecord.ID<OMERecord.Stage>
    var startTime: Date
    var title: String

    init(state: EditPerformance.State, stageID: OMERecord.ID<OMERecord.Stage>) {
        self.anonymousContributorName = state.trimmedAnonymousContributorName.nilIfEmpty
        self.contributorIDString = state.trimmedContributorIDString.nilIfEmpty
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
        if let contributorIDString = request.contributorIDString {
            drafts.append(
                OMERecord.Performance.Contributors.Draft(
                    organizerID: request.eventID.organizerID,
                    eventID: request.eventID.eventID,
                    performanceID: performanceID,
                    contributorID: OMERecord.ID<OMERecord.Contributor>(.init(contributorIDString)),
                    anonymousName: nil,
                    contributorActor: nil
                )
            )
        }
        if let anonymousContributorName = request.anonymousContributorName {
            drafts.append(
                OMERecord.Performance.Contributors.Draft(
                    organizerID: request.eventID.organizerID,
                    eventID: request.eventID.eventID,
                    performanceID: performanceID,
                    contributorID: nil,
                    anonymousName: anonymousContributorName,
                    contributorActor: nil
                )
            )
        }
        return drafts
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
    @Bindable var store: StoreOf<EditPerformance>

    public init(store: StoreOf<EditPerformance>) {
        self.store = store
    }

    public var body: some View {
        Form {
            performanceSection
            stageSection
            timeSection
            if store.isCreating {
                contributorSection
            }
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
            TextField("Title", text: $store.title, prompt: Text("Main Stage Set"))
            TextField("Description", text: $store.description, axis: .vertical)
                .lineLimit(3...8)
        }
    }

    private var stageSection: some View {
        Section("Stage") {
            Picker("Stage", selection: $store.selectedStageID) {
                ForEach(store.stageOptions, id: \.rawID) { stage in
                    Text(stage.name).tag(Optional(stage.id))
                }
            }
        }
    }

    private var timeSection: some View {
        Section("Time") {
            DatePicker(
                "Starts",
                selection: $store.startTimeSelection,
                displayedComponents: .hourAndMinute
            )
            .environment(\.timeZone, store.timeZone)

            DatePicker(
                "Ends",
                selection: $store.endTimeSelection,
                displayedComponents: .hourAndMinute
            )
            .environment(\.timeZone, store.timeZone)
        }
    }

    private var contributorSection: some View {
        Section("Contributor") {
            TextField("Contributor ID", text: $store.contributorIDString, prompt: Text("artist-name"))
                #if !os(macOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
            TextField("Name", text: $store.anonymousContributorName, prompt: Text("Guest Artist"))
        }
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
