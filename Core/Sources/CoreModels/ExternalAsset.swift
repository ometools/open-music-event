//
//  ExternalAsset.swift
//  open-music-event
//
//  Created by Woodrow Melling on 10/2/25.
//

import Foundation

// MARK: External Asset
public struct ExternalAsset: Equatable, Codable, Sendable {
    public var url: URL
    public var type: AssetType
    public var platform: Platform?
    public var title: String?
    public var description: String?

    public enum AssetType: Equatable, Codable, Sendable {
        case profile
        case video(VideoMetadata?)
        case audio(AudioMetadata?)
        case image(ImageMetadata?)
        case document(DocumentMetadata?)
        case playlist(PlaylistMetadata?)
        case livestream(LivestreamMetadata?)
    }

    public struct VideoMetadata: Equatable, Codable, Sendable {
        public var durationSeconds: Int?
        public var thumbnailURL: URL?
        public var resolution: String? // e.g., "1920x1080"
        public var quality: String? // e.g., "HD", "4K"
        
        public init(durationSeconds: Int? = nil, thumbnailURL: URL? = nil, resolution: String? = nil, quality: String? = nil) {
            self.durationSeconds = durationSeconds
            self.thumbnailURL = thumbnailURL
            self.resolution = resolution
            self.quality = quality
        }
    }

    public struct AudioMetadata: Equatable, Codable, Sendable {
        public var durationSeconds: Int?
        public var thumbnailURL: URL?
        public var bitrate: Int?
        public var sampleRate: Int?
        
        public init(durationSeconds: Int? = nil, thumbnailURL: URL? = nil, bitrate: Int? = nil, sampleRate: Int? = nil) {
            self.durationSeconds = durationSeconds
            self.thumbnailURL = thumbnailURL
            self.bitrate = bitrate
            self.sampleRate = sampleRate
        }
    }

    public struct ImageMetadata: Equatable, Codable, Sendable {
        public var resolution: String?
        public var fileSizeBytes: Int?
        
        public init(resolution: String? = nil, fileSizeBytes: Int? = nil) {
            self.resolution = resolution
            self.fileSizeBytes = fileSizeBytes
        }
    }

    public struct DocumentMetadata: Equatable, Codable, Sendable {
        public var fileSizeBytes: Int?
        public var pageCount: Int?
        
        public init(fileSizeBytes: Int? = nil, pageCount: Int? = nil) {
            self.fileSizeBytes = fileSizeBytes
            self.pageCount = pageCount
        }
    }

    public struct PlaylistMetadata: Equatable, Codable, Sendable {
        public var trackCount: Int?
        public var totalDurationSeconds: Int?
        
        public init(trackCount: Int? = nil, totalDurationSeconds: Int? = nil) {
            self.trackCount = trackCount
            self.totalDurationSeconds = totalDurationSeconds
        }
    }

    public struct LivestreamMetadata: Equatable, Codable, Sendable {
        public var isLive: Bool?
        public var scheduledStartTime: Date?
        public var viewerCount: Int?
        
        public init(isLive: Bool? = nil, scheduledStartTime: Date? = nil, viewerCount: Int? = nil) {
            self.isLive = isLive
            self.scheduledStartTime = scheduledStartTime
            self.viewerCount = viewerCount
        }
    }

    public enum Platform: String, Equatable, Codable, Sendable, CaseIterable {
        case youtube
        case soundcloud
        case spotify
        case appleMusic = "apple_music"
        case bandcamp
        case mixcloud
        case twitch
        case instagram
        case facebook
        case twitter
        case tiktok
        case website
        
        public var label: String {
            switch self {
            case .youtube: return "YouTube"
            case .soundcloud: return "SoundCloud"
            case .spotify: return "Spotify"
            case .appleMusic: return "Apple Music"
            case .bandcamp: return "Bandcamp"
            case .mixcloud: return "Mixcloud"
            case .twitch: return "Twitch"
            case .instagram: return "Instagram"
            case .facebook: return "Facebook"
            case .twitter: return "Twitter"
            case .tiktok: return "TikTok"
            case .website: return "Website"
            }
        }
    }

    public init(
        url: URL,
        type: AssetType,
        platform: Platform? = nil,
        title: String? = nil,
        description: String? = nil
    ) {
        self.url = url
        self.type = type
        self.platform = platform ?? Self.detectPlatform(from: url)
        self.title = title
        self.description = description
    }
    
    // Auto-detect platform from URL
    private static func detectPlatform(from url: URL) -> Platform? {
        guard let host = url.host?.lowercased() else { return nil }
        
        if host.contains("youtube.com") || host.contains("youtu.be") {
            return .youtube
        } else if host.contains("soundcloud.com") {
            return .soundcloud
        } else if host.contains("spotify.com") {
            return .spotify
        } else if host.contains("music.apple.com") {
            return .appleMusic
        } else if host.contains("bandcamp.com") {
            return .bandcamp
        } else if host.contains("mixcloud.com") {
            return .mixcloud
        } else if host.contains("twitch.tv") {
            return .twitch
        } else if host.contains("instagram.com") {
            return .instagram
        } else if host.contains("facebook.com") || host.contains("fb.com") {
            return .facebook
        } else if host.contains("twitter.com") || host.contains("x.com") {
            return .twitter
        } else if host.contains("tiktok.com") {
            return .tiktok
        } else {
            return .website
        }
    }
}