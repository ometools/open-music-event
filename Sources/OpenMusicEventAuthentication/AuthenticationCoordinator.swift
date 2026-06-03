import ATProtoOAuth
import TCATProtoAuthentication

public typealias AuthenticationCoordinator = OAuthAuthenticationCoordinator
public typealias AuthenticationCoordinatorView = OAuthAuthenticationCoordinatorView
public typealias AuthorizationFlowSheetView = OAuthAuthorizationFlowSheetView
public typealias OpenMusicEventAuthorizationFlowView = OAuthAuthorizationFlowSheetView
public typealias OpenMusicEventAuthorizationFormView = OAuthAuthorizationFormView

public extension OAuthAuthenticationCoordinator.State {
    init() {
        self.init(storage: OpenMusicEventOAuth.storage)
    }
}

public extension OpenMusicEventOAuth {
    static func authorizationFlowState(
        for request: AuthorizationPresentationRequest,
        session: OAuth.Session?,
        sessionStore: OAuth.SessionStore
    ) -> AuthorizationFlow.State {
        OAuthAuthenticationCoordinator.authorizationFlowState(
            for: request,
            session: session,
            sessionStore: sessionStore
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
}
