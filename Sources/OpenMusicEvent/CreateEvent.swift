//
//  CreateEvent.swift
//  open-music-event
//
//  Created by Woodrow Melling on 5/2/26.
//

import ComposableArchitecture2
import SwiftUI

@Feature
public struct CreateEvent {
    public struct State {
        var eventName = ""

    }

}

struct CreateEventView: View {
    @Bindable var store: StoreOf<CreateEvent>

    var body: some View {
        Form {
            TextField("Event Name", text: $store.eventName, prompt: Text("Testival 2026"))
        }
        .navigationTitle("New Event")
    }
}
