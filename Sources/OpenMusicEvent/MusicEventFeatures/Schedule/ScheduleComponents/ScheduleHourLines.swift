//
//  SwiftUIView.swift
//  
//
//  Created by Woody on 2/17/22.
//

import  SwiftUI; import SkipFuse

public struct ScheduleHourLines: View {
    
    public init() {}

    var lineColor = Color.secondary.opacity(0.5)

    public var body: some View {
        GeometryReader { proxy in
            let hourSpacing: CGFloat = 1500 / 24

            ForEach(0..<24) { index in
                let lineHeight = hourSpacing * CGFloat(index)

                ZStack {
                    Path { path in
                        path.move(
                            to: CGPoint(
                                x: 0,
                                y: lineHeight
                            )
                        )

                        path.addLine(
                            to: CGPoint(
                                x: proxy.size.width,
                                y: lineHeight
                            )
                        )
                    }
                    .stroke(lineColor)
                }
            }
        }
        .frame(maxWidth: .infinity)

    }
}
//
//struct ScheduleGridView_Previews: PreviewProvider {
//    static var previews: some View {
//        ScheduleHourLines()
//    }
//}
