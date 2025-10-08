//
//  OEmbedClient.swift
//  open-music-event
//
//  Created by Claude Code on 10/7/25.
//

import Foundation
import Dependencies
import CoreModels

/// Metadata fetched from oEmbed endpoints
/// Conforms to the oEmbed specification: https://oembed.com
public struct OEmbedMetadata: Sendable, Decodable {
    // Required fields
    public let type: OEmbedType
//    public let version: String

    // Common optional fields
    public let title: String?
    public let authorName: String?
    public let authorURL: URL?
    public let providerName: String?
    public let providerURL: URL?
    public let cacheAge: Int?
    public let thumbnailURL: URL?
    public let thumbnailWidth: Int?
    public let thumbnailHeight: Int?

//    // Type-specific fields
    public let html: String?
//    public let width: Int?
//    public let height: Int?
//    public let url: URL?

    public enum OEmbedType: String, Codable, Sendable {
        case photo
        case video
        case link
        case rich
    }

    enum CodingKeys: String, CodingKey {
        case type
//        case version
        case title
        case authorName = "author_name"
        case authorURL = "author_url"
        case providerName = "provider_name"
        case providerURL = "provider_url"
        case cacheAge = "cache_age"
        case thumbnailURL = "thumbnail_url"
        case thumbnailWidth = "thumbnail_width"
        case thumbnailHeight = "thumbnail_height"
        case html
//        case width
//        case height
//        case url
    }
}

import Dependencies
import DependenciesMacros

/// Dependency for fetching metadata from external platforms via oEmbed endpoints
@DependencyClient
public struct OEmbedClient: Sendable {
    public var fetch: @Sendable (URL, ExternalPlatform?) async throws -> OEmbedMetadata
}

import HTTPClient
//import HTTPClient
extension OEmbedClient: DependencyKey {
    public static let liveValue = OEmbedClient { url, platform in

        guard let oEmbedBaseURL = platform?.oEmbedBaseURL
        else {
            struct UnsupportedPlatformError: Error {}

            throw UnsupportedPlatformError()
        }

        @Dependency(\.httpClient) var httpClient

        let metadata: OEmbedMetadata = try await httpClient.get(oEmbedBaseURL, queryItems: [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "url", value: "\(url.absoluteString)")
        ])

        return metadata
    }
}

extension ExternalPlatform {
    /// Returns the oEmbed endpoint URL for platforms that support it
    /// Note: Some platforms require authentication or don't support oEmbed
    var oEmbedBaseURL: URL? {
        switch self {
        // Platforms with official oEmbed support (no auth required)
        case .youtube:
            URL(string: "https://www.youtube.com/oembed")
        case .soundcloud:
            URL(string: "https://soundcloud.com/oembed")
        case .spotify:
            URL(string: "https://open.spotify.com/oembed")
        case .twitter:
            URL(string: "https://publish.twitter.com/oembed")
        case .tiktok:
            URL(string: "https://www.tiktok.com/oembed")

        // Platforms with limited/deprecated oEmbed support
        // Note: Instagram and Facebook require OAuth and app approval
        // Note: Apple Music has no official oEmbed endpoint
        // Note: Bandcamp has no official oEmbed endpoint
        // Note: Mixcloud has no official oEmbed endpoint
        // Note: Twitch deprecated their oEmbed endpoint
        // Note: Website is a generic fallback
        case .appleMusic, .bandcamp, .mixcloud, .twitch, .instagram, .facebook, .website:
            nil
        }
    }
}

extension DependencyValues {
    public var oembedClient: OEmbedClient {
        get { self[OEmbedClient.self] }
        set { self[OEmbedClient.self] = newValue }
    }
}
