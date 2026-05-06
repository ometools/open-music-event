import ComposableArchitecture2
import Dependencies
import SwiftUI

@Feature
public struct LocationViewer {
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

public struct LocationViewerView: View {
    let store: StoreOf<LocationViewer>

    public init(store: StoreOf<LocationViewer>) {
        self.store = store
    }

    public var body: some View {
        ViewerPlaceholderView(
            title: "Location",
            systemImage: "mappin.and.ellipse",
            description: "No locations have been added to this event yet."
        )
    }
}
