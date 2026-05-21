import ComposableArchitecture2
import Foundation
import GRDB
import OpenMusicEventSourceEditing
import SourceEditing
import SQLiteData
import SwiftUI

@Feature
public struct EditEvent {
    public init() {}

    public enum ChangeView: Hashable, CaseIterable, Sendable {
        case database
        case source
    }

    public enum SourcePatchStatus: Equatable, Sendable {
        case failed(SourcePatchGenerationFailure)
        case generated(SourcePatch)
        case generating
        case needsGeneration(SourcePatchInvalidation)
        case notGenerated
    }

    public struct SourcePatchGenerationFailure: Equatable, Error, Sendable {
        public var message: String

        public init(_ error: any Error) {
            self.message = String(describing: error)
        }
    }

    public struct State {
        public init(eventID: OMERecord.Event.ID) {
            self.eventID = eventID
            self._editSummary = Fetch(
                wrappedValue: EventEditSummary(
                    eventID: eventID,
                    availability: .notSourceBacked,
                    groups: []
                ),
                EventEditSummaryRequest(eventID: eventID)
            )
        }

        public let eventID: OMERecord.Event.ID
        @DebugSnapshotIgnored
        @Fetch public var editSummary: EventEditSummary
        public var selectedChangeView: ChangeView = .database
        public var sourcePatchStatus: SourcePatchStatus = .notGenerated

        public var changeCount: Int? {
            editSummary.badgeCount
        }
    }

    public enum Action {
        case generateSourcePatchButtonTapped
        case sourcePatchGenerationResponse(Result<SourcePatch, SourcePatchGenerationFailure>)
        case sourcePatchInvalidationReceived(SourcePatchInvalidation)
    }

    @Dependency(SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self) var sourcePatchGenerator
    @Dependency(\.sourcePatchInvalidations) var sourcePatchInvalidations
    public var body: some Feature {
        Update { state, action in
            func generateSourcePatch(
                eventID: OMERecord.Event.ID,
                state: inout State
            ) {
                let sourcePatchGenerator = sourcePatchGenerator
                state.sourcePatchStatus = .generating
                store.addTask {
                    do {
                        let patch = try await sourcePatchGenerator.generate(
                            OpenMusicEventSourcePatchRequest(eventID: eventID)
                        )
                        try store.send(.sourcePatchGenerationResponse(.success(patch)))
                    } catch {
                        try store.send(
                            .sourcePatchGenerationResponse(
                                .failure(SourcePatchGenerationFailure(error))
                            )
                        )
                    }
                }
            }

            switch action {
            case .generateSourcePatchButtonTapped:
                generateSourcePatch(eventID: state.eventID, state: &state)

            case let .sourcePatchGenerationResponse(.success(patch)):
                state.sourcePatchStatus = .generated(patch)

            case let .sourcePatchGenerationResponse(.failure(failure)):
                state.sourcePatchStatus = .failed(failure)

            case let .sourcePatchInvalidationReceived(invalidation):
                state.sourcePatchStatus = .needsGeneration(invalidation)
                guard state.selectedChangeView == .source else { return }
                generateSourcePatch(eventID: state.eventID, state: &state)
            }
        }
        .onChange(of: store.selectedChangeView) { state in
            guard state.selectedChangeView == .source else { return }
            store.addTask {
                try store.send(.generateSourcePatchButtonTapped)
            }
        }
        .onMount { state in
            let eventID = state.eventID
            store.addTask {
                for await invalidation in sourcePatchInvalidations.stream() {
                    guard invalidation.eventID == eventID else { continue }
                    try store.send(.sourcePatchInvalidationReceived(invalidation))
                }
            }
        }
    }
}

public struct EditEventView: View {
    @Bindable var store: StoreOf<EditEvent>

