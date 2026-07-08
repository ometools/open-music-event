import ATProtoOAuth
import ComposableArchitecture2
import Sharing
import TCATProtoAuthentication

public extension FeatureProtocol {
    func openMusicEventAuthenticatedSession(
        sessionStore: Shared<OAuth.SessionStore> = OpenMusicEventOAuth.sessionStore,
        authFailureMessage: Shared<ErrorMessage?> = OpenMusicEventOAuth.authFailureMessage
    ) -> some FeatureProtocol<State, Action> {
        self
            .authenticatedOAuthSession(
                storage: OAuthSessionStorage(
                    sessionStore: sessionStore,
                    authFailureMessage: authFailureMessage
                )
            )
    }
}
