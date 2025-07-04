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
        self._colors = .init(wrappedValue: colors)
    }

    public init(color: OMEColor) {
        self.init(colors: [color])
    }

    public init(_ stages: [Stage.ID]) {
        self.stageIDs = stages
    }

    public init(_ stages: Set<Stage.ID>) {
        self.init(Array(stages))
    }


    var angleHeight: CGFloat = 5 / 2
    
    var stageIDs: [Stage.ID] = []
    
    @Dependency(\.defaultDatabase) var defaultDatabase
    
    @State internal var colors: [OMEColor] = []

    public var body: some View {
        Group {
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
        colors.first?.swiftUIColor ?? .green
#endif

        }
        .task { Task { await loadColors() }}
        //            Text("STAGE INDICATOR")
    }

    
    private func loadColors() async {
        guard !stageIDs.isEmpty else { return }
        
        do {
            let colors = try await defaultDatabase.read { db in
                try Stage
                    .filter(stageIDs.contains(Column("id")))
                    .select(Column("color"))
                    .fetchAll(db)
                    .map(\.color)
            }
            self.colors = colors
        } catch {
            print("Error loading stage colors: \(error)")
        }
    }
}
