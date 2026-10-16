import ATProto
import ATProtoOAuth
import Foundation
import OpenMusicEventAuthentication
import OpenMusicEventLexicon

func canonicalWorkspaceTestOAuthSession(actorID: DID) -> OAuth.Session {
    OAuth.Session(
        accountID: Atmosphere.Account.ID(actorID),
        pdsHost: "owner.pds.example",
        tokenEndpoint: OAuth.AuthorizationServer.TokenEndpoint(
            URL(string: "https://owner.pds.example/oauth/token")!
        ),
        scope: OAuth.Scope(rawValue: OAuth.Permission.atproto.rawValue),
        accessToken: OAuth.AccessToken(rawValue: "canonical-workspace-test-access-token"),
        refreshToken: OAuth.RefreshToken(rawValue: "canonical-workspace-test-refresh-token"),
        dpopKey: OAuth.DPOP.Key()
    )
}
