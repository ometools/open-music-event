import ComposableArchitecture2
import Dependencies
import SwiftUI

@Feature
public struct SiteMapViewer {
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

public struct SiteMapViewerView: View {
    let store: StoreOf<SiteMapViewer>

    public init(store: StoreOf<SiteMapViewer>) {
        self.store = store
    }

    public var body: some View {
        ViewerPlaceholderView(
            title: "Site Map",
            systemImage: "map",
            description: "No site map has been added to this event yet."
        )
    }
}
