//
//  ExternalPlatform.Asset.swift
//  open-music-event
//
//  Created by Woodrow Melling on 10/2/25.
//

import Foundation

public enum ExternalPlatform: String, Equatable, Codable, Sendable, CaseIterable {
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

    public var name: String {
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
    // Auto-detect platform from URL
    public static func detectPlatform(from url: URL) -> Self? {
        let host = url.absoluteString
        if host.contains("youtube") || host.contains("youtu.be") {
            return .youtube
        } else if host.contains("soundcloud") {
            return .soundcloud
        } else if host.contains("spotify") {
            return .spotify
        } else if host.contains("music.apple") {
            return .appleMusic
        } else if host.contains("bandcamp") {
            return .bandcamp
        } else if host.contains("mixcloud") {
            return .mixcloud
        } else if host.contains("twitch.tv") {
            return .twitch
        } else if host.contains("instagram") {
            return .instagram
        } else if host.contains("facebook") || host.contains("fb.com") {
            return .facebook
        } else if host.contains("twitter") || host.contains("x.com") {
            return .twitter
        } else if host.contains("tiktok.com") {
            return .tiktok
        } else {
            return .website
        }
    }
}



public extension ExternalPlatform {
    struct Link: Equatable, Codable, Sendable {
        public var url: URL
        public var platform: ExternalPlatform?

        public init(url: URL) {
            self.url = url
            self.platform = .detectPlatform(from: url)
        }

        public init(url: URL, platform: ExternalPlatform?) {
            self.url = url
            self.platform = platform
        }


        public var withDetectedPlatform: Self {
            Link(
                url: self.url,
                platform: self.platform ?? .detectPlatform(from: url)
            )
        }
    }

    struct Asset: Equatable, Codable, Sendable {

        public init(url: URL) {
            self.url = url
        }
        public let url: URL

        public enum AssetType: Equatable, Codable, Sendable {
            case profile
            case video(VideoMetadata?)
            case audio(AudioMetadata?)
            case image(ImageMetadata?)
            case document(DocumentMetadata?)
            case playlist(PlaylistMetadata?)
            case livestream(LivestreamMetadata?)
        }
    }
}

extension ExternalPlatform.Asset {

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
}

