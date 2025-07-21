//
//  StagesIndicatorView.swift
//  open-music-event
//
//  Created by Woodrow Melling on 5/14/25.
//

import SwiftUI
import SkipFuse
import CoreModels
import Dependencies
import GRDB

struct StageIndicatorAngleKey: EnvironmentKey {
    static let defaultValue: Angle = .degrees(15)
}

extension EnvironmentValues {
    var stageIndicatorAngle: Angle {
        get { self[StageIndicatorAngleKey.self] }
        set { self[StageIndicatorAngleKey.self] = newValue }
    }
}

extension View {
    func stageIndicatorAngle(_ angle: Angle) -> some View {
        environment(\.stageIndicatorAngle, angle)
    }
}

struct StageIndicatorView: View {
    public init(colors: [OMEColor]) {
        self.colors = colors.map(\.swiftUIColor)
    }

    public init(color: OMEColor) {
        self.init(colors: [color])
    }

    public init(colors: [Color]) {
        self.colors = colors
    }

    var angleHeight: CGFloat = 5 / 2
    

    @Dependency(\.defaultDatabase) var defaultDatabase
    @Environment(\.stageIndicatorAngle) var stageIndicatorAngle

    var colors: [Color] = []

    public var body: some View {
        ZStack {
            ForEach(Array(colors.enumerated()), id: \.offset) { index, color in
                StageIndicator(stageCount: colors.count, index: index, angle: stageIndicatorAngle)
                    .fill(color)
            }
        }
    }

    struct StageIndicator: Shape {
        let stageCount: Int
        let index: Int
        var angle: Angle
        
        nonisolated func path(in rect: CGRect) -> Path {
            let segmentHeight = rect.height / CGFloat(stageCount)
            let indexFloat = CGFloat(index)
            
            let segmentTop = indexFloat * segmentHeight
            let segmentBottom = segmentTop + segmentHeight
            
            let angleHeight = rect.width * tan(angle.radians)
            
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
}
