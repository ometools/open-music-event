import Foundation
import OpenMusicEventComponents
import OpenMusicEventLexicon
import SwiftUI

struct CommunicationChannelRowView: View {
    let row: CommunicationChannelRow

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.channel.name)
                    .font(.headline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                if let description = row.channel.displayDescription {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if row.unreadPostCount > 0 {
                Text("\(row.unreadPostCount)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .portableMonospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.tint, in: Capsule())
                    .accessibilityLabel(
                        Text("Unread posts: \(row.unreadPostCount)")
                    )
            }

            notificationImage
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    var notificationImage: some View {
        if row.channel.notificationsRequired {
            MappedSystemImage(systemName: "bell.badge")
                .frame(width: 20, height: 20)
                .accessibilityLabel("Notifications required")
        } else if row.effectiveNotificationState == .subscribed {
            MappedSystemImage(systemName: "bell.fill")
                .frame(width: 20, height: 20)
                .accessibilityLabel("Notifications enabled")
        }
    }
}

private extension OMERecord.Channel {
    var displayDescription: String? {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
