//
//  SwiftUIView.swift
//  
//
//  Created by Woodrow Melling on 4/18/22.
//

import SwiftUI
import SkipFuse

import Dependencies


struct TimeIndicatorView: View {

    init() {}
    @Environment(\.dayStartsAtNoon) var dayStartsAtNoon: Bool

    var textWidth: CGFloat = 43
    var gradientHeight: CGFloat = 30
    
    var body: some View {
        Text("TIMEINDICATOR")
//        TimelineView(.periodic(from: .now, by: 1)) { context in
//            GeometryReader { geo in
//                if shouldShowTimeIndicator(context.date) {
//                    ZStack(alignment: .leading) {
//                        
//                        // Current time text
//                        Text(
//                            context.date
//                                .formatted(timeFormat)
//                                .lowercased()
//                                .replacingOccurrences(of: " ", with: "")
//                        )
//                        .foregroundColor(Color.accentColor)
//                        .font(.caption)
//                        .background {
//                            // Gradient behind the current time text so that it doesn't overlap with the grid time text
//                            Rectangle()
//                                .fill(
//                                    LinearGradient(
//                                        colors: [.clear, .red, .red, .clear],
//                                        startPoint: .top,
//                                        endPoint: .bottom
//                                    )
//                                )
//                                .frame(height: gradientHeight)
//                        }
//
//
//                        // Circle indicator
//                        Circle()
//                            .fill(Color.accentColor)
//                            .frame(square: 5)
//                            .offset(x: textWidth, y: 0)
//                        
//                        
//                        // Line going across the schedule
//                        Rectangle()
//                            .fill(Color.accentColor)
//                            .frame(height: 1)
//                            .offset(x: textWidth, y: 0)
//                    }
//                    .position(x: geo.size.width / 2, y: context.date.toY(containerHeight: geo.size.height, dayStartsAtNoon: dayStartsAtNoon))
//                } else {
//                    EmptyView()
//                }
//            }
//        }
    }
    
    func shouldShowTimeIndicator(_ currentTime: Date) -> Bool {
        return true
    }

    var timeFormat: Date.FormatStyle {
        var format = Date.FormatStyle.dateTime.hour(.defaultDigits(amPM: .narrow)).minute()
        format.timeZone = NSTimeZone.default
        return format
    }
}

//struct TimeIndicatorView_Previews: PreviewProvider {
//    static var previews: some View {
//        TimeIndicatorView()
//    }
//}
