import ComposableArchitecture2
import Dependencies
import SwiftUI

@Feature
public struct NotificationsViewer {
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

public struct NotificationsViewerView: View {
    let store: StoreOf<NotificationsViewer>

    public init(store: StoreOf<NotificationsViewer>) {
        self.store = store
    }

    public var body: some View {
        ViewerPlaceholderView(
            title: "Notifications",
            systemImage: "bell",
            description: "No notification settings are available for this event yet."
        )
    }
}
