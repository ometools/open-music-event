//
//  ExternalAssetsSection.swift
//  open-music-event
//
//  Created by Woodrow Melling on 10/2/25.
//

import SwiftUI
import CoreModels

public struct ExternalAssetsSection: View {
    let assets: [ExternalAsset]
    let title: String
    
    public init(assets: [ExternalAsset], title: String) {
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
        let asset: ExternalAsset

        public init(asset: ExternalAsset) {
            self.asset = asset
        }

        public var body: some View {
            Link(destination: asset.url) {
                HStack(spacing: 12) {
                    // Platform icon
                    Image(systemName: platformIcon(for: asset.platform))
                        .foregroundColor(platformColor(for: asset.platform))
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        if let title = asset.title {
                            Text(asset.title ?? "Recording")
                                .font(.body)
                                .foregroundColor(.primary)
                        }

                        HStack {
                            if let platform = asset.platform {
                                Text(platform.label)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if let durationText = durationText {
                                Text("• \(durationText)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
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
        }

        private var durationText: String? {
            switch asset.type {
            case .video(let metadata):
                return metadata?.durationSeconds.map(formatDuration)
            case .audio(let metadata):
                return metadata?.durationSeconds.map(formatDuration)
            default:
                return nil
            }
        }

        private func platformIcon(for platform: ExternalAsset.Platform?) -> String {
            switch platform {
            case .youtube:
                return "play.rectangle.fill"
            case .soundcloud:
                return "waveform"
            case .spotify:
                return "music.note"
            case .appleMusic:
                return "music.note"
            case .bandcamp:
                return "music.note.list"
            case .mixcloud:
                return "waveform.path"
            case .twitch:
                return "tv.fill"
            case .instagram:
                return "camera.fill"
            case .facebook:
                return "person.2.fill"
            case .twitter:
                return "message.fill"
            case .tiktok:
                return "video.fill"
            case .website, .none:
                return "link"
            }
        }

        private func platformColor(for platform: ExternalAsset.Platform?) -> Color {
            switch platform {
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
            case .website, .none:
                return .gray
            }
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
    }
}

#Preview {
    List {
        ExternalAssetsSection(
            assets: [
                ExternalAsset(
                    url: URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!,
                    type: .video(nil),
                    title: "Full Set Recording"
                ),
                ExternalAsset(
                    url: URL(string: "https://soundcloud.com/artist/live-set")!,
                    type: .audio(nil),
//                    title: "Audio Recording"
                )
            ],
            title: "Recordings"
        )
    }
}
