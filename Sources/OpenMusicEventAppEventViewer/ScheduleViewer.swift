import ComposableArchitecture2
import Dependencies
import SwiftUI

@Feature
public struct ScheduleViewer {
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

public struct ScheduleViewerView: View {
    let store: StoreOf<ScheduleViewer>

    public init(store: StoreOf<ScheduleViewer>) {
        self.store = store
    }

    public var body: some View {
        ViewerPlaceholderView(
            title: "Schedule",
            systemImage: "calendar",
            description: "No schedule has been added to this event yet."
        )
    }
}
