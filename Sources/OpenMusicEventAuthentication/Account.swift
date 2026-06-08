import ATProtoOAuth
import Sharing
import TCATProtoAuthentication

public typealias Account = OAuthAccount
public typealias AccountView = OAuthAccountView

public extension OAuthAccount {
    init() {
        self.init(
            baseAuthRequirement: OpenMusicEventOAuth.baseAuthRequirement,
            signUpServerConfiguration: OpenMusicEventOAuth.signUpServerConfiguration
        )
    }
}

public extension OAuthAccount.State {
    init() {
        self.init(storage: OpenMusicEventOAuth.storage)
    }

    init(
        authFailureMessage: Shared<ErrorMessage?>,
        session: Shared<OAuth.Session?>,
        sessionStore: Shared<OAuth.SessionStore>
    ) {
        self.init(
            storage: OAuthSessionStorage(
                session: session,
                sessionStore: sessionStore,
                authFailureMessage: authFailureMessage
            )
        )
    }
}
