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
        self.modifier(AuthoringAuthorizationInvalidationModifier<AuthoringContent>())
    }
}

private struct AuthoringAuthorizationInvalidationModifier<AuthoringContent: FeatureProtocol>:
    FeatureModifier
{
    typealias AuthoringFeature = OpenMusicEventSourceEditing.Authoring<AuthoringContent>
    typealias State = OAuthAuthorization<AuthoringFeature>.State
    typealias Action = OAuthAuthorization<AuthoringFeature>.Action

    let store = FeatureStore<State, Action>()

    func body(content: Content) -> some FeatureProtocol<State, Action> {
        content
            .onChange(of: store.authentication.session?.accountID) { oldID, newID, state in
                guard oldID != newID else { return }
                let entry = state.content.entry
                state.content.invalidateAuthoring()
                store.addTask {
                    await entry.cancel()?.value
                    try store.send(.content(.refreshAdmission))
                }
            }
            .onEvent(OAuthAuthorizationInvalidated.self) { _, state in
                state.content.invalidateAuthoring()
            }
    }
}
