import Foundation
import OpenMusicEventImages
import OpenMusicEventLexicon
import OpenMusicEventSourceEditing
#if os(Android)
import SkipSwiftUI
#else
import SwiftUI
#endif

struct WorkspaceChangeSummarySection: View {
    let changes: [CanonicalWorkspaceRecordChange]
    var title: String = "What changed"
    var emptyMessage: String = "No local changes."

    var body: some View {
        Section(title) {
            if changes.isEmpty {
                Text(emptyMessage).foregroundStyle(.secondary)
            }
            ForEach(Array(Set(changes.map(\.collectionTitle))).sorted(), id: \.self) { group in
                DisclosureGroup {
                    ForEach(changes.filter { $0.collectionTitle == group }, id: \.id) { change in
                        WorkspaceRecordChangeView(change: change)
                    }
                } label: {
                    HStack {
                        Text(group)
                        Spacer()
                        let count = changes.filter { $0.collectionTitle == group }.count
                        Text(count == 1 ? "1 change" : "\(count) changes")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("workspace.changes.\(group)")
            }
        }
    }
}

struct WorkspaceRecordChangeView: View {
    let change: CanonicalWorkspaceRecordChange

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(change.kind == .added ? "Added" : change.kind == .deleted ? "Deleted" : "Edited")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(change.kind == .deleted ? .red : .secondary)
                Text(change.title).font(.headline)
            }
            if change.kind == .edited && change.before == nil {
                Text("The previous publication was verified, but its content was not saved for comparison. Current content is shown below.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(change.fields) { field in
                VStack(alignment: .leading, spacing: 6) {
                    Text(field.title).font(.subheadline.weight(.semibold))
                    if let before = field.before {
                        WorkspaceChangeValueView(
                            label: change.kind == .deleted ? "Removed" : "Before",
                            value: before, recordID: change.id
                        )
                    }
                    if let after = field.after {
                        WorkspaceChangeValueView(
                            label: change.kind == .added ? "Added" : "After",
                            value: after, recordID: change.id
                        )
                    } else if change.kind == .edited {
                        Text("After: Not set").foregroundStyle(.secondary)
                    }
                }
            }
            DisclosureGroup("Technical details") {
                Text(change.id.description).font(.caption).textSelection(.enabled)
                Text(change.collection).font(.caption).textSelection(.enabled)
                if let before = change.before {
                    Text(String(describing: before)).font(.caption).textSelection(.enabled)
                }
                if let after = change.after {
                    Text(String(describing: after)).font(.caption).textSelection(.enabled)
                }
            }
            .font(.caption)
            .accessibilityIdentifier("workspace.change.technical.\(change.id.description)")
        }
        .padding(.vertical, 6)
    }
}

struct WorkspaceChangeValueView: View {
    let label: String
    let value: CanonicalWorkspaceRecordChange.Value
    let recordID: Event.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            ForEach(Array(value.lines.enumerated()), id: \.offset) { _, line in
                Text(line)
            }
            ForEach(Array(value.images.enumerated()), id: \.offset) { _, image in
                ImageAssetAsyncImage(image: .record(image, recordID)) { ProgressView() }
                    .frame(height: 150)
                    .accessibilityLabel(image.alt?.rawValue ?? image.title ?? "Event image")
            }
        }
    }
}
