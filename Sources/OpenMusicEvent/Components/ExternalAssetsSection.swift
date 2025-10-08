//
//  ExternalPlatform.AssetsSection.swift
//  open-music-event
//
//  Created by Woodrow Melling on 10/2/25.
//

import SwiftUI
import CoreModels
import Dependencies
import GRDB


extension ExternalPlatform {
    public struct RowView: View {
        let asset: Asset

        @Dependency(\.defaultDatabase) var database
        @Dependency(\.oembedClient) var oembedClient
        @Dependency(\.date) var date
        @State var preferences: ExternalPlatform.Asset.Preferences?
        @State var isLoadingMetadata = false

        public init(asset: ExternalPlatform.Asset) {
            self.asset = asset
        }

        public var body: some View {
            SwiftUI.Link(destination: asset.url) {
                HStack(spacing: 12) {
                    Thumbnail(preferences: preferences)

                    VStack(alignment: .leading, spacing: 2) {
                        if let title = preferences?.cachedTitle {
                            Text(title)
                                .font(.body)
                                .foregroundColor(.primary)
                        } else {
                            Text(asset.url.absoluteString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        if let durationText = durationText {
                            Text("• \(durationText)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    if isLoadingMetadata {
                        ProgressView()
                            .scaleEffect(0.7)
                    }

                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
//            .buttonStyle(PlainButtonStyle())
            .task {
                await loadPreferencesAndMetadata()
            }
        }

        struct Thumbnail: View {
            var preferences: ExternalPlatform.Asset.Preferences?

            var body: some View {
                CachedAsyncImage(url: preferences?.cachedThumbnailURL, contentMode: .fill) {
                    ProgressView()
                }
                .frame(square: 60)
                .clipped()
                .overlay(alignment: .bottomTrailing) {
                    if let platform = preferences?.platform {
                        platform.icon?
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundColor(platform.color)
                            .opacity(0.5)
                            .frame(width: 20, height: 20)
                            .padding(2)
                    }
                }
            }
        }

        private var durationText: String? {
            preferences?.cachedDurationSeconds.map(formatDuration)
        }

        private func formatDuration(_ seconds: Int) -> String {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            let remainingSeconds = seconds % 60

            if hours > 0 {
                return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
            } else {
                return String(format: "%d:%02d", minutes, remainingSeconds)
            }
        }

        func loadPreferencesAndMetadata() async {
            await withErrorReporting {
                // Fetch or create preferences
                self.preferences = try await database.write { db in
                    // Create if doesn't exist
                    let detectedPlatform = ExternalPlatform.detectPlatform(from: asset.url)
                    try db.execute(
                        sql: "INSERT INTO externalAssetPreferences (assetURL, platform) VALUES (?, ?) ON CONFLICT DO NOTHING",
                        arguments: [asset.url.absoluteString, detectedPlatform.rawValue]
                    )

                    // Fetch it
                    return try ExternalPlatform.Asset.Preferences
                        .filter(Column("assetURL") == asset.url.absoluteString)
                        .fetchOne(db)
                }

                guard let prefs = preferences else { return }

//                // Skip if we tried recently (within 5 minutes)
//                if let lastAttempt = prefs.lastMetadataFetchAttemptAt,
//                   date().timeIntervalSince(lastAttempt) < 300 {
//                    return
//                }

                // Fetch metadata
                isLoadingMetadata = true
                defer { isLoadingMetadata = false }

                do {
                    let metadata = try await oembedClient.fetch(asset.url, prefs.platform)

                    // Update database with fetched metadata
                    // Note: oEmbed spec doesn't include duration or description fields
                    try await database.write { db in
                        try db.execute(
                            sql: """
                            UPDATE externalAssetPreferences
                            SET cachedTitle = ?,
                                cachedThumbnailURL = ?,
                                lastMetadataFetchAttemptAt = ?
                            WHERE assetURL = ?
                            """,
                            arguments: [
                                metadata.title,
                                metadata.thumbnailURL?.absoluteString,
                                Date(),
                                asset.url.absoluteString
                            ]
                        )
                    }

                    // Reload preferences to show updated data
                    self.preferences = try? await database.read { db in
                        try ExternalPlatform.Asset.Preferences
                            .filter(Column("assetURL") == asset.url.absoluteString)
                            .fetchOne(db)
                    }
                } catch {
                    // On error, just update the timestamp so we don't retry immediately
                    try await database.write { db in
                        try db.execute(
                            sql: """
                            UPDATE externalAssetPreferences
                            SET lastMetadataFetchAttemptAt = ?
                            WHERE assetURL = ?
                            """,
                            arguments: [Date(), asset.url.absoluteString]
                        )
                    }
                    throw error
                }
            }
        }
    }
}

extension ExternalPlatform {
    var color: Color {
        switch self {
        case .youtube:
            return .red
        case .soundcloud:
            return .orange
        case .spotify:
            return .green
        case .appleMusic:
            return .pink
        case .bandcamp:
            return .blue
        case .mixcloud:
            return .purple
        case .twitch:
            return .purple
        case .instagram:
            return .pink
        case .facebook:
            return .blue
        case .twitter:
            return .blue
        case .tiktok:
            return .black
        case .website:
            return .gray
        }
    }
}
