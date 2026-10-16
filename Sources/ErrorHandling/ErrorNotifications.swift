import ComposableArchitecture2
import Dependencies
import Foundation

@Feature
public struct ErrorNotifications {
    public static let automaticDismissDelay: Duration = .seconds(5)

    public init() {}

    @Dependency(\.continuousClock) var clock

    public struct State {
        public init(latestError: HandledError? = nil) {
            self.latestError = latestError
        }

        public var latestError: HandledError?
    }

    public enum Action {
        case errorReported(HandledError)
        case latestErrorAutomaticallyDismissed(UUID)
        case latestErrorNotificationDismissed
        case latestErrorNotificationTapped
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .errorReported(let error):
                state.report(error)

            case .latestErrorAutomaticallyDismissed(let id):
                state.dismiss(id: id)

            case .latestErrorNotificationDismissed:
                state.dismiss()

            case .latestErrorNotificationTapped:
                guard let error = state.latestError else { return }
                store.addTask {
                    try store.post(key: ErrorNotificationSelected.self, value: error)
                }
            }
        }
        .onChange(of: store.latestError?.id) { _, newID, _ in
            guard let newID else { return }
            store.addTask {
                try await clock.sleep(for: Self.automaticDismissDelay)
                try store.send(.latestErrorAutomaticallyDismissed(newID))
            }
        }
        .onEvent(ErrorReported.self) { error, state in
            state.report(error)
        }
    }
}

public extension ErrorNotifications.State {
    mutating func report(_ error: HandledError) {
        latestError = error
    }

    mutating func dismiss(id: UUID? = nil) {
        guard id == nil || latestError?.id == id else { return }
        latestError = nil
    }
}

public struct ErrorNotificationSelected: FeatureEventKey {
    public init() {}
    public typealias Value = HandledError
}
