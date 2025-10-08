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

public struct ExternalAssetsSection: View {
    let assets: [ExternalPlatform.Asset]
    let title: String

    public init(assets: [ExternalPlatform.Asset], title: String) {
        self.assets = assets
        self.title = title
    }
    
    public var body: some View {
        if !assets.isEmpty {
            Section(title) {
                ForEach(assets.indices, id: \.self) { index in
                    Row(asset: assets[index])
                }
            }
        }
    }

    public struct Row: View {
        let asset: ExternalPlatform.Asset

        @Dependency(\.defaultDatabase) var database
        @Dependency(\.externalAssetMetadataFetcher) var metadataFetcher
        @Dependency(\.date) var date
        @State var preferences: ExternalPlatform.Asset.Preferences?
        @State var isLoadingMetadata = false

        public init(asset: ExternalPlatform.Asset) {
            self.asset = asset
        }

        public var body: some View {
            Link(destination: asset.url) {
                HStack(spacing: 12) {
                    // Platform icon
                    if let platform = preferences?.platform {
                        platform.icon
                            .foregroundColor(platform.color)
                            .frame(width: 24, height: 24)
                    }

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

                        HStack {
                            if let platform = preferences?.platform {
                                Text(platform.name)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if let durationText = durationText {
                                Text("• \(durationText)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if isLoadingMetadata {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                        }
                    }

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .task {
                await loadPreferencesAndMetadata()
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
                self.preferences = try? await database.write { db in
                    // Create if doesn't exist
                    try db.execute(
                        sql: "INSERT INTO externalAssetPreferences (assetURL) VALUES (?) ON CONFLICT DO NOTHING",
                        arguments: [asset.url.absoluteString]
                    )

                    // Fetch it (platform will be auto-detected by trigger)
                    return try ExternalPlatform.Asset.Preferences
                        .filter(Column("assetURL") == asset.url.absoluteString)
                        .fetchOne(db)
                }

                guard let prefs = preferences else { return }

                // Skip if we tried recently (within 5 minutes)
                if let lastAttempt = prefs.lastMetadataFetchAttemptAt,
                   date().timeIntervalSince(lastAttempt) < 300 {
                    return
                }

                // Skip if we already have metadata
                if prefs.cachedTitle != nil {
                    return
                }

                // Fetch metadata
                isLoadingMetadata = true
                defer { isLoadingMetadata = false }

                do {
                    let metadata = try await metadataFetcher.fetch(asset.url, prefs.platform)

                    // Update database with fetched metadata
                    try await database.write { db in
                        try db.execute(
                            sql: """
                            UPDATE externalAssetPreferences
                            SET cachedTitle = ?,
                                cachedDescription = ?,
                                cachedThumbnailURL = ?,
                                cachedDurationSeconds = ?,
                                lastMetadataFetchAttemptAt = ?
                            WHERE assetURL = ?
                            """,
                            arguments: [
                                metadata.title,
                                metadata.description,
                                metadata.thumbnailURL?.absoluteString,
                                metadata.durationSeconds,
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
                    try? await database.write { db in
                        try db.execute(
                            sql: """
                            UPDATE externalAssetPreferences
                            SET lastMetadataFetchAttemptAt = ?
                            WHERE assetURL = ?
                            """,
                            arguments: [Date(), asset.url.absoluteString]
                        )
                    }
                }
            }
        }
    }
}

#Preview {
    List {
        ExternalAssetsSection(
            assets: [
                ExternalPlatform.Asset(
                    url: URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!,
                ),
                ExternalPlatform.Asset(
                    url: URL(string: "https://soundcloud.com/artist/live-set")!,
                )
            ],
            title: "Recordings"
        )
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
