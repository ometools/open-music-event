import Dependencies
import TCATProtoAuthentication

public typealias OpenMusicEventAuthorizationRequests = OAuthAuthorizationRequests

public extension DependencyValues {
    var openMusicEventAuthorizationRequests: OpenMusicEventAuthorizationRequests {
        get { oauthAuthorizationRequests }
        set { oauthAuthorizationRequests = newValue }
    }
}
