import ComposableArchitecture2
import OpenMusicEventAppEventViewer
import OpenMusicEventAuthentication
import OpenMusicEventSourceEditing
import TCATProtoAuthentication

public typealias OpenMusicEventAuthoring<Content: FeatureProtocol> =
    OAuthAuthorization<OpenMusicEventSourceEditing.Authoring<Content>>

public extension OAuthAuthorization
where Content == OpenMusicEventSourceEditing.Authoring<EventViewer> {
    init() {
        self.init(storage: OpenMusicEventOAuth.storage) {
            OpenMusicEventSourceEditing.Authoring {
                EventViewer()
            }
        }
    }
}

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
