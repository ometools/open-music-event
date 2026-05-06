import ComposableArchitecture2
import Dependencies
import SwiftUI

@Feature
public struct Edit {
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

public struct EditView: View {
    let store: StoreOf<Edit>

    public init(store: StoreOf<Edit>) {
        self.store = store
    }

    public var body: some View {
        ViewerPlaceholderView(
            title: "Edit",
            systemImage: "pencil",
            description: "This event does not have any editable sections yet."
        )
    }
}
