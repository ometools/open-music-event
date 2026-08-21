import OpenMusicEventLexicon
import SwiftUI

struct CommsPostRowView: View {
    let post: CommsPost
    let isRead: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if !isRead {
                        Circle()
                            .fill(.tint)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                    }

                    Text(post.title)
                        .font(.headline)
                        .fontWeight(isRead ? .regular : .semibold)
                        .foregroundStyle(.primary)

                    Spacer()
                }

                if let timestamp = post.timestamp {
                    Text(timestamp, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            CommsMarkdownText(post.contents)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .lineLimit(4)
        }
        .padding(.vertical, 4)
        .accessibilityValue(Text(isRead ? "Read" : "Unread"))
    }
}
