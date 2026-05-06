import ComposableArchitecture2
import Dependencies
import SwiftUI

@Feature
public struct AboutViewer {
    public init() {}

    public struct State {
        public init() {}
    }

    public enum Action {}

    @Dependency(\.viewerEventID) var viewerEventID

    public var body: some Feature {
        let _ = viewerEventID
        return Update { _, _ in }
    }
}

public struct EventInfoViewerView: View {
    let store: StoreOf<AboutViewer>

    public init(store: StoreOf<AboutViewer>) {
        self.store = store
    }

    public var body: some View {
        ViewerPlaceholderView(
            title: "About",
            systemImage: "info.circle",
            description: "No about information has been added to this event yet."
        )
    }
}
