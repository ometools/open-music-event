import OpenMusicEventLexicon
import HeroImageList
import ComposableArchitecture2
import Dependencies
import Foundation
import ATProtoTypes
import OpenMusicEventComponents
import OpenMusicEventEditors
import OpenMusicEventImages
import SQLiteData
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

@Feature
public struct EventInfoViewer {
    public init() {}

    public struct State {
        public let eventID: Event.ID
        @FetchOne public var event: Event?
        public var destination: Destination.State?

        public init(eventID: Event.ID) {
            self.eventID = eventID
            _event = FetchOne(
                Event.where { $0.id.eq(eventID) }
            )
        }
    }

    public enum Action {
        case aboutOpenMusicEventButtonTapped
        case destination(Destination.Action)
    }

    @Feature
    public enum Destination {
        case aboutOpenMusicEvent(AboutOpenMusicEvent)
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .aboutOpenMusicEventButtonTapped:
                state.destination = .aboutOpenMusicEvent(
                    AboutOpenMusicEvent.State(eventID: state.eventID)
                )

            case .destination:
                break


            }
        }
        .ifLet(\.destination) {
            Destination.body
        }
    }
}

public struct EventInfoViewerView: View {
    @Bindable var store: StoreOf<EventInfoViewer>
    let showsAuthoringControls: Bool
    let onEdit: () -> Void

    public init(
        store: StoreOf<EventInfoViewer>,
        showsAuthoringControls: Bool,
        onEdit: @escaping () -> Void
    ) {
        self.store = store
        self.showsAuthoringControls = showsAuthoringControls
        self.onEdit = onEdit
    }

    public var body: some View {
        Group {
            if let event = store.event {
                let heroImageSources = event.heroImageSources
                let heroImageTitleSources = event.heroImageTitleSources
                HeroImageList(
                    title: Text(event.name),
                    showsNavigationTitleBeforeScroll: heroImageTitleSources.containsLogo
                ) {
                    HeroImage(
                        title: Text(event.name),
                        sources: heroImageSources,
                        titleSources: heroImageTitleSources
                    ) {
                        MappedSystemImage(systemName: "music.note")
                            .frame(width: 82, height: 82)
                    }
                } content: {
                    if let description = event.eventInfoDescription {
                        Section("About") {
                            Text(description)
                        }
                    }

                    if event.hasEventInfoDates {
                        Section("Dates") {
                            if let dateInterval = event.dateIntervalText {
                                EventInfoRow(title: "Dates", value: dateInterval)
                            } else {
                                if let startDate = event.startDateText {
                                    EventInfoRow(title: "Starts", value: startDate)
                                }
                                
                                if let endDate = event.endDateText {
                                    EventInfoRow(title: "Ends", value: endDate)
                                }

                                if let timeZone = event.eventInfoTimeZone {
                                    EventInfoRow(title: "Time Zone", value: timeZone)
                                }
                            }
                        }
                    }

                    if event.hasEventInfoDetails {
                        Section("Details") {
                            if let status = event.status?.eventInfoText {
                                EventInfoRow(title: "Status", value: status)
                            }

                            if let mode = event.mode?.eventInfoText {
                                EventInfoRow(title: "Mode", value: mode)
                            }

                            if let rsvpExpected = event.rsvpExpected {
                                EventInfoRow(
                                    title: "RSVPs",
                                    value: rsvpExpected ? "Expected" : "Not expected"
                                )
                            }
                        }
                    }

                    Section {
                        Button("About OpenMusicEvent") {
                            store.send(.aboutOpenMusicEventButtonTapped)
                        }
                        .navigationLinkListRowStyle()
                    }
                }
                .navigationDestination(
                    item: $store.scope(\.destination).aboutOpenMusicEvent
                ) { aboutStore in
                    AboutOpenMusicEventView(store: aboutStore)
                }
            } else {
                ViewerPlaceholderView(
                    title: "About",
                    systemImage: "info.circle",
                    description: "This event could not be loaded."
                )
            }
        }
        .toolbar {
            if showsAuthoringControls {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit Event Info", action: onEdit)
                        .accessibilityIdentifier("button.event-info.edit")
                }
            }
        }
    }
}

struct EventInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

private extension Event {
    var eventInfoDescription: String? {
        let description = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        return description?.isEmpty == false ? description : nil
    }

    var eventInfoTimeZone: String? {
        timeZone.identifier
    }

    var hasEventInfoDates: Bool {
        start?.date(in: timeZone) != nil || end?.date(in: timeZone) != nil
    }

    var hasEventInfoDetails: Bool {
        status != nil || mode != nil || rsvpExpected != nil
    }

    var dateIntervalText: String? {
        guard let start, let end,
              case let .known(.day(startDay)) = start,
              case let .known(.day(endDay)) = end
        else { return nil }

        let formatter = DateIntervalFormatter()
        formatter.timeZone = timeZone
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(
            from: startDay.value.atStartOfDay(in: timeZone),
            to: endDay.value.atStartOfDay(in: timeZone)
        )
    }

    var startDateText: String? {
        boundaryText(start)
    }

    var endDateText: String? {
        boundaryText(end)
    }

    func boundaryText(_ boundary: Open<Time>?) -> String? {
        guard let boundary, let date = boundary.date(in: timeZone) else { return nil }
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        if case .known(.time) = boundary {
            formatter.timeStyle = .short
        } else {
            formatter.timeStyle = .none
        }
        return formatter.string(from: date)
    }
}

private extension Event.Status {
    var eventInfoText: String {
        switch self {
        case .planned:
            "Planned"
        case .scheduled:
            "Scheduled"
        case .rescheduled:
            "Rescheduled"
        case .cancelled:
            "Cancelled"
        case .postponed:
            "Postponed"
        }
    }
}

private extension Event.Mode {
    var eventInfoText: String {
        switch self {
        case .inPerson:
            "In Person"
        case .virtual:
            "Virtual"
        case .hybrid:
            "Hybrid"
        }
    }
}

private extension Open where Known == Event.Status {
    var eventInfoText: String {
        switch self {
        case .known(let status):
            return status.eventInfoText
        case .unknown(let value):
            if let stringValue = value.string?.trimmingCharacters(in: .whitespacesAndNewlines),
               !stringValue.isEmpty {
                return stringValue
            } else {
                return "Unknown"
            }
        }
    }
}

private extension Open where Known == Event.Mode {
    var eventInfoText: String {
        switch self {
        case .known(let mode):
            return mode.eventInfoText
        case .unknown(let value):
            if let stringValue = value.string?.trimmingCharacters(in: .whitespacesAndNewlines),
               !stringValue.isEmpty {
                return stringValue
            } else {
                return "Unknown"
            }
        }
    }
}
