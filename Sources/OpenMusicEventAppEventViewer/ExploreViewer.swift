import ComposableArchitecture2
import Dependencies
import SwiftUI

@Feature
public struct EventSearch {
    public init() {}

    public struct State {
        public init(destination: Destination.State? = nil) {
            self.destination = destination
        }


        public var query = ""

        public var destination: Destination.State?

        public static func route(target: EventTarget?) -> Self {
            switch target {
            case let .participant(participantID):
                return .init(
                    destination: .participantDetail(
                        Spawn(.init(participantID: participantID))
                    )
                )
            case let .stage(stageID):
                return .init(
                    destination: .stageDetail(
                        Spawn(.init(stageID: stageID))
                    )
                )
            default:
                return .init()
            }
        }
    }

    public enum Action {
        case destination(Destination.Action)
        case openParticipant(OMERecord.ID<OMERecord.Participant>)
        case openStage(OMERecord.ID<OMERecord.Stage>)
    }

    @Feature
    public enum Destination {
        case participantDetail(Spawn<ParticipantDetail>)
        case stageDetail(Spawn<StageDetail>)
    }

    @Dependency(\.defaultEventID) var defaultEventID

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .destination:
                break

            case .openParticipant(let participantID):
                store.addTask {
                    try store.post(
                        key: NavigationRequested.self,
                        value: .event(defaultEventID, .participant(participantID))
                    )
                }

            case .openStage(let stageID):
                store.addTask {
                    try store.post(
                        key: NavigationRequested.self,
                        value: .event(defaultEventID, .stage(stageID))
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
                description: "Search within this event to find participants and stages."
            )
            .navigationDestination(item: $store.scope(state: \.destination, action: \.destination).participantDetail) { detailStore in
                ParticipantDetailView(store: detailStore)
            }
            .navigationDestination(item: $store.scope(state: \.destination, action: \.destination).stageDetail) { detailStore in
                StageDetailView(store: detailStore)
            }
        }
        .searchable(text: $store.query, prompt: "Search Wicked Woods")
    }
}
