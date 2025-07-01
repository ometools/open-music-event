//
//  ScheduleHourLinesView.swift
//  
//
//  Created by Woody on 2/17/22.
//

import  SwiftUI; import SkipFuse

struct DayStartsAtNoonEnvironmentKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    var dayStartsAtNoon: Bool {
        get { self[DayStartsAtNoonEnvironmentKey.self] }
        set { self[DayStartsAtNoonEnvironmentKey.self] = newValue }
    }
}

public struct ScheduleHourTag: Hashable {
    var hour: Int
    
    public init(hour: Int) {
        self.hour = hour
    }
}


public struct HourLabelsWidthPreferenceKey {
    public static let defaultValue: CGFloat = 43
    
    public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
#if os(iOS)
extension HourLabelsWidthPreferenceKey: PreferenceKey {}
#endif

public struct ScheduleHourLabelsView: View {
    public init() {}
    
    @Environment(\.dayStartsAtNoon) var dayStartsAtNoon
    #if os(iOS)
    @ScaledMetric var hourLabelsWidth: CGFloat = HourLabelsWidthPreferenceKey.defaultValue
    #elseif os(Android)
    var hourLabelsWidth: CGFloat = HourLabelsWidthPreferenceKey.defaultValue
    #endif


    public var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(0..<24) { index in
                Text(timeStringForIndex(index))
                    .id(ScheduleHourTag(hour: adjustedIndex(index)))
                    .lineLimit(1)
                    .font(.caption)
                    #if os(iOS)
                    .monospacedDigit()
                    #endif
                    .foregroundColor(.secondary)

                Spacer()
            }
        }
        .frame(maxHeight: .infinity)
    }
    
    func adjustedIndex(_ index: Int) -> Int {
        if dayStartsAtNoon {
            return (index + 12) % 24
        } else {
            return index
        }
    }
    
    func timeStringForIndex(_ index: Int) -> String{
        let index: Int = adjustedIndex(index)

        switch index {
        case 0: return "mdnt"
        case 12: return "noon"
        default:
            
            return Calendar.current.date(from: DateComponents(timeZone: .current, hour: index))!
                .formatted(
                    .dateTime.hour(.defaultDigits(amPM: .abbreviated))
                )
                .lowercased()
                .replacingOccurrences(of: " ", with: "")
        }

    }
}

//struct ScheduleHourLinesView_Previews: PreviewProvider {
//    static var previews: some View {
//        ScheduleHourLabelsView()
//            .previewDisplayName("Day starts at midnight")
//        
//        ScheduleHourLabelsView()
//            .environment(\.dayStartsAtNoon, true)
//            .previewDisplayName("Day starts at noon")
//
//    }
//}
