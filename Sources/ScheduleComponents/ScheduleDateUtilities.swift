import Foundation
import SwiftUI

public extension Date {
    func ceil(precision: TimeInterval) -> Date {
        round(precision: precision, rule: .up)
    }

    func floor(precision: TimeInterval) -> Date {
        round(precision: precision, rule: .down)
    }

    func round(precision: TimeInterval) -> Date {
        round(precision: precision, rule: .toNearestOrAwayFromZero)
    }

    func round(precision: TimeInterval, rule: FloatingPointRoundingRule) -> Date {
        let seconds = (timeIntervalSinceReferenceDate / precision).rounded(rule) * precision
        return Date(timeIntervalSinceReferenceDate: seconds)
    }

    func toY(containerHeight: CGFloat, in range: DateInterval) -> CGFloat {
        let progress = timeIntervalSince(range.start) / range.duration
        return containerHeight * CGFloat(progress)
    }

    func toX(containerWidth: CGFloat, in range: DateInterval) -> CGFloat {
        let progress = timeIntervalSince(range.start) / range.duration
        return containerWidth * CGFloat(progress)
    }
}

public extension Int {
    var seconds: TimeInterval { TimeInterval(self) }
    var minutes: TimeInterval { seconds * 60 }
    var hours: TimeInterval { minutes * 60 }
    var days: TimeInterval { hours * 24 }
}

public extension TimeInterval {
    var seconds: TimeInterval { self }
    var minutes: TimeInterval { seconds * 60 }
    var hours: TimeInterval { minutes * 60 }
    var days: TimeInterval { hours * 24 }
}
