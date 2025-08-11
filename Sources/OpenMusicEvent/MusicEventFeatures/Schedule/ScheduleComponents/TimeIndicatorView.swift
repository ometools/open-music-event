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

    @Environment(\.shouldShowTimeIndicator) var shouldShowTimeIndicator


    @Environment(\.colorScheme) var scheme

    var backgroundColor: Color {
        switch scheme {
        case .dark:
            Color.black
        case .light:
            Color.white
        @unknown default:
            Color.clear
        }
    }

    @Environment(\.calendar) var calendar

    var body: some View {
        CrossPlatformTimelineView(.periodic(by: 1)) { date in
            GeometryReader { geo in
                if shouldShowTimeIndicator {
                    ZStack(alignment: .leading) {

                        // Current time text
                        Text(
                            date
                                .formatted(timeFormat)
                                .lowercased()
                                .replacingOccurrences(of: " ", with: "")
                        )
                        .foregroundColor(Color.accentColor)
                        .font(.caption)
//                        .contentShape(Rectangle())
                        .background {
                            // Gradient behind the current time text so that it doesn't overlap with the grid time text
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [.clear, backgroundColor, backgroundColor, .clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(height: gradientHeight)

                        }


                        // Circle indicator
                        Circle()
                            .fill(Color.accentColor)
                            .frame(square: 5)
                            .offset(x: textWidth, y: 0)
                        
                        
                        // Line going across the schedule
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(height: 1)
                            .offset(x: textWidth, y: 0)
                    }
                    .position(
                        x: geo.size.width / 2,
                        y: withDependencies {
                            $0.calendar = self.calendar
                        } operation: {
                            date.toY(containerHeight: 1500, dayStartsAtNoon: dayStartsAtNoon)
                        }
                    )
                } else {
                    EmptyView()
                }
            }

        }
    }
    
    var timeFormat: Date.FormatStyle {
        var format = Date.FormatStyle.dateTime.hour(.defaultDigits(amPM: .narrow)).minute()
        format.calendar = self.calendar
        format.timeZone = calendar.timeZone
        return format
    }
}

struct CrossPlatformTimelineView<Content: View>: View {
    let schedule: PeriodicTimelineSchedule

    struct PeriodicTimelineSchedule {
        var interval: TimeInterval
        public static func periodic(by interval: TimeInterval) -> PeriodicTimelineSchedule {
            .init(interval: interval)
        }
    }

    var content: (Date) -> Content

    @State var currentDate: Date = .now
    @Environment(\.date) var date

    init(_ schedule: PeriodicTimelineSchedule, @ViewBuilder content: @escaping (Date) -> Content) {
        self.schedule = schedule
        self.content = content
    }


    var body: some View {
        content(currentDate)
            .task {
                while !Task.isCancelled {
                    self.currentDate = date()
                    try? await Task.sleep(for: .seconds(schedule.interval))
                }
            }
    }
}

enum ShowTimeIndicatorEnvironmentKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var shouldShowTimeIndicator: Bool {
        get {
            self[ShowTimeIndicatorEnvironmentKey.self]
        } set {
            self[ShowTimeIndicatorEnvironmentKey.self] = true
        }
    }
}
//struct TimeIndicatorView_Previews: PreviewProvider {
//    static var previews: some View {
//        TimeIndicatorView()
//    }
//}
