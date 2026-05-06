//
//  MyEvents.swift
//  open-music-event
//
//  Created by Woodrow Melling on 5/2/26.
//

import ComposableArchitecture2
import OpenMusicEventAppEventViewer
import OpenMusicEventLexicon
import SQLiteData
import SwiftUI

@Feature
public struct MyEvents {
    public struct State {
        var destination: Destination.State?

        @DebugSnapshotIgnored
        @FetchAll(MyEvents.query)
        var events
    }

    public enum Action {
        case didTapCreateEvent
        case didTapEvent(OMERecord.Event)
        case destination(Destination.Action)
    }

    static let query = OMERecord.Event.where { event in
        OMERecord.EventOrganizer.where {
            $0.id.eventID.eq(event.id)
        }.exists().not()

    }

    @Feature
    public enum Destination {
        case createEvent(Spawn<CreateEvent>)
    }

    public var body: some Feature {
        let _ = Self._logChanges()
        Update { state, action in
            switch action {
            case .didTapCreateEvent:
                state.destination = .createEvent(Spawn(CreateEvent.State()))
            case .didTapEvent(let event):
                store.addTask {
                    try store.post(
                        key: NavigationRequested.self,
                        value: .event(event.id, nil)
                    )
                }

            case .destination:
                return
            }
        }
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
    }
}

struct MyEventsView: View {
    @Bindable var store: StoreOf<MyEvents>

    var body: some View {
        List {
            ForEach(store.events) { event in
                Button {
                    store.send(.didTapEvent(event))
                } label: {
                    EventRowView(event: event)
                }
            }
        }
        .listStyle(.plain)
        .toolbar {
                Button("Create Event", systemImage: "plus") {
                    store.send(.didTapCreateEvent)
                }
            }
        .sheet(item: $store.scope(state: \.destination, action: \.destination).createEvent) { createEventStore in
            NavigationStack {
                CreateEventView(store: createEventStore)
            }
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

struct EventRowView: View {
    var event: OMERecord.Event

    static let intervalFormatter = {
        let f = DateIntervalFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        return f
    }()

    var eventDateString: String? {
        if let startTime = event.startsAt, let endTime = event.endsAt {
            guard startTime <= endTime
            else {
                reportIssue("Start time (\(String(describing: startTime))) is after end time (\(String(describing: endTime)))")
                return nil
            }

            return Self.intervalFormatter.string(from: startTime, to: endTime)
        } else if let startTime = event.startsAt {
            return startTime.formatted()
        } else {
            return nil
        }
    }

//    @Environment(\.date) var date

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
