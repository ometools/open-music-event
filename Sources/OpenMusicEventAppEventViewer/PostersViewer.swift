import ComposableArchitecture2
import Dependencies
import SwiftUI

@Feature
public struct PostersViewer {
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

public struct PostersViewerView: View {
    let store: StoreOf<PostersViewer>

    public init(store: StoreOf<PostersViewer>) {
        self.store = store
    }

    public var body: some View {
        ViewerPlaceholderView(
            title: "Posters",
            systemImage: "photo.on.rectangle",
            description: "No posters have been added to this event yet."
        )
    }
}
