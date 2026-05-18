import ComposableArchitecture2
import SwiftUI

@Feature
public struct CommunicationsViewer {
    public init() {}

    public struct State {
        public init(eventID: OMERecord.Event.ID) {
            self.eventID = eventID
        }

        let eventID: OMERecord.Event.ID
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
        ViewerPlaceholderView(
            title: "Communications",
            systemImage: "megaphone",
            description: "No communication channels have been added to this event yet."
        )
    }
}
