import ComposableArchitecture2
import Dependencies
import Foundation
import Lexicon
import OpenMusicEventImages
import SQLiteData
import SwiftUI

@Feature
public struct EventInfoViewer {
    public init() {}

    public struct State {
        public let eventID: OMERecord.Event.ID
        @FetchOne public var event: OMERecord.Event?
        public var destination: Destination.State?

        public init(
            eventID: OMERecord.Event.ID,
            destination: Destination.State? = nil
        ) {
            self.eventID = eventID
            self.destination = destination
            _event = FetchOne(
                OMERecord.Event.where { $0.id.eq(eventID) }
            )
        }
    }

    public enum Action {
        case destination(Destination.Action)
        case editButtonTapped
    }

    @Feature
    public enum Destination {
        case editEventInfo(Spawn<EditEventInfo>)
    }


    public var body: some Feature {
        Update { state, action in
            switch action {
            case .destination:
                break

            case .editButtonTapped:
                store.withDependencies {
                    state.destination = .editEventInfo(
                        Spawn(EditEventInfo.State(eventID: state.eventID))
                    )
                }
            }
        }
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
    }
}

public struct EventInfoViewerView: View {
    @Bindable var store: StoreOf<EventInfoViewer>

    public init(store: StoreOf<EventInfoViewer>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if let event = store.event {
                let logoAsset = event.images?.imageAsset(role: .icon)
                HeroImageList(
                    title: Text(event.name),
                    showsNavigationTitleBeforeScroll: logoAsset != nil
                ) {
                    HeroImage(
                        title: Text(event.name),
                        asset: event.images?.imageAsset(role: .hero),
                        cacheContext: .init(eventID: event.id),
                        logoAsset: logoAsset
                    ) {
                        Image(systemName: "music.note")
                            .font(.system(size: 82, weight: .semibold))
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
                        }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Edit") {
                            store.send(.editButtonTapped)
                        }
                    }
                }
            } else {
                ViewerPlaceholderView(
                    title: "About",
                    systemImage: "info.circle",
                    description: "This event could not be loaded."
                )
            }
        }
        .sheet(item: $store.scope(state: \.destination, action: \.destination).editEventInfo) { editStore in
            NavigationStack {
                EditEventInfoView(store: editStore)
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

private extension OMERecord.Event {
    var eventInfoDescription: String? {
        let description = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        return description?.isEmpty == false ? description : nil
    }

    var eventInfoTimeZone: String? {
        timeZone.identifier
    }

    var hasEventInfoDates: Bool {
        startDate != nil || endDate != nil
    }

    var hasEventInfoDetails: Bool {
        status != nil || mode != nil
    }

    var dateIntervalText: String? {
        guard let startDate, let endDate else { return nil }

        let formatter = DateIntervalFormatter()
        formatter.timeZone = timeZone
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(
            from: startDate.atStartOfDay(in: timeZone),
            to: endDate.atStartOfDay(in: timeZone)
        )
    }

    var startDateText: String? {
        startDate?.formatted(dateStyle: .medium, in: timeZone)
    }

    var endDateText: String? {
        endDate?.formatted(dateStyle: .medium, in: timeZone)
    }
}

private extension LocalDate {
    func formatted(dateStyle: DateFormatter.Style, in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateStyle = dateStyle
        formatter.timeStyle = .none
        return formatter.string(from: atStartOfDay(in: timeZone))
    }
}

private extension OMERecord.Event.Status {
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

private extension OMERecord.Event.Mode {
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

private extension Open where Known == OMERecord.Event.Status {
    var eventInfoText: String {
        switch self {
        case .known(let status):
            return status.eventInfoText
        case .unknown(let value):
            if let stringValue = value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !stringValue.isEmpty {
                return stringValue
            } else {
                return "Unknown"
            }
        }
    }
}

private extension Open where Known == OMERecord.Event.Mode {
    var eventInfoText: String {
        switch self {
        case .known(let mode):
            return mode.eventInfoText
        case .unknown(let value):
            if let stringValue = value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !stringValue.isEmpty {
                return stringValue
            } else {
                return "Unknown"
            }
        }
    }
}
