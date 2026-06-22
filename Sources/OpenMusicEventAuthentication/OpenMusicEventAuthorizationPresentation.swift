import ATProtoOAuth
import ComposableArchitecture2
import Dependencies
import Sharing
import SwiftUI
import TCATProtoAuthentication

public struct OpenMusicEventAuthorizationPresentationRequested: FeatureEventKey {
    public init() {}
    public typealias Value = AuthorizationPresentationRequest
}

public typealias OpenMusicEventAuthorizationPresentation = OAuthAuthorizationPresentation

public struct OpenMusicEventAuthorizationPresenter: @unchecked Sendable {
    private let present: (AuthorizationPresentationRequest) async throws -> Void

    public init(
        present: @escaping (AuthorizationPresentationRequest) async throws -> Void
    ) {
        self.present = present
    }

    public func authorize(_ requirement: OAuth.AuthRequirement) async throws {
        @Dependency(\.openMusicEventSignUpServerConfiguration)
        var signUpServerConfiguration
        let request = AuthorizationPresentationRequest(
            signUpServerConfiguration: signUpServerConfiguration,
            requirement: requirement
        )
        try await present(request)
        try await request.responder.wait()
    }
}

public extension OAuthAuthorizationPresentation.State {
    init() {
        self.init(storage: OpenMusicEventOAuth.storage)
    }
}

public nonisolated(nonsending) func withOpenMusicEventAuthorization<Result>(
    presenter: OpenMusicEventAuthorizationPresenter,
    session: Shared<OAuth.Session?> = OpenMusicEventOAuth.session,
    sessionStore: Shared<OAuth.SessionStore> = OpenMusicEventOAuth.sessionStore,
    authFailureMessage: Shared<ErrorMessage?> = OpenMusicEventOAuth.authFailureMessage,
    operation: nonisolated(nonsending) () async throws -> Result
) async throws -> Result {
    try await withDependencies {
        $0.oauthAuthorizationBroker = OAuth.AuthorizationBroker { requirement in
            try await presenter.authorize(requirement)
        }
        $0.getDefaultSession = {
            session.wrappedValue
                ?? sessionStore.wrappedValue.selectedSession
                ?? .placeholder
        }
        $0.getOptionalDefaultSession = {
            session.wrappedValue
                ?? sessionStore.wrappedValue.selectedSession
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

public extension View {
    func openMusicEventAuthorizationDestination(
        store: StoreOf<OpenMusicEventAuthorizationPresentation>
    ) -> some View {
        modifier(OpenMusicEventAuthorizationNavigationDestinationModifier(store: store))
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
