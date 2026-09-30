import ATProto
import ATProtoOAuth
import Dependencies
import Foundation
import Sharing
import ComposableAtmosphere

private enum SelectedOAuthSessionIDKey: DependencyKey {
    static let liveValue: @Sendable () -> Atmosphere.Account.ID? = { nil }
    static let testValue: @Sendable () -> Atmosphere.Account.ID? = { nil }
}

public extension DependencyValues {
    var selectedOAuthSessionID: Atmosphere.Account.ID? {
        get { getSelectedOAuthSessionID() }
        set {
            getSelectedOAuthSessionID = { newValue }
        }
    }

    var getSelectedOAuthSessionID: @Sendable () -> Atmosphere.Account.ID? {
        get { self[SelectedOAuthSessionIDKey.self] }
        set { self[SelectedOAuthSessionIDKey.self] = newValue }
    }


}

public extension OAuthSessionStorage {
    init(
        sessionStore: Shared<OAuth.SessionStore>,
        authFailureMessage: Shared<ErrorMessage?>,
        selectedSessionID: Shared<Atmosphere.Account.ID?>
    ) {
        syncOpenMusicEventSelectedSessionID(selectedSessionID, into: sessionStore)
        self.init(
            sessionStore: sessionStore,
            authFailureMessage: authFailureMessage
        )
    }
}

func syncOpenMusicEventSelectedSessionID(
    _ selectedSessionID: Shared<Atmosphere.Account.ID?>,
    into sessionStore: Shared<OAuth.SessionStore>
) {
    let selectedAccountID = selectedSessionID.withLock { $0 }
    sessionStore.selectedAccountID.withLock {
        $0 = selectedAccountID
    }
}
