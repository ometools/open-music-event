import ComposableArchitecture2
import Dependencies
import SwiftUI

@Feature
public struct ContactInfoViewer {
    public init() {}

    public struct State {
        public init() {}
    }

    public enum Action {}

    @Dependency(\.defaultEventID) var defaultEventID

    public var body: some Feature {
        let _ = defaultEventID
        Update { _, _ in }
    }
}

public struct ContactInfoViewerView: View {
    let store: StoreOf<ContactInfoViewer>

    public init(store: StoreOf<ContactInfoViewer>) {
        self.store = store
    }

    public var body: some View {
        ViewerPlaceholderView(
            title: "Contact Info",
            systemImage: "phone",
            description: "No contact information has been added to this event yet."
        )
    }
}
