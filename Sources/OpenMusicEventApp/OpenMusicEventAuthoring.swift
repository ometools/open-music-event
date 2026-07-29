import ComposableArchitecture2
import OpenMusicEventAuthentication
import OpenMusicEventSourceEditing
import TCATProtoAuthentication

public typealias OpenMusicEventAuthoring<Content: FeatureProtocol> =
    OAuthAuthorization<OpenMusicEventSourceEditing.Authoring<Content>>

extension OAuthAuthorization {
    func invalidatingAuthoringWhenAuthorizationIsLost<AuthoringContent>()
        -> some FeatureProtocol<State, Action>
    where
        AuthoringContent: FeatureProtocol,
        Content == OpenMusicEventSourceEditing.Authoring<AuthoringContent>
    {
        self.onEvent(OAuthAuthorizationInvalidated.self) { _, state in
            state.content.invalidateAuthoring()
        }
    }
}
