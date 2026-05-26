import ATProtoOAuth
import ComposableArchitecture2
import Foundation
import TCATProtoAuthentication

public struct OpenMusicEventAuthorizationPresentationRequested: FeatureEventKey {
    public init() {}
    public typealias Value = AuthorizationPresentationRequest
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
