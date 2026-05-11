import Dependencies
import SwiftUI

public struct SchedulePageView<
    Element: TimelineCard,
    CardContent: View,
    EmptyContent: View
>: View {
    @Environment(\.calendar) var calendar
    @Environment(\.scheduleHeight) var scheduleHeight
    @Environment(\.scheduleTimeRange) var scheduleTimeRange

    let cardContent: (Element) -> CardContent
    let cards: [Element]
    let emptyContent: EmptyContent
    let groupMapping: [Int: Int]
    let groups: [Int]

    public init(
        _ cards: [Element],
        @ViewBuilder cardContent: @escaping (Element) -> CardContent,
        @ViewBuilder emptyContent: () -> EmptyContent
    ) {
        self.cards = cards
        self.cardContent = cardContent
        self.emptyContent = emptyContent()

        let groups = Set(cards.map(\.groupWidth.lowerBound))
        self.groups = Array(groups).sorted()
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
                            in: CGSize(width: geometry.size.width, height: scheduleHeight)
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
                range: range
            )
        }
    }
}

public extension TimelineCard {
    func xOrigin(containerWidth: CGFloat, groupMapping: [Int: Int]) -> CGFloat {
        guard groupMapping.count > 1 else { return 0 }
        return containerWidth / CGFloat(groupMapping.count) * CGFloat(groupMapping[groupWidth.lowerBound] ?? 0)
    }

    func yOrigin(containerHeight: CGFloat, in range: DateInterval) -> CGFloat {
        dateInterval.start.toY(containerHeight: containerHeight, in: range)
    }

    func size(in containerSize: CGSize, groupMapping: [Int: Int], range: DateInterval) -> CGSize {
        CGSize(
            width: width(in: containerSize, groupMapping: groupMapping),
            height: height(in: containerSize, range: range)
        )
    }

    func height(in containerSize: CGSize, range: DateInterval) -> CGFloat {
        containerSize.height * CGFloat(dateInterval.duration / range.duration)
    }

    func width(in containerSize: CGSize, groupMapping: [Int: Int]) -> CGFloat {
        guard !groupMapping.isEmpty else { return containerSize.width }
        guard groupMapping.count > 1 else { return containerSize.width }

        let groupSpanCount = (groupMapping[groupWidth.upperBound] ?? 0)
            - (groupMapping[groupWidth.lowerBound] ?? 0)
            + 1
        return (containerSize.width / CGFloat(groupMapping.count)) * CGFloat(groupSpanCount)
    }

    func frame(in containerSize: CGSize, groupMapping: [Int: Int], range: DateInterval) -> CGRect {
        CGRect(
            origin: CGPoint(
                x: xOrigin(containerWidth: containerSize.width, groupMapping: groupMapping),
                y: yOrigin(containerHeight: containerSize.height, in: range)
            ),
            size: size(in: containerSize, groupMapping: groupMapping, range: range)
        )
    }
}

private extension View {
    func placement(_ frame: CGRect) -> some View {
        self
            .frame(width: frame.width, height: frame.height)
            .position(frame.offsetBy(dx: frame.size.width / 2, dy: frame.size.height / 2).origin)
    }
}
