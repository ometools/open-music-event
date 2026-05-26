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
            .transformDependency(\.getDefaultSession) { getDefaultSession in
                getDefaultSession = {
                    session.wrappedValue ?? .placeholder
                }
            }
            .transformDependency(\.getOptionalDefaultSession) { getOptionalDefaultSession in
                getOptionalDefaultSession = {
                    session.wrappedValue
                }
            }
            .transformDependency(\.errorInterceptors) {
                $0.append(
                    .tokenRefresh(
                        session: session,
                        authFailureMessage: authFailureMessage
                    )
                )
            }
    }
}
