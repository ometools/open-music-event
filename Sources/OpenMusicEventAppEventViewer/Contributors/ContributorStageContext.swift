import Foundation
import OpenMusicEventLexicon
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

struct ContributorStageContext {
    let contributorID: Contributor.ID
    let scheduledItems: [ProgramItem]
    let scheduledStages: [EventPlace]
    let lineupStages: [EventPlace]

    init(
        contributorID: Contributor.ID,
        performanceRows: [PerformanceRow],
        lineupStages: [EventPlace]
    ) {
        self.contributorID = contributorID
        self.scheduledItems = performanceRows.map(\.performance)
        self.scheduledStages = Self.orderedStages(performanceRows.compactMap(\.stage))
        self.lineupStages = Self.orderedStages(lineupStages)
    }

    init(
        contributorID: Contributor.ID,
        scheduledStages: [EventPlace],
        stages: [EventPlace]
    ) {
        self.contributorID = contributorID
        self.scheduledItems = []
        self.scheduledStages = Self.orderedStages(scheduledStages)
        self.lineupStages = Self.orderedStages(stages)
    }

    var primaryStage: EventPlace? {
        stages.first
    }

    var lineupOnlyStages: [EventPlace] {
        let scheduledStageIDs = Set(scheduledStages.map(\.id))
        return lineupStages.filter { !scheduledStageIDs.contains($0.id) }
    }

    var stages: [EventPlace] {
        Self.orderedStages(scheduledStages + lineupStages)
    }

    func stage(for item: ProgramItem) -> EventPlace? {
        stages.first { $0.id == item.eventPlace }
    }

    private static func orderedStages(_ stages: [EventPlace]) -> [EventPlace] {
        var seen: Set<EventPlace.ID> = []
        return stages
            .filter { stage in
                seen.insert(stage.id).inserted
            }
            .sorted { lhs, rhs in
                let leftOrder = lhs.stageUse?.sortIndex ?? Int.max
                let rightOrder = rhs.stageUse?.sortIndex ?? Int.max
                if leftOrder != rightOrder {
                    return leftOrder < rightOrder
                }
                let nameComparison = lhs.name.localizedStandardCompare(rhs.name)
                if nameComparison != .orderedSame {
                    return nameComparison == .orderedAscending
                }
                return lhs.id.description < rhs.id.description
            }
    }
}

extension EventPlace {
    var stageUse: EventPlace.Kind.Stage? {
        guard case let .known(.stage(use)) = kind else { return nil }
        return use
    }

    var stageUIColor: Color {
        guard let color = stageUse?.color
        else { return .secondary }
        return Color(
            red: Double((color.rawValue >> 16) & 0xFF) / 255.0,
            green: Double((color.rawValue >> 8) & 0xFF) / 255.0,
            blue: Double(color.rawValue & 0xFF) / 255.0
        )
    }

    var stageVisualIdentifier: String {
        if let icon = stageUse?.icon {
            return "icon:\(icon.rawValue)"
        }
        if let shortLabel = stageUse?.shortLabel, !shortLabel.isEmpty {
            return "text:\(shortLabel.lowercased())"
        }
        return "text:\(stageFallbackInitials.lowercased())"
    }

    var stageFallbackInitials: String {
        name.split(separator: " ")
            .filter { !$0.localizedCaseInsensitiveContains("the") }
            .compactMap(\.first)
            .prefix(2)
            .map(String.init)
            .joined()
    }
}

struct ContributorStageIndicatorView: View {
    let colors: [Color]

    var body: some View {
        ZStack {
            ForEach(Array(colors.enumerated()), id: \.offset) { index, color in
                ContributorStageIndicatorSegment(
                    stageCount: colors.count,
                    index: index,
                    angle: .degrees(15)
                )
                .fill(color)
            }
        }
    }
}

struct ContributorStageIndicatorSegment: Shape {
    let stageCount: Int
    let index: Int
    let angle: Angle

    nonisolated func path(in rect: CGRect) -> Path {
        guard stageCount > 0 else { return Path() }

        let segmentHeight = rect.height / CGFloat(stageCount)
        let segmentTop = CGFloat(index) * segmentHeight
        let segmentBottom = segmentTop + segmentHeight
        let angleHeight = rect.width * CGFloat(tan(angle.radians))
        let isTop = index == 0
        let isBottom = index == stageCount - 1
        let leftTopY = isTop ? segmentTop : segmentTop - angleHeight
        let rightTopY = isTop ? segmentTop : segmentTop + angleHeight
        let leftBottomY = isBottom ? segmentBottom : segmentBottom - angleHeight
        let rightBottomY = isBottom ? segmentBottom : segmentBottom + angleHeight

        return Path { path in
            path.move(to: CGPoint(x: 0, y: leftTopY))
            path.addLine(to: CGPoint(x: rect.width, y: rightTopY))
            path.addLine(to: CGPoint(x: rect.width, y: rightBottomY))
            path.addLine(to: CGPoint(x: 0, y: leftBottomY))
            path.closeSubpath()
        }
    }
}
