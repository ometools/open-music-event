import ATProto
import ATProtoOAuth
import ComposableArchitecture2
import Sharing
import ComposableAtmosphere

public extension FeatureProtocol {
    func openMusicEventAuthenticatedSession(
        sessionStore: Shared<OAuth.SessionStore> = OpenMusicEventOAuth.sessionStore,
        selectedSessionID: Shared<Atmosphere.Account.ID?> = OpenMusicEventOAuth.selectedSessionID,
        authFailureMessage: Shared<ErrorMessage?> = OpenMusicEventOAuth.authFailureMessage
    ) -> some FeatureProtocol<State, Action> {
        self
            .authenticatedOAuthSession(
                storage: OAuthSessionStorage(
                    sessionStore: sessionStore,
                    authFailureMessage: authFailureMessage,
                    selectedSessionID: selectedSessionID
                )
            )
    }
}
