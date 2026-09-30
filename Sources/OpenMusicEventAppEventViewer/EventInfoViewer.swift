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
        public let eventID: OMERecord.Event.ID
        @FetchOne public var event: OMERecord.Event?
        @FetchOne public var sourceProvenance: EventSourceProvenanceRecord?
        @FetchAll public var posters: [OMERecord.Poster]
        public var destination: Destination.State?

        public init(eventID: OMERecord.Event.ID) {
            self.eventID = eventID
            _event = FetchOne(
                OMERecord.Event.where { $0.id.eq(eventID) }
            )
            _sourceProvenance = FetchOne(
                EventSourceProvenanceRecord.where { $0.id.eq(eventID) }
            )
            _posters = FetchAll(
                PostersViewer.postersQuery(eventID: eventID)
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
                    AboutOpenMusicEvent.State(
                        eventID: state.eventID,
                        sourceProvenance: state.sourceProvenance
                    )
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

    public init(store: StoreOf<EventInfoViewer>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if let event = store.event {
                let heroImageSources = event.heroImageSources(posters: store.posters)
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
            if let stringValue = value.string?.trimmingCharacters(in: .whitespacesAndNewlines),
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
            if let stringValue = value.string?.trimmingCharacters(in: .whitespacesAndNewlines),
               !stringValue.isEmpty {
                return stringValue
            } else {
                return "Unknown"
            }
        }
    }
}
