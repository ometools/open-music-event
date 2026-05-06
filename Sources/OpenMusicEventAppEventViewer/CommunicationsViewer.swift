import ComposableArchitecture2
import Dependencies
import SwiftUI

@Feature
public struct CommunicationsViewer {
    public init() {}

    public struct State {
        public init() {}
    }

    public enum Action {}

    @Dependency(\.defaultEventID) var defaultEventID

    public var body: some Feature {
        let _ = defaultEventID
        return Update { _, _ in }
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
