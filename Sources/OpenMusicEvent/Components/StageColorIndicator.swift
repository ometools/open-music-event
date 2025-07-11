//
//  StagesIndicatorView.swift
//  open-music-event
//
//  Created by Woodrow Melling on 5/14/25.
//

import SwiftUI; import SkipFuse
import CoreModels
import Dependencies
import GRDB

struct StageIndicatorView: View {
    public init(colors: [OMEColor]) {
        self.colors = colors
    }

    public init(color: OMEColor) {
        self.init(colors: [color])
    }

    var angleHeight: CGFloat = 5 / 2
    

    @Dependency(\.defaultDatabase) var defaultDatabase
    

    var colors: [OMEColor] = []

    public var body: some View {
        Group {
            let _ = print("StageIndicatorView colors count: \(colors.count)")
#if os(iOS)
        Canvas { context, size in
            let segmentHeight = size.height / CGFloat(colors.count)
            for (index, color) in colors.map(\.swiftUIColor).enumerated() {
                let index = CGFloat(index)

                context.fill(
                    Path { path in
                        let topLeft = CGPoint(
                            x: 0,
                            y: index * segmentHeight - angleHeight
                        )

                        let topRight = CGPoint(
                            x: size.width,
                            y: index > 0 ?
                            index * segmentHeight + angleHeight :
                                index * segmentHeight
                        )

                        let bottomLeft = CGPoint(
                            x: 0,
                            y: index == colors.indices.last.flatMap { CGFloat($0) } ?
                            index * segmentHeight + segmentHeight :
                                index * segmentHeight + segmentHeight - angleHeight
                        )

                        let bottomRight = CGPoint(
                            x: size.width,
                            y: index * segmentHeight + segmentHeight + angleHeight
                        )

                        path.move(to: topLeft)
                        path.addLine(to: topRight)
                        path.addLine(to: bottomRight)
                        path.addLine(to: bottomLeft)
                    },
                    with: .color(color)
                )
            }
        }
        #else
            colors.first?.swiftUIColor .clear
        #endif

        }

    }
}
