import ComposableArchitecture2
import OpenMusicEventAppEventViewer
import SwiftUI

@Feature
public struct OrganizationRoot {
    public init() {}

    public struct State {
        public init(organizerID: OMERecord.Organizer.ID) {
            self.organizerDetail = Spawn(OrganizerDetail.State(organizerID: organizerID))
        }

        public var eventViewer: Spawn<EventViewer>?
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
        Update { state, action in
            switch action {
            case .eventViewerDismissed:
                state.eventViewer = nil

            case let .handleNavigationRequest(request):
                switch request {
                case let .event(eventID, target):
                    store.withDependencies {
                        state.eventViewer = Spawn(.route(eventID: eventID, target: target))
                    }

                case .externalURL:
                    break
                }
            }
        }
        .onEvent(NavigationRequested.self) { request, _ in
            store.addTask {
                try store.send(.handleNavigationRequest(request))
            }
        }
        .spawn(\.organizerDetail) {
            OrganizerDetail()
        }
        .ifLet(\.eventViewer) {
            EventViewer()
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
                .openMusicEventFullScreenCover(
                    isPresented: eventViewerIsPresented,
                    onDismiss: {
                        store.send(.eventViewerDismissed)
                    }
                ) {
                    if let eventViewerStore = store.spawn(\.eventViewer) {
                        EventViewerView(store: eventViewerStore)
                    }
                }
        }
    }

    private var eventViewerIsPresented: Binding<Bool> {
        Binding(
            get: { store.eventViewer != nil },
            set: { isPresented in
                if !isPresented {
                    store.send(.eventViewerDismissed)
                }
            }
        )
    }
}
