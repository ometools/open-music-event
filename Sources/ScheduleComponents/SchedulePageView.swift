import Dependencies
import SwiftUI

public struct SchedulePageView<
    Element: TimelineCard,
    CardContent: View,
    EmptyContent: View
>: View {
    @Environment(\.calendar) var calendar
    @Environment(\.scheduleTimelineOrientation) var scheduleTimelineOrientation
    @Environment(\.scheduleTimeRange) var scheduleTimeRange

    let cardContent: (Element) -> CardContent
    let cards: [Element]
    let emptyContent: EmptyContent
    let groupMapping: [Int: Int]
    let groups: [Int]

    public init(
        _ cards: [Element],
        groups: [Int]? = nil,
        @ViewBuilder cardContent: @escaping (Element) -> CardContent,
        @ViewBuilder emptyContent: () -> EmptyContent
    ) {
        self.cards = cards
        self.cardContent = cardContent
        self.emptyContent = emptyContent()

        let groups = groups ?? Array(Set(cards.map(\.groupWidth.lowerBound))).sorted()
        self.groups = Array(Set(groups)).sorted()
        self.groupMapping = Dictionary(uniqueKeysWithValues: self.groups.enumerated().map { index, group in
            (group, index)
        })
    }

    public var body: some View {
        ScheduleGrid {
            if cards.isEmpty || scheduleTimeRange == nil {
                emptyContent
            } else {
                GeometryReader { geometry in
                    ForEach(cards) { scheduleItem in
                        let frame = frame(
                            for: scheduleItem,
                            in: geometry.size
                        )
                        cardContent(scheduleItem)
                            .id(scheduleItem.id)
                            .zIndex(0)
                            .placement(frame)
                    }
                }
            }
        }
    }

    func frame(for timelineCard: Element, in size: CGSize) -> CGRect {
        guard let range = scheduleTimeRange else { return .zero }
        return withDependencies {
            $0.calendar = self.calendar
        } operation: {
            timelineCard.frame(
                in: size,
                groupMapping: groupMapping,
                range: range,
                orientation: scheduleTimelineOrientation
            )
        }
    }
}

public extension TimelineCard {
    func timeOrigin(containerLength: CGFloat, in range: DateInterval) -> CGFloat {
        containerLength * CGFloat(dateInterval.start.timeIntervalSince(range.start) / range.duration)
    }

    func timeLength(in containerLength: CGFloat, range: DateInterval) -> CGFloat {
        containerLength * CGFloat(dateInterval.duration / range.duration)
    }

    func groupOrigin(containerLength: CGFloat, groupMapping: [Int: Int]) -> CGFloat {
        guard groupMapping.count > 1 else { return 0 }
        return containerLength / CGFloat(groupMapping.count) * CGFloat(groupMapping[groupWidth.lowerBound] ?? 0)
    }

    func groupLength(in containerLength: CGFloat, groupMapping: [Int: Int]) -> CGFloat {
        guard !groupMapping.isEmpty else { return containerLength }
        guard groupMapping.count > 1 else { return containerLength }

        let groupSpanCount = (groupMapping[groupWidth.upperBound] ?? 0)
            - (groupMapping[groupWidth.lowerBound] ?? 0)
            + 1
        return (containerLength / CGFloat(groupMapping.count)) * CGFloat(groupSpanCount)
    }

    func xOrigin(containerWidth: CGFloat, groupMapping: [Int: Int]) -> CGFloat {
        groupOrigin(containerLength: containerWidth, groupMapping: groupMapping)
    }

    func yOrigin(containerHeight: CGFloat, in range: DateInterval) -> CGFloat {
        timeOrigin(containerLength: containerHeight, in: range)
    }

    func size(in containerSize: CGSize, groupMapping: [Int: Int], range: DateInterval) -> CGSize {
        CGSize(
            width: width(in: containerSize, groupMapping: groupMapping),
            height: height(in: containerSize, range: range)
        )
    }

    func height(in containerSize: CGSize, range: DateInterval) -> CGFloat {
        timeLength(in: containerSize.height, range: range)
    }

    func width(in containerSize: CGSize, groupMapping: [Int: Int]) -> CGFloat {
        groupLength(in: containerSize.width, groupMapping: groupMapping)
    }

    func frame(in containerSize: CGSize, groupMapping: [Int: Int], range: DateInterval) -> CGRect {
        frame(
            in: containerSize,
            groupMapping: groupMapping,
            range: range,
            orientation: .verticalTime
        )
    }

    func frame(
        in containerSize: CGSize,
        groupMapping: [Int: Int],
        range: DateInterval,
        orientation: ScheduleTimelineOrientation
    ) -> CGRect {
        switch orientation {
        case .verticalTime:
            return CGRect(
                origin: CGPoint(
                    x: groupOrigin(containerLength: containerSize.width, groupMapping: groupMapping),
                    y: timeOrigin(containerLength: containerSize.height, in: range)
                ),
                size: CGSize(
                    width: groupLength(in: containerSize.width, groupMapping: groupMapping),
                    height: timeLength(in: containerSize.height, range: range)
                )
            )

        case .horizontalTime:
            return CGRect(
                origin: CGPoint(
                    x: timeOrigin(containerLength: containerSize.width, in: range),
                    y: groupOrigin(containerLength: containerSize.height, groupMapping: groupMapping)
                ),
                size: CGSize(
                    width: timeLength(in: containerSize.width, range: range),
                    height: groupLength(in: containerSize.height, groupMapping: groupMapping)
                )
            )
        }
    }
}

private extension View {
    func placement(_ frame: CGRect) -> some View {
        self
            .frame(width: frame.width, height: frame.height)
            .position(frame.offsetBy(dx: frame.size.width / 2, dy: frame.size.height / 2).origin)
    }
}
