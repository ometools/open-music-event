//
//  ExternalAssetMetadataFetcher.swift
//  open-music-event
//
//  Created by Claude Code on 10/7/25.
//

import Foundation
import Dependencies
import CoreModels

/// Metadata fetched from external platforms
public struct FetchedAssetMetadata: Sendable {
    public var title: String?
    public var description: String?
    public var thumbnailURL: URL?
    public var durationSeconds: Int?

    public init(
        title: String? = nil,
        description: String? = nil,
        thumbnailURL: URL? = nil,
        durationSeconds: Int? = nil
    ) {
        self.title = title
        self.description = description
        self.thumbnailURL = thumbnailURL
        self.durationSeconds = durationSeconds
    }
}

/// Dependency for fetching metadata from external platforms like YouTube, SoundCloud, etc.
public struct ExternalAssetMetadataFetcher: Sendable {
    public var fetch: @Sendable (URL, ExternalPlatform?) async throws -> FetchedAssetMetadata

    public init(
        fetch: @escaping @Sendable (URL, ExternalPlatform?) async throws -> FetchedAssetMetadata
    ) {
        self.fetch = fetch
    }
}

extension ExternalAssetMetadataFetcher: DependencyKey {
    public static let liveValue = ExternalAssetMetadataFetcher { url, platform in
        // TODO: Implement actual metadata fetching
        // For now, return empty metadata

        // Example implementation structure:
        // switch platform {
        // case .youtube:
        //     return try await fetchYouTubeMetadata(url)
        // case .soundcloud:
        //     return try await fetchSoundCloudMetadata(url)
        // case .spotify:
        //     return try await fetchSpotifyMetadata(url)
        // default:
        //     return FetchedAssetMetadata()
        // }

        return FetchedAssetMetadata()
    }

    public static let testValue = ExternalAssetMetadataFetcher { url, platform in
        // Return mock data for tests
        return FetchedAssetMetadata(
            title: "Test Title",
            description: "Test Description",
            thumbnailURL: URL(string: "https://example.com/thumbnail.jpg"),
            durationSeconds: 300
        )
    }
}

extension DependencyValues {
    public var externalAssetMetadataFetcher: ExternalAssetMetadataFetcher {
        get { self[ExternalAssetMetadataFetcher.self] }
        set { self[ExternalAssetMetadataFetcher.self] = newValue }
    }
}
