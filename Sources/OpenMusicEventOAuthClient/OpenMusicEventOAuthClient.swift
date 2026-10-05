import Foundation

/// The public native client identity shared by the apps and their metadata server.
public enum OpenMusicEventOAuthClient: String, Sendable, Equatable {
    case production
    case privateAuthentication = "private-authentication"

    public static let eventPublicationPermissions = [
        "repo:events.openmusic.event?action=create",
        "repo:events.openmusic.event?action=update",
        "blob:image/png",
        "blob:image/jpeg",
    ]

    public static var privateScope: String {
        (["atproto"] + eventPublicationPermissions).joined(separator: " ")
    }

    public var metadataURL: URL {
        switch self {
        case .production: URL(string: "https://openmusicevent.app/.well-known/oauth-client-metadata.json")!
        case .privateAuthentication: URL(string: "https://metadata.ome-auth.test/oauth-client-metadata.json")!
        }
    }

    public var homepageURL: URL {
        switch self {
        case .production: URL(string: "https://openmusicevent.app")!
        case .privateAuthentication: URL(string: "https://metadata.ome-auth.test/")!
        }
    }

    public var redirectURL: URL {
        switch self {
        case .production: URL(string: "app.openmusicevent:/oauth/callback")!
        case .privateAuthentication: URL(string: "test.ome-auth.metadata:/oauth/callback")!
        }
    }

    /// Preserve the permission manifest and other protocol fields, replacing only identity.
    public func metadataData(from manifest: Data) throws -> Data {
        guard var metadata = try JSONSerialization.jsonObject(with: manifest) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        metadata["client_id"] = metadataURL.absoluteString
        metadata["client_uri"] = homepageURL.absoluteString
        metadata["redirect_uris"] = [redirectURL.absoluteString]
        return try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    public func privateMetadataData() throws -> Data {
        guard self == .privateAuthentication else {
            throw CocoaError(.coderInvalidValue)
        }
        return try metadataData(from: JSONSerialization.data(withJSONObject: [
            "client_name": "OME Private Authentication Tests",
            "application_type": "native",
            "grant_types": ["authorization_code", "refresh_token"],
            "response_types": ["code"],
            "scope": Self.privateScope,
            "token_endpoint_auth_method": "none",
            "dpop_bound_access_tokens": true,
        ]))
    }

    public func isCallbackURL(_ url: URL) -> Bool {
        url.scheme == redirectURL.scheme && url.host == redirectURL.host
            && url.path == redirectURL.path
    }
}
