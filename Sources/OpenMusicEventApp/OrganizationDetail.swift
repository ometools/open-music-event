import ATProto
import ComposableArchitecture2
import ComposableCalendarEvents
import Dependencies
import Foundation
import OpenMusicEventComponents
import OpenMusicEventImages
import OpenMusicEventLexicon
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

/// The public organizer surface shared by white-label and Browse navigation.
@Feature
public struct OrganizationDetail {
    public init() {}

    public struct State: Identifiable {
        public init(
            organizerID: OME.Organizer.ID,
            collection: ATProto.NSID = OME.Event.nsid,
            organizer: CalendarEvent.Organizer? = nil,
            events: [CalendarEvent] = []
        ) {
            self.organizerID = organizerID
            self.collection = collection
            self.organizer = organizer
            self.events = events
        }

        public let collection: ATProto.NSID
        public var errorMessage: String?
        public var events: [CalendarEvent]
        public var isLoading = false
        public var organizer: CalendarEvent.Organizer?
        public let organizerID: OME.Organizer.ID

        public var id: OME.Organizer.ID { organizerID }
    }

    public enum Action {
        case eventButtonTapped(ATProto.URI)
        case retryButtonTapped
        case task
    }

    @Dependency(\.calendarEvents) var calendarEvents
    public var body: some Feature {
        Update { state, action in
            switch action {
            case let .eventButtonTapped(eventURI):
                guard let event = state.events.first(where: { $0.uri == eventURI }) else {
                    return
                }
                store.addTask {
                    try store.post(key: OrganizationEventSelected.self, value: event)
                }

            case .retryButtonTapped, .task:
                guard !state.isLoading else { return }
                state.isLoading = true
                state.errorMessage = nil
                let collection = state.collection
                let organizerID = state.organizerID
                store.addTask {
                    do {
                        let organizer = try await calendarEvents.organizer(organizerID)
                        let page = try await calendarEvents.browse(
                            CalendarEvent.PageRequest(collection: collection)
                        )
                        try store.modify {
                            $0.events = page.events
                                .filter { $0.organizer.id == organizerID }
                                .sorted(by: Self.eventComesBefore)
                            $0.isLoading = false
                            $0.organizer = organizer
                        }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        try store.modify {
                            $0.errorMessage = "Unable to load this organizer."
                            $0.isLoading = false
                        }
                    }
                }
            }
        }
    }

    static func eventComesBefore(_ lhs: CalendarEvent, _ rhs: CalendarEvent) -> Bool {
        switch (lhs.startsAt, rhs.startsAt) {
        case let (.some(lhsDate), .some(rhsDate)):
            if lhsDate != rhsDate { return lhsDate < rhsDate }
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            break
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}

public struct OrganizationDetailView: View {
    public init(store: StoreOf<OrganizationDetail>) {
        self.store = store
    }

    @Bindable var store: StoreOf<OrganizationDetail>
    @Dependency(\.date.now) var now

    public var body: some View {
        HeroImageList(title: Text(organizerTitle)) {
            HeroImage(
                title: Text(organizerTitle),
                sources: organizerImageSources,
                titleSources: [.title]
            ) {
                MappedSystemImage(systemName: "person.crop.circle")
                    .font(.system(size: 82, weight: .semibold))
            }
        } content: {
            if let organizer = store.organizer {
                if let handle = organizer.handle {
                    Section {
                        Text("@\(handle)")
                            .foregroundStyle(.secondary)
                    }
                }
                if let description = organizer.description, !description.isEmpty {
                    Section("About") {
                        Text(description)
                    }
                }
            }

            if !currentEvents.isEmpty {
                Section("Now") { eventRows(currentEvents) }
            }
            if !upcomingEvents.isEmpty {
                Section("Upcoming") { eventRows(upcomingEvents) }
            }
            if !previousEvents.isEmpty {
                Section("Previous") { eventRows(previousEvents) }
            }
            if !unavailableEvents.isEmpty {
                Section("Unavailable Events") { eventRows(unavailableEvents) }
            }

            if store.isLoading && store.events.isEmpty {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            } else if store.events.isEmpty && store.errorMessage == nil {
                EmptyBrowserState(
                    title: "No Events",
                    systemImage: "calendar.badge.exclamationmark",
                    message: "This organizer has no events."
                )
            }

            if let errorMessage = store.errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                    Button("Try Again") { store.send(.retryButtonTapped) }
                }
            }
        }
        .task {
            await store.send(.task)?.value
        }
    }

    @ViewBuilder
    func eventRows(_ events: [CalendarEvent]) -> some View {
        ForEach(events) { event in
            Button {
                store.send(.eventButtonTapped(event.uri))
            } label: {
                BrowseCalendarEventRow(event: event)
            }
            .buttonStyle(.plain)
        }
    }

    var organizerTitle: String {
        store.organizer?.name ?? store.organizerID.description
    }

    var organizerImageSources: [HeroImageSource] {
        guard let avatarURL = store.organizer?.avatarURL else { return [] }
        return [
            .logo(
                DisplayImageAsset(
                    asset: OME.ImageAsset(
                        source: .url(avatarURL),
                        role: .logo,
                        renderKind: .transparent,
                        materializationPolicy: .lazy
                    )
                )
            )
        ]
    }

    var currentEvents: [CalendarEvent] {
        store.events.filter { event in
            guard let startsAt = event.startsAt else { return false }
            return startsAt <= now && (event.endsAt ?? startsAt) >= now
        }
    }

    var upcomingEvents: [CalendarEvent] {
        store.events.filter { ($0.startsAt ?? .distantPast) > now }
    }

    var previousEvents: [CalendarEvent] {
        Array(
            store.events.filter { event in
                guard let startsAt = event.startsAt else { return false }
                return (event.endsAt ?? startsAt) < now
            }.reversed()
        )
    }

    var unavailableEvents: [CalendarEvent] {
        store.events.filter { $0.startsAt == nil }
    }
}

struct OrganizationEventSelected: FeatureEventKey {
    typealias Value = CalendarEvent
}
