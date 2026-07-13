import SwiftUI

public struct SchedulePerformanceRow: View {
    @Environment(\.needsStageDisambiguation) var needsStageDisambiguation
    let row: PerformanceRow
    let subtitle: String

    public init(
        row: PerformanceRow,
        subtitle: String
    ) {
        self.row = row
        self.subtitle = subtitle
    }

    public var body: some View {
        HStack(spacing: 10) {
            if needsStageDisambiguation {
                RoundedRectangle(cornerRadius: 2)
                    .fill(row.stage?.color.swiftUIColor ?? .secondary.opacity(0.35))
                    .frame(width: 5)

                stageIcon
                    .frame(width: 60, height: 60)
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .lineLimit(2)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .frame(height: 60)
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .foregroundStyle(.primary)
    }

    @ViewBuilder
    private var stageIcon: some View {
        if let stage = row.stage {
            ScheduleStageIcon(stage: stage)
        } else {
            Image(systemName: "music.note")
                .resizable()
                .scaledToFit()
                .padding(14)
                .foregroundStyle(.secondary)
        }
    }
}