    public init(store: StoreOf<EditEvent>) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker("Changes", selection: $store.selectedChangeView) {
                ForEach(EditEvent.ChangeView.allCases, id: \.self) { changeView in
                    Text(changeView.title).tag(changeView)
                }
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top])
            .padding(.bottom, 8)

            Group {
                switch store.selectedChangeView {
                case .database:
                    databaseChangesContent
                case .source:
                    sourceChangesContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Edit")
    }

    @ViewBuilder
    private var databaseChangesContent: some View {
        switch store.editSummary.availability {
        case .available where store.editSummary.totalCount == 0:
            ContentUnavailableView(
                "No Changes",
                systemImage: "checkmark.circle"
            )

        case .available:
            List {
                Section {
                    HStack {
                        Label("Database Changes", systemImage: "pencil.and.list.clipboard")
                        Spacer()
                        Text(store.editSummary.totalCount, format: .number)
                            .font(.headline)
                            .monospacedDigit()
                    }
                }

                ForEach(store.editSummary.groups.filter { !$0.records.isEmpty }) { group in
                    SourceChangeGroupSections(group: group)
                }
            }

        case .missingBaseline:
            ContentUnavailableView(
                "Baseline Missing",
                systemImage: "externaldrive.badge.questionmark"
            )

        case .notSourceBacked:
            ContentUnavailableView(
                "Not Source Backed",
                systemImage: "doc.badge.ellipsis"
            )

        case let .unavailable(reason):
            SourceChangeUnavailableView(reason: reason)
        }
    }

    @ViewBuilder
    private var sourceChangesContent: some View {
        switch store.editSummary.availability {
        case .available:
            List {
                Section {
                    HStack {
                        Label("Source Patch", systemImage: "doc.text")
                        if let fileChangeCount = store.sourcePatchStatus.fileChangeCount {
                            Spacer()
                            Text(fileChangeCount, format: .number)
                                .font(.headline)
                                .monospacedDigit()
                        }
                    }
                }

                Section {
                    Label("Patch Preview", systemImage: "doc.text.magnifyingglass")
                    SourcePatchStatusView(status: store.sourcePatchStatus)

                    Button {
                        store.send(.generateSourcePatchButtonTapped)
                    } label: {
                        Label(
                            store.sourcePatchStatus.generationButtonTitle,
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                    .disabled(store.sourcePatchStatus.isGenerating)
                }

                if case let .generated(patch) = store.sourcePatchStatus {
                    if patch.isEmpty {
                        Section {
                            Label("No File Changes", systemImage: "checkmark.circle")
                        }
                    } else {
                        Section("Files") {
                            ForEach(patch.fileChanges) { change in
                                SourcePatchFileChangeRow(change: change)
                            }
                        }
                    }
                }
            }

        case .missingBaseline:
            ContentUnavailableView(
                "Baseline Missing",
                systemImage: "externaldrive.badge.questionmark"
            )

        case .notSourceBacked:
            ContentUnavailableView(
                "Not Source Backed",
                systemImage: "doc.badge.ellipsis"
            )

        case let .unavailable(reason):
            SourceChangeUnavailableView(reason: reason)
        }
    }
}

struct SourcePatchStatusView: View {
    let status: EditEvent.SourcePatchStatus

    var body: some View {
        switch status {
        case let .failed(failure):
            VStack(alignment: .leading, spacing: 4) {
                Text("Generation Failed")
                Text(failure.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

        case let .generated(patch):
            HStack {
                Text("Generated")
                Spacer()
                Text(patch.fileChanges.count, format: .number)
                    .font(.headline)
                    .monospacedDigit()
            }

        case .generating:
            HStack(spacing: 8) {
                ProgressView()
                Text("Generating")
            }

        case let .needsGeneration(invalidation):
            VStack(alignment: .leading, spacing: 4) {
                Text("Needs Generation")
                Text("\(invalidation.operation.title) \(invalidation.tableName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .notGenerated:
            Text("Not Generated")
                .foregroundStyle(.secondary)
        }
    }
}

struct SourcePatchFileChangeRow: View {
    let change: SourcePatchFileChange

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(change.kind.title, systemImage: change.kind.systemImage)
                .font(.caption)
                .foregroundStyle(change.kind.tint)

            Text(change.path)
                .font(.caption)
                .monospaced()
                .textSelection(.enabled)

            if let oldContents = change.oldContents {
                SourcePatchFileContentsPreview(
                    title: "Old",
                    data: oldContents
                )
            }

            if let newContents = change.newContents {
                SourcePatchFileContentsPreview(
                    title: "New",
                    data: newContents
                )
            }
        }
        .padding(.vertical, 4)
    }
}

struct SourcePatchFileContentsPreview: View {
    let title: String
    let data: Data

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(data.sourcePatchPreview)
                .font(.caption)
                .monospaced()
                .lineLimit(12)
                .textSelection(.enabled)
        }
    }
}

private extension SourcePatchInvalidation.Operation {
    var title: String {
        switch self {
        case .delete:
            "Deleted"
        case .insert:
            "Inserted"
        case .update:
            "Updated"
        }
    }
}

private extension EditEvent.SourcePatchStatus {
    var generationButtonTitle: String {
        switch self {
        case .generated:
            "Regenerate Patch"
        case .generating:
            "Generating Patch"
        default:
            "Generate Patch"
        }
    }

    var isGenerating: Bool {
        self == .generating
    }

    var fileChangeCount: Int? {
        guard case let .generated(patch) = self else { return nil }
        return patch.fileChanges.count
    }
}

private extension EditEvent.ChangeView {
    var title: String {
        switch self {
        case .database:
            "Database"
        case .source:
            "Source"
        }
    }
}

private extension SourcePatchFileChange.Kind {
    var systemImage: String {
        switch self {
        case .added:
            "plus.circle"
        case .deleted:
            "minus.circle"
        case .modified:
            "pencil.circle"
        }
    }

    var tint: Color {
        switch self {
        case .added:
            .green
        case .deleted:
            .red
        case .modified:
            .orange
        }
    }

    var title: String {
        switch self {
        case .added:
            "Added"
        case .deleted:
            "Deleted"
        case .modified:
            "Modified"
        }
    }
}

private extension Data {
    var sourcePatchPreview: String {
        guard let text = String(data: self, encoding: .utf8) else {
            return "<binary \(count) bytes>"
        }
        guard !text.isEmpty else { return "<empty>" }
        guard text.count > 1_200 else { return text }
        return "\(String(text.prefix(1_200)))\n..."
    }
}

struct SourceChangeGroupSections: View {
    let group: SourceChangeGroup

    var body: some View {
        ForEach(kinds, id: \.self) { kind in
            SourceChangeKindSection(
                title: "\(kind.title) \(group.displayName)",
                records: records(for: kind)
            )
        }
    }

    private var kinds: [SourceRecordChangeKind] {
        SourceRecordChangeKind.allCases.filter { kind in
            group.records.contains { $0.kind == kind }
        }
    }

    private func records(for kind: SourceRecordChangeKind) -> [SourceRecordChange] {
        group.records.filter { $0.kind == kind }
    }
}

struct SourceChangeKindSection: View {
    let title: String
    let records: [SourceRecordChange]

    var body: some View {
        Section(title) {
            ForEach(records) { record in
                SourceRecordChangeRow(record: record)
            }
        }
    }
}

struct SourceRecordChangeRow: View {
    let record: SourceRecordChange

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.kind.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(record.primaryKeySummary)
                    .font(.caption)
                    .monospaced()
                    .foregroundStyle(.secondary)
            }

            if let recordDiff = record.recordDiff, !recordDiff.isEmpty {
                Text(recordDiff)
                    .font(.caption)
                    .monospaced()
                    .textSelection(.enabled)
            } else {
                ForEach(record.fieldChanges) { change in
                    SourceFieldChangeRow(change: change)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct SourceFieldChangeRow: View {
    let change: SourceFieldChange

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(change.columnName)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(change.baselineValue.sourceDisplayValue) -> \(change.workingValue.sourceDisplayValue)")
                .font(.caption)
                .monospaced()
                .textSelection(.enabled)
        }
    }
}

private extension SourceRecordChangeKind {
    var title: String {
        switch self {
        case .added:
            "Added"
        case .modified:
            "Modified"
        case .deleted:
            "Deleted"
        }
    }
}

private extension SourceRecordChange {
    var primaryKeySummary: String {
        primaryKeyValues
            .map { "\($0.columnName)=\($0.value.sourceDisplayValue)" }
            .joined(separator: ", ")
    }
}

private extension Optional where Wrapped == DatabaseValue {
    var sourceDisplayValue: String {
        switch self {
        case let .some(value):
            value.sourceDisplayValue
        case .none:
            "missing"
        }
    }
}

private extension DatabaseValue {
    var sourceDisplayValue: String {
        switch storage {
        case .null:
            "NULL"
        case let .int64(value):
            "\(value)"
        case let .double(value):
            "\(value)"
        case let .string(value):
            value.sourceStringDisplayValue
        case let .blob(data):
            "<blob \(data.count) bytes>"
        }
    }
}

private extension String {
    var sourceStringDisplayValue: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isLikelyJSON {
            return "<json \(utf8.count) bytes>"
        }
        if count > 240 {
            return "\(String(prefix(160)).debugDescription) ... <\(utf8.count) bytes>"
        }
        return debugDescription
    }
}

private extension String {
    var isLikelyJSON: Bool {
        (hasPrefix("{") && hasSuffix("}"))
            || (hasPrefix("[") && hasSuffix("]"))
    }
}

struct SourceChangeUnavailableView: View {
    let reason: SourceChangeSummary.UnavailableReason

    var body: some View {
        switch reason {
        case let .schemaMismatch(mismatches):
            List {
                Section {
                    Label("Schema Mismatch", systemImage: "exclamationmark.triangle")
                }

                Section("Missing Columns") {
                    ForEach(mismatches) { mismatch in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mismatch.tableName)
                            Text(mismatch.missingColumnNames.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}
