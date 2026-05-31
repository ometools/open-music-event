import ComposableArchitecture2
import Dependencies
import SwiftUI

@Feature
public struct EventSearch {
    public init() {}

    public struct State {
        public init(
            eventID: OMERecord.Event.ID,
            destination: Destination.State? = nil
        ) {
            self.eventID = eventID
            self.destination = destination
        }

        public let eventID: OMERecord.Event.ID

        public var query = ""

        public var destination: Destination.State?

        public static func route(
            eventID: OMERecord.Event.ID,
            target: EventTarget?
        ) -> Self {
            switch target {
            case let .contributor(contributorID):
                return .init(
                    eventID: eventID,
                    destination: .contributorDetail(
                        Spawn(.init(contributorID: contributorID, eventID: eventID))
                    )
                )
            case let .stage(stageID):
                return .init(
                    eventID: eventID,
                    destination: .stageDetail(
                        Spawn(.init(stageID: stageID, eventID: eventID))
                    )
                )
            default:
                return .init(eventID: eventID)
            }
        }
    }

    public enum Action {
        case destination(Destination.Action)
        case openContributor(OMERecord.ID<OMERecord.Contributor>)
        case openStage(OMERecord.ID<OMERecord.Stage>)
    }

    @Feature
    public enum Destination {
        case contributorDetail(Spawn<ContributorDetail>)
        case stageDetail(Spawn<StageDetail>)
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .destination:
                break

            case .openContributor(let contributorID):
                let eventID = state.eventID
                store.addTask {
                    try store.post(
                        key: NavigationRequested.self,
                        value: .event(eventID, .contributor(contributorID))
                    )
                }

            case .openStage(let stageID):
                let eventID = state.eventID
                store.addTask {
                    try store.post(
                        key: NavigationRequested.self,
                        value: .event(eventID, .stage(stageID))
                    )
                }
            }
        }
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
    }
}

public struct EventSearchView: View {
    @Bindable var store: StoreOf<EventSearch>

    public init(store: StoreOf<EventSearch>) {
        self.store = store
    }

    @FocusState var searchFocus

    public var body: some View {
        NavigationStack {
            ViewerPlaceholderView(
                title: "Search",
                systemImage: "magnifyingglass",
                description: "Search within this event to find contributors and stages."
            )
            .navigationDestination(item: $store.scope(\.destination, action: \.destination).contributorDetail) { detailStore in
                ContributorDetailView(store: detailStore)
            }
            .navigationDestination(item: $store.scope(\.destination, action: \.destination).stageDetail) { detailStore in
                StageDetailView(store: detailStore)
            }
        }
        .searchable(text: $store.query, prompt: "Search Wicked Woods")
    }
}
