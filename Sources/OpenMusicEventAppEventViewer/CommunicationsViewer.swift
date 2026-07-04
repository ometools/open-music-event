import ComposableArchitecture2
import Foundation
import SQLiteData
import SwiftUI

@Feature
public struct CommunicationsViewer {
    public init() {}

    public struct State {
        public let eventID: OMERecord.Event.ID
        @FetchOne public var event: OMERecord.Event?

        public init(eventID: OMERecord.Event.ID) {
            self.eventID = eventID
            _event = FetchOne(OMERecord.Event.where { $0.id.eq(eventID) })
        }
    }

    public enum Action {}

    public var body: some Feature {
        Update { _, _ in }
    }
}

public struct CommunicationsViewerView: View {
    let store: StoreOf<CommunicationsViewer>

    public init(store: StoreOf<CommunicationsViewer>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if let reportingLink = store.event?.reportingLink {
                List {
                    Section("Incident Reporting") {
                        Link(destination: reportingLink.url) {
                            ReportingLinkLabel(reportingLink: reportingLink)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens this event's reporting link in a browser.")
                    }

                    Section {
                        Text("No communication channels have been added to this event yet.")
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Comms")
            } else {
                ViewerPlaceholderView(
                    title: "Comms",
                    systemImage: "megaphone",
                    description: store.event == nil
                        ? "This event could not be loaded."
                        : "No communication channels have been added to this event yet."
                )
            }
        }
    }
}

struct ReportingLinkLabel: View {
    let reportingLink: OMERecord.Event.ReportingLink

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(reportingLink.name)
                .font(.headline.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .background(.red, in: RoundedRectangle(cornerRadius: 8))

            if let description = reportingLink.displayDescription {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

private extension OMERecord.Event.ReportingLink {
    var displayDescription: String? {
        guard let description else { return nil }

        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
