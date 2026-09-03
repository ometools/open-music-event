import Foundation
import SwiftUI

enum PerformanceTimingStatus: Equatable, Sendable {
    case nowPlaying
    case startsIn(TimeInterval)

    init?(
        startTime: Date,
        endTime: Date,
        now: Date
    ) {
        if startTime <= now, now < endTime {
            self = .nowPlaying
        } else if now < startTime {
            self = .startsIn(startTime.timeIntervalSince(now))
        } else {
            return nil
        }
    }

    static let maximumCountdownInterval: TimeInterval = 48 * 60 * 60

    var chipTitle: String? {
        switch self {
        case .nowPlaying:
            "Now Playing"
        case let .startsIn(interval) where interval <= Self.maximumCountdownInterval:
            Self.remainingText(for: interval)
        case .startsIn:
            nil
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .nowPlaying:
            "Now Playing"
        case let .startsIn(interval):
            "Starts in \(Self.remainingText(for: interval))"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .nowPlaying:
            "indicator.performance-timing.now-playing"
        case .startsIn:
            "indicator.performance-timing.starts-in"
        }
    }

    static func remainingText(for interval: TimeInterval) -> String {
        let totalMinutes = max(1, Int(ceil(interval / 60)))

        if totalMinutes == 1, interval < 60 {
            return "<1m"
        }

        if totalMinutes < 60 {
            return "\(totalMinutes)m"
        }

        let totalHours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if totalHours < 24 {
            return minutes == 0
                ? "\(totalHours)h"
                : "\(totalHours)h \(minutes)m"
        }

        let days = totalHours / 24
        let hours = totalHours % 24
        return hours == 0
            ? "\(days)d"
            : "\(days)d \(hours)h"
    }
}

struct PerformanceTimingChip: View {
    let status: PerformanceTimingStatus?

    init(status: PerformanceTimingStatus?) {
        self.status = status
    }

    init(
        startTime: Date,
        endTime: Date,
        now: Date
    ) {
        self.status = PerformanceTimingStatus(
            startTime: startTime,
            endTime: endTime,
            now: now
        )
    }

    var body: some View {
        if let status, let title = status.chipTitle {
            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(foregroundStyle(for: status))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background {
                    Capsule()
                        .fill(backgroundStyle(for: status))
                }
                .accessibilityLabel(Text(status.accessibilityTitle))
                .accessibilityIdentifier(status.accessibilityIdentifier)
        }
    }

    private func foregroundStyle(for status: PerformanceTimingStatus) -> Color {
        switch status {
        case .nowPlaying:
            .green
        case .startsIn:
            .orange
        }
    }

    private func backgroundStyle(for status: PerformanceTimingStatus) -> Color {
        foregroundStyle(for: status).opacity(0.15)
    }
}
