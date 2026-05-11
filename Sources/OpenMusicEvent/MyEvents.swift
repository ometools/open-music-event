//
//  MyEvents.swift
//  open-music-event
//
//  Created by Woodrow Melling on 5/2/26.
//

import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventAppEventViewer
import OpenMusicEventLexicon
import SQLiteData
import SwiftUI

@Feature
public struct MyEvents {
    public struct State {
        var destination: Destination.State?
        var organizerDetail: OrganizerDetail.State?

        @DebugSnapshotIgnored
        @FetchAll(MyEvents.query)
        var events

        @DebugSnapshotIgnored
        @FetchAll(MyEvents.organizersQuery)
        var organizers
    }

    public enum Action {
        case didTapCreateEvent
        case didTapEvent(OMERecord.Event)
        case didTapImportSource
        case didTapOrganizer(OMERecord.Organizer.ID)
        case destination(Destination.Action)
        case organizerDetail(OrganizerDetail.Action)
    }

    static let query = OMERecord.Event.where { event in
        OMERecord.EventOrganizer
            .where { $0.id.organizerID.eq(event.id.organizerID) }
            .where { $0.id.eventID.eq(event.id.eventID) }
            .exists()
            .not()

    }

    static let organizersQuery = OMERecord.Organizer.where { organizer in
        OMERecord.EventOrganizer
            .where { $0.id.eventOrganizerID.eq(organizer.id) }
            .exists()
    }

    @Feature
    public enum Destination {
        case createEvent(Spawn<CreateEvent>)
        case sourceImport(Spawn<TangledSourceDownload>)
    }

    public var body: some Feature {
        let _ = Self._logChanges()
        Update { state, action in
            switch action {
            case .didTapCreateEvent:
                state.destination = .createEvent(Spawn(CreateEvent.State()))

            case .didTapImportSource:
                state.destination = .sourceImport(Spawn(TangledSourceDownload.State()))

            case .didTapEvent(let event):
                store.addTask {
                    try store.post(
                        key: NavigationRequested.self,
                        value: .event(event.id, nil)
                    )
                }

            case .didTapOrganizer(let organizerID):
                @Dependency(\.defaultDatabase) var database
                state.organizerDetail = .init(
                    organizerID: organizerID,
                    database: database
                )

            case .destination:
                return

            case .organizerDetail:
                return
            }
        }
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
        .ifLet(\.organizerDetail, action: \.organizerDetail) {
            OrganizerDetail()
        }
    }
}

struct MyEventsView: View {
    @Bindable var store: StoreOf<MyEvents>

    var body: some View {
        List {
            if !store.organizers.isEmpty {
                Section("Organizers") {
                    ForEach(store.organizers) { organizer in
                        Button {
                            store.send(.didTapOrganizer(organizer.id))
                        } label: {
                            OrganizerRowView(organizer: organizer)
                        }
                    }
                }
            }

            if !store.events.isEmpty {
                Section("Events") {
                    ForEach(store.events) { event in
                        Button {
                            store.send(.didTapEvent(event))
                        } label: {
                            EventRowView(event: event)
                        }
                    }
                }
            }
        }
        .navigationTitle("My Events")
        .listStyle(.plain)
        .toolbar {
            Button("Import Source", systemImage: "arrow.down.doc") {
                store.send(.didTapImportSource)
            }

            Button("Create Event", systemImage: "plus") {
                store.send(.didTapCreateEvent)
            }
        }
        .sheet(item: $store.scope(state: \.destination, action: \.destination).createEvent) { createEventStore in
            NavigationStack {
                CreateEventView(store: createEventStore)
            }
        }
        .sheet(item: $store.scope(state: \.destination, action: \.destination).sourceImport) { downloadStore in
            NavigationStack {
                TangledSourceDownloadView(store: downloadStore)
            }
        }
        .navigationDestination(item: $store.scope(state: \.organizerDetail, action: \.organizerDetail)) { detailStore in
            OrganizerDetailView(store: detailStore)
        }
    }
}

#Preview {
    NavigationStack {
        MyEventsView(store: Store(initialState: .init(), feature: {
            MyEvents()
        }))
    }
}

import SwiftUI

struct OrganizerRowView: View {
    var organizer: OMERecord.Organizer

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 60, height: 60)

            Text(organizer.id.description)
                .lineLimit(1)

            Spacer()
        }
        .foregroundStyle(.primary)
    }
}

struct EventRowView: View {
    var event: OMERecord.Event
    
    var eventDateString: String? {
        event.eventDateText(dateStyle: .long)
    }

    var body: some View {
        HStack(spacing: 10) {
            EventIconImageView(event: event)
                .frame(width: 60, height: 60)
            //                    .foregroundColor(.label)
            //                .invertForLightMode()

            HStack {
                VStack(alignment: .leading) {
                    Text(event.name)
                    if let eventDateString {
                        Text(eventDateString)
                            .lineLimit(1)
                            .font(.caption2)
                    }
                }
            }

            Spacer()
        }
        .foregroundStyle(.primary)
    }


    struct EventIconImageView: View {
        let event: OMERecord.Event
        var body: some View {

        }
    }
}

private extension OMERecord.Event {
    func eventDateText(dateStyle: DateFormatter.Style) -> String? {
        switch (startDate, endDate) {
        case let (.some(startDate), .some(endDate)):
            let formatter = DateIntervalFormatter()
            formatter.timeZone = timeZone
            formatter.dateStyle = .long
            formatter.timeStyle = .none
            return formatter.string(
                from: startDate.atStartOfDay(in: timeZone),
                to: endDate.atStartOfDay(in: timeZone)
            )

        case let (.some(startDate), .none):
            return startDate.formatted(dateStyle: dateStyle, in: timeZone)

        case let (.none, .some(endDate)):
            return endDate.formatted(dateStyle: dateStyle, in: timeZone)

        case (.none, .none):
            return nil
        }
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
