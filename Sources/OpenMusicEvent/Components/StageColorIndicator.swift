//
//  StagesIndicatorView.swift
//  open-music-event
//
//  Created by Woodrow Melling on 5/14/25.
//

import SwiftUI; import SkipFuse
import CoreModels
// import SharingGRDB

public extension Stage {
    struct IndicatorView: View {
        public init(colors: [OMEColor]) {
//            self._colors = .init(wrappedValue: colors)
        }

        public init(color: OMEColor) {
            self.init(colors: [color])
        }

        public init(_ stages: [Stage.ID]) {

            // TODO: Replace with GRDB query
            // let query = Stage.where { $0.id.in(stages) }.select { $0.color }
            // self._colors = FetchAll(query)

        }

        public init(_ stages: Set<Stage.ID>) {
            self.init(Array(stages))
        }


        var angleHeight: CGFloat = 5 / 2

        // TODO: Replace @FetchAll with GRDB query
        var colors: [OMEColor] = []

        public var body: some View {
            Text("STAGE INDICATOR")
//            Canvas { context, size in
//                let segmentHeight = size.height / CGFloat(colors.count)
//                for (index, color) in colors.map(\.swiftUIColor).enumerated() {
//                    let index = CGFloat(index)
//
//                    context.fill(
//                        Path { path in
//                            let topLeft = CGPoint(
//                                x: 0,
//                                y: index * segmentHeight - angleHeight
//                            )
//
//                            let topRight = CGPoint(
//                                x: size.width,
//                                y: index > 0 ?
//                                    index * segmentHeight + angleHeight :
//                                    index * segmentHeight
//                            )
//
//                            let bottomLeft = CGPoint(
//                                x: 0,
//                                y: index == colors.indices.last.flatMap { CGFloat($0) } ?
//                                    index * segmentHeight + segmentHeight :
//                                    index * segmentHeight + segmentHeight - angleHeight
//                            )
//
//                            let bottomRight = CGPoint(
//                                x: size.width,
//                                y: index * segmentHeight + segmentHeight + angleHeight
//                            )
//
//                            path.move(to: topLeft)
//                            path.addLine(to: topRight)
//                            path.addLine(to: bottomRight)
//                            path.addLine(to: bottomLeft)
//                        },
//                        with: .color(color)
//                    )
//                }
//            }
        }
    }

}
