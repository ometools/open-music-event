import ComposableArchitecture2
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

@Feature
public struct NotificationsViewer {
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
