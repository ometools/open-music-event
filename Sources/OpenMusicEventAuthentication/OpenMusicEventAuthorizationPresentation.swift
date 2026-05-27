import ATProtoOAuth
import ComposableArchitecture2
import Dependencies
import Foundation
import Sharing
import SwiftUI
import TCATProtoAuthentication

public struct OpenMusicEventAuthorizationPresentationRequested: FeatureEventKey {
    public init() {}
    public typealias Value = AuthorizationPresentationRequest
}

@Feature
public struct OpenMusicEventAuthorizationPresentation {
    public init() {}

    public struct State {
        public init() {
            self._session = OpenMusicEventOAuth.session
            self._sessionStore = OpenMusicEventOAuth.sessionStore
        }

        public var flow: AuthorizationFlow.State?

        @DebugSnapshotIgnored
        @Shared public var session: OAuth.Session?
        @DebugSnapshotIgnored
        @Shared public var sessionStore: OAuth.SessionStore
        @DebugSnapshotIgnored
        public var request: AuthorizationPresentationRequest?

        public mutating func present(_ request: AuthorizationPresentationRequest) {
            self.request = request
            self.flow = OpenMusicEventOAuth.authorizationFlowState(
                for: request,
                session: session,
                sessionStore: sessionStore
            )
        }
    }

    @CasePathable
    public enum Action {
        case delegate(AuthorizationFlow.Action.Delegate)
        case flow(AuthorizationFlow.Action)
        case present(AuthorizationPresentationRequest)
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .delegate(.succeeded), .flow(.delegate(.succeeded)):
                state.$session.withLock {
                    $0 = state.sessionStore.selectedSession
                }
                let request = state.request
                state.request = nil
                state.flow = nil
                store.addTask {
                    await request?.responder.succeed()
                }

            case .delegate(.cancelled), .flow(.delegate(.cancelled)):
                let request = state.request
                state.request = nil
                state.flow = nil
                store.addTask {
                    await request?.responder.cancel()
                }

            case let .delegate(.failed(error)), let .flow(.delegate(.failed(error))):
                let request = state.request
                state.request = nil
                state.flow = nil
                store.addTask {
                    await request?.responder.fail(error)
                }

            case .flow:
                break

            case .present(let request):
                state.present(request)
            }
        }
        .onMount { state in
            if let session = state.session, state.sessionStore.selectedSession == nil {
                state.$sessionStore.withLock {
                    $0.upsert(session)
                }
            }
            state.$session.withLock {
                $0 = state.sessionStore.selectedSession
            }
        }
        .onDismount { state in
            await state.request?.responder.cancel()
        }
        .ifLet(\.flow, action: \.flow) {
            AuthorizationFlow(sessionStore: store.$sessionStore)
        }
    }
}

public struct OpenMusicEventAuthorizationPresenter: @unchecked Sendable {
    private let present: (AuthorizationPresentationRequest) async throws -> Void

    public init(
        present: @escaping (AuthorizationPresentationRequest) async throws -> Void
    ) {
        self.present = present
    }

    public func authorize(_ requirement: OAuth.AuthRequirement) async throws {
        let request = AuthorizationPresentationRequest(requirement: requirement)
        try await present(request)
        try await request.responder.wait()
    }
}

public nonisolated(nonsending) func withOpenMusicEventAuthorization<Result>(
    presenter: OpenMusicEventAuthorizationPresenter,
    session: Shared<OAuth.Session?> = OpenMusicEventOAuth.session,
    authFailureMessage: Shared<ErrorMessage?> = OpenMusicEventOAuth.authFailureMessage,
    operation: nonisolated(nonsending) () async throws -> Result
) async throws -> Result {
    try await withDependencies {
        $0.oauthAuthorizationBroker = OAuth.AuthorizationBroker { requirement in
            try await presenter.authorize(requirement)
        }
        $0.getDefaultSession = {
            session.wrappedValue ?? .placeholder
        }
        $0.getOptionalDefaultSession = {
            session.wrappedValue
        }
        $0.errorInterceptors.append(
            .tokenRefresh(
                session: session,
                authFailureMessage: authFailureMessage
            )
        )
    } operation: {
        try await operation()
    }
}

public struct OpenMusicEventAuthorizationNavigationDestinationModifier: ViewModifier {
    @Bindable var store: StoreOf<OpenMusicEventAuthorizationPresentation>

    public init(store: StoreOf<OpenMusicEventAuthorizationPresentation>) {
        self.store = store
    }

    public func body(content: Content) -> some View {
        content
            .navigationDestination(item: $store.scope(\.flow, action: \.flow)) { flowStore in
                OpenMusicEventAuthorizationFormView(store: flowStore)
            }
    }
}

public extension View {
    func openMusicEventAuthorizationDestination(
        store: StoreOf<OpenMusicEventAuthorizationPresentation>
    ) -> some View {
        modifier(OpenMusicEventAuthorizationNavigationDestinationModifier(store: store))
    }
}

public extension OpenMusicEventOAuth {
    static func authorizationFlowState(
        for request: AuthorizationPresentationRequest,
        session: OAuth.Session?,
        sessionStore: OAuth.SessionStore
    ) -> AuthorizationFlow.State {
        AuthorizationFlow.State(
            requirement: request.requirement,
            loginHint: loginHint(
                for: request.requirement,
                session: session,
                sessionStore: sessionStore
            )
        )
    }

    static func authorizationFlowState(
        for request: AuthorizationPresentationRequest
    ) -> AuthorizationFlow.State {
        authorizationFlowState(
            for: request,
            session: session.wrappedValue,
            sessionStore: sessionStore.wrappedValue
        )
    }

    static func loginHint(
        for requirement: OAuth.AuthRequirement,
        session: OAuth.Session?,
        sessionStore: OAuth.SessionStore
    ) -> String {
        switch requirement.account {
        case .anySignedInAccount:
            sessionStore.selectedSession?.accountID.rawValue.description
                ?? session?.accountID.rawValue.description
                ?? ""

        case .did(let did):
            did.description
        }
    }
}
