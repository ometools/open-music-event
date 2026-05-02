//
//  MyEvents.swift
//  open-music-event
//
//  Created by Woodrow Melling on 5/2/26.
//

import ComposableArchitecture2
import SwiftUI


@Feature
public struct MyEvents {
    public struct State {
        var destination: Destination.State?
    }

    public enum Action {
        case didTapCreateEvent
        case destination(Destination.Action)
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
        Text("Hello World")
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
