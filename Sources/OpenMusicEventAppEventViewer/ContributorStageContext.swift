import Foundation
import OpenMusicEventDatabase
import SwiftUI

struct ContributorStageContext {
    let contributorID: OMERecord.ID<OMERecord.Contributor>
    let scheduledPerformances: [OMERecord.Performance]
    let scheduledStages: [OMERecord.Stage]
    let eventStages: [OMERecord.Stage]

    init(
        contributorID: OMERecord.ID<OMERecord.Contributor>,
        performanceContributors: [OMERecord.Performance.Contributors],
        performances: [OMERecord.Performance],
        stages: [OMERecord.Stage]
    ) {
        self.contributorID = contributorID
        let performanceIDs = Set(
            performanceContributors
                .filter { $0.contributorID == contributorID }
                .map(\.performanceID)
        )
        let scheduledPerformances = performances.filter {
            performanceIDs.contains($0.id.performanceID)
        }
        self.scheduledPerformances = scheduledPerformances
        self.scheduledStages = Self.orderedStages(
            stages.filter { stage in
                scheduledPerformances.contains { $0.stageID == stage.id.stageID }
            }
        )
        self.eventStages = Self.orderedStages(stages)
    }

    init(
        contributorID: OMERecord.ID<OMERecord.Contributor>,
        scheduledStages: [OMERecord.Stage],
        stages: [OMERecord.Stage]
    ) {
        self.contributorID = contributorID
        self.scheduledPerformances = []
        self.scheduledStages = Self.orderedStages(scheduledStages)
        self.eventStages = Self.orderedStages(stages)
    }

    var primaryStage: OMERecord.Stage? {
        stages.first
    }

    var lineupOnlyStages: [OMERecord.Stage] {
        let scheduledStageIDs = Set(scheduledStages.map(\.id.stageID))
        return lineupStages.filter { !scheduledStageIDs.contains($0.id.stageID) }
    }

    var stages: [OMERecord.Stage] {
        let stageIDs = Set(scheduledStages.map(\.id.stageID)).union(lineupStageIDs)
        return eventStages.filter { stageIDs.contains($0.id.stageID) }
    }

    func stage(for performance: OMERecord.Performance) -> OMERecord.Stage? {
        eventStages.first { $0.id.stageID == performance.stageID }
    }

    private var lineupStageIDs: Set<OMERecord.ID<OMERecord.Stage>> {
        Set(lineupStages.map(\.id.stageID))
    }

    private var lineupStages: [OMERecord.Stage] {
        eventStages.filter { stage in
            stage.lineup?.contains(contributorID) == true
        }
    }

    private static func orderedStages(_ stages: [OMERecord.Stage]) -> [OMERecord.Stage] {
        var seen: Set<OMERecord.ID<OMERecord.Stage>> = []
        return stages
            .filter { stage in
                seen.insert(stage.id.stageID).inserted
            }
            .sorted { lhs, rhs in
                switch (lhs.sortIndex, rhs.sortIndex) {
                case let (lhs?, rhs?) where lhs != rhs:
                    return lhs < rhs
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    break
                }

                let nameComparison = lhs.name.localizedStandardCompare(rhs.name)
                if nameComparison != .orderedSame {
                    return nameComparison == .orderedAscending
                }

                return lhs.id.stageID.rawValue.rawValue < rhs.id.stageID.rawValue.rawValue
            }
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
