import ComposableArchitecture2
import OpenMusicEventAppEventViewer
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

@Feature
public struct OrganizationRoot {
    public init() {}

    public struct State {
        public init(organizerID: OMERecord.Organizer.ID) {
            self.organizerDetail = Spawn(OrganizerDetail.State(organizerID: organizerID))
        }

        public var organizerDetail: Spawn<OrganizerDetail>

        public var organizerID: OMERecord.Organizer.ID {
            organizerDetail.state.organizerID
        }
    }

    public enum Action {
        case eventViewerDismissed
        case handleNavigationRequest(NavigationRequest)
    }

    public var body: some Feature {
        Update { _, action in
            switch action {
            case .eventViewerDismissed, .handleNavigationRequest:
                return
            }
        }
        .spawn(\.organizerDetail) {
            OrganizerDetail()
        }
    }
}

public struct OrganizationRootView: View {
    public init(store: StoreOf<OrganizationRoot>) {
        self.store = store
    }

    @Bindable var store: StoreOf<OrganizationRoot>

    public var body: some View {
        NavigationStack {
            OrganizerDetailView(store: store.spawn(\.organizerDetail))
        }
    }
}
