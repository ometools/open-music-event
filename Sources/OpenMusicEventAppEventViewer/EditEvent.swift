import ComposableArchitecture2
import Foundation
import GRDB
import OpenMusicEventSourceEditing
import SQLiteData
import SwiftUI

@Feature
public struct EditEvent {
    public init() {}

    public enum ChangeView: Hashable, CaseIterable, Sendable {
        case database
        case source
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

        public var changeCount: Int? {
            editSummary.badgeCount
        }
    }

    public enum Action {}

    public var body: some Feature {
        Update { _, _ in }
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
        case .available where store.editSummary.totalCount == 0:
            ContentUnavailableView(
                "No Source Changes",
                systemImage: "checkmark.circle"
            )

        case .available:
            List {
                Section {
                    HStack {
                        Label("Source Changes", systemImage: "doc.text")
                        Spacer()
                        Text(store.editSummary.totalCount, format: .number)
                            .font(.headline)
                            .monospacedDigit()
                    }
                }

                Section {
                    Label("Patch Preview", systemImage: "doc.text.magnifyingglass")
                    Text("Not Generated")
                        .foregroundStyle(.secondary)
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
