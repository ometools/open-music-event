import ComposableArchitecture2
import OpenMusicEventSourceEditing
import SQLiteData
import SwiftUI

@Feature
public struct EditEvent {
    public init() {}

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
    }

    public enum Action {}

    public var body: some Feature {
        Update { _, _ in }
    }
}

public struct EditEventView: View {
    let store: StoreOf<EditEvent>

    public init(store: StoreOf<EditEvent>) {
        self.store = store
    }

    public var body: some View {
        Group {
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
                            Label("Changes", systemImage: "pencil.and.list.clipboard")
                            Spacer()
                            Text(store.editSummary.totalCount, format: .number)
                                .font(.headline)
                                .monospacedDigit()
                        }
                    }

                    Section("Records") {
                        ForEach(store.editSummary.groups.filter { $0.totalCount > 0 }) { group in
                            SourceChangeGroupRow(group: group)
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
        .navigationTitle("Edit")
    }
}

struct SourceChangeGroupRow: View {
    let group: SourceChangeGroup

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(group.displayName)
                Text(group.changeSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(group.totalCount, format: .number)
                .font(.headline)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }
}

private extension SourceChangeGroup {
    var changeSummary: String {
        [
            changeSummaryPart(count: added, name: "added"),
            changeSummaryPart(count: modified, name: "modified"),
            changeSummaryPart(count: deleted, name: "deleted"),
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    func changeSummaryPart(count: Int, name: String) -> String? {
        guard count > 0 else { return nil }
        return "\(count) \(name)"
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
