import ATProtoOAuth
import ComposableArchitecture2
import Sharing
import SwiftUI
import TCATProtoAuthentication

public struct OpenMusicEventAuthorizationPresentationRequested: FeatureEventKey {
    public init() {}
    public typealias Value = AuthorizationPresentationRequest
}

public typealias OpenMusicEventAuthorizationPresentation = OAuthAuthorizationPresentation
public typealias OpenMusicEventAuthorizationPresenter = OAuthAuthorizationPresenter
public typealias OpenMusicEventAuthorizationNavigationDestinationModifier =
    OAuthAuthorizationNavigationDestinationModifier

public extension OAuthAuthorizationPresentation.State {
    init() {
        self.init(storage: OpenMusicEventOAuth.storage)
    }
}

public nonisolated(nonsending) func withOpenMusicEventAuthorization<Result>(
    presenter: OpenMusicEventAuthorizationPresenter,
    session: Shared<OAuth.Session?> = OpenMusicEventOAuth.session,
    authFailureMessage: Shared<ErrorMessage?> = OpenMusicEventOAuth.authFailureMessage,
    operation: nonisolated(nonsending) () async throws -> Result
) async throws -> Result {
    try await withOAuthAuthorization(
        presenter: presenter,
        storage: OAuthSessionStorage(
            session: session,
            sessionStore: OpenMusicEventOAuth.sessionStore,
            authFailureMessage: authFailureMessage
        ),
        operation: operation
    )
}

public extension View {
    func openMusicEventAuthorizationDestination(
        store: StoreOf<OpenMusicEventAuthorizationPresentation>
    ) -> some View {
        oauthAuthorizationDestination(store: store)
    }
}
