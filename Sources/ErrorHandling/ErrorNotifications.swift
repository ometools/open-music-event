import ComposableArchitecture2

@Feature
public struct ErrorNotifications {
    public init() {}

    public struct State {
        public init(latestError: HandledError? = nil) {
            self.latestError = latestError
        }

        public var latestError: HandledError?
    }

    public enum Action {
        case errorReported(HandledError)
        case latestErrorNotificationTapped
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .errorReported(let error):
                state.report(error)

            case .latestErrorNotificationTapped:
                break
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
}
