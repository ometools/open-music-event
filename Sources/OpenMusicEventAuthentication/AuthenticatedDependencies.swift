import ATProtoOAuth
import ComposableArchitecture2
import Sharing
import TCATProtoAuthentication

public extension FeatureProtocol {
    func openMusicEventAuthenticatedSession(
        session: Shared<OAuth.Session?> = OpenMusicEventOAuth.session,
        authFailureMessage: Shared<ErrorMessage?> = OpenMusicEventOAuth.authFailureMessage
    ) -> some FeatureProtocol<State, Action> {
        self
            .authenticatedOAuthSession(
                session: session,
                authFailureMessage: authFailureMessage
            )
    }
}
