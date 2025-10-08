//
//  ExternalAssetMetadataFetcher.swift
//  open-music-event
//
//  Created by Claude Code on 10/7/25.
//

import Foundation
import Dependencies
import CoreModels

/// Metadata fetched from oEmbed endpoints
public struct OEmbedMetadata: Sendable {
    public var title: String?
    public var description: String?
    public var thumbnailURL: URL?
    public var durationSeconds: Int?
    public var platform: ExternalPlatform?

    public init(
        title: String? = nil,
        description: String? = nil,
        thumbnailURL: URL? = nil,
        durationSeconds: Int? = nil,
        platform: ExternalPlatform? = nil
    ) {
        self.title = title
        self.description = description
        self.thumbnailURL = thumbnailURL
        self.durationSeconds = durationSeconds
        self.platform = platform
    }
}

import Dependencies
import DependenciesMacros

/// Dependency for fetching metadata from external platforms via oEmbed endpoints
@DependencyClient
public struct OEmbedClient: Sendable {
    public var fetch: @Sendable (URL, ExternalPlatform?) async throws -> OEmbedMetadata
}

extension OEmbedClient: DependencyKey {
    public static let liveValue = OEmbedClient { url, platform in
        try? await Task.sleep(for: .seconds(2))
        // Return mock data for tests
        return OEmbedMetadata(
            title: "Test Title",
            description: "Test Description",
            thumbnailURL: URL(string: "https://example.com/thumbnail.jpg"),
            durationSeconds: 300
        )
    }
}

extension DependencyValues {
    public var oembedClient: OEmbedClient {
        get { self[OEmbedClient.self] }
        set { self[OEmbedClient.self] = newValue }
    }
}
