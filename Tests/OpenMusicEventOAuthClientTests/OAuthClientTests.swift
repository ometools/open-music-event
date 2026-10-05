import Foundation
import OpenMusicEventOAuthClient
import Testing

@Test func productionIdentityPreservesExportedPermissions() throws {
    let data = try OpenMusicEventOAuthClient.production.metadataData(from:
        Data(#"{"scope":"atproto repo:example.record","grant_types":["authorization_code","refresh_token"]}"#.utf8))
    let metadata = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(metadata["client_uri"] as? String == "https://openmusicevent.app")
    #expect(metadata["scope"] as? String == "atproto repo:example.record")
    #expect(metadata["redirect_uris"] as? [String] == ["app.openmusicevent:/oauth/callback"])
}

@Test func privateIdentityHasNoProductionReferences() throws {
    let identity = OpenMusicEventOAuthClient.privateAuthentication
    let data = try identity.privateMetadataData()
    let metadata = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(metadata["client_id"] as? String == "https://metadata.ome-auth.test/oauth-client-metadata.json")
    #expect(metadata["client_uri"] as? String == "https://metadata.ome-auth.test/")
    #expect(metadata["redirect_uris"] as? [String] == ["test.ome-auth.metadata:/oauth/callback"])
    #expect(metadata["scope"] as? String == OpenMusicEventOAuthClient.privateScope)
    #expect(!String(decoding: data, as: UTF8.self).contains("openmusicevent.app"))
    #expect(identity.isCallbackURL(URL(string: "test.ome-auth.metadata:/oauth/callback?code=fixture&state=fixture")!))
    #expect(!identity.isCallbackURL(URL(string: "app.openmusicevent:/oauth/callback")!))
}
