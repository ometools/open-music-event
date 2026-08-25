import Dependencies
#if os(Android) || SKIP_BRIDGE
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

// SKIP INSERT: import skip.ui.*

public struct SchedulePageView<
    Element: TimelineCard,
    CardContent: View,
    EmptyContent: View
>: View {
    #if os(Android) || SKIP_BRIDGE
    var calendar: Calendar { .current }
    #else
    @Environment(\.calendar) var calendar
    #endif
    @Environment(\.scheduleHeight) var scheduleHeight
    @Environment(\.scheduleWidth) var scheduleWidth
    @Environment(\.scheduleTimelineOrientation) var scheduleTimelineOrientation
    @Environment(\.scheduleTimeRange) var scheduleTimeRange

    let cardContent: (Element) -> CardContent
    let cards: [Element]
    let emptyContent: EmptyContent
    let groupMapping: [Int: Int]
    let groups: [Int]
    let currentTimeLabel: (Date) -> String
    let hourLabel: (Date) -> String

    public init(
        _ cards: [Element],
        groups: [Int]? = nil,
        currentTimeLabel: @escaping (Date) -> String,
        hourLabel: @escaping (Date) -> String,
        @ViewBuilder cardContent: @escaping (Element) -> CardContent,
        @ViewBuilder emptyContent: () -> EmptyContent
    ) {
        self.cards = cards
        self.cardContent = cardContent
        self.currentTimeLabel = currentTimeLabel
        self.emptyContent = emptyContent()
        self.hourLabel = hourLabel

        let groups = groups ?? Array(Set(cards.map(\.groupWidth.lowerBound))).sorted()
        self.groups = Array(Set(groups)).sorted()
        self.groupMapping = Dictionary(uniqueKeysWithValues: self.groups.enumerated().map { index, group in
            (group, index)
        })
    }

    public var body: some View {
        ScheduleGrid(
            currentTimeLabel: currentTimeLabel,
            hourLabel: hourLabel
        ) {
            if cards.isEmpty || scheduleTimeRange == nil {
                emptyContent
            } else {
                #if os(Android) || SKIP_BRIDGE
                ZStack(alignment: .topLeading) {
                    if scheduleWidth > 0, scheduleHeight > 0 {
                        let layoutSize = ScheduleCGSize(
                            width: scheduleWidth,
                            height: scheduleHeight
                        )
                        ForEach(cards) { scheduleItem in
                            let frame = frame(
                                for: scheduleItem,
                                in: layoutSize
                            )
                            cardContent(scheduleItem)
                                .id(scheduleItem.id)
                                .zIndex(0)
                                .frame(width: frame.width, height: frame.height)
                                .offset(x: frame.minX, y: frame.minY)
                        }
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
                #else
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
                #endif
            }
        }
    }

    func frame(for timelineCard: Element, in size: ScheduleCGSize) -> ScheduleCGRect {
        guard let range = scheduleTimeRange else { return .zero }
        let layoutSize = ScheduleCGSize(
            width: scheduleWidth > 0 ? scheduleWidth : size.width,
            height: scheduleHeight
        )
        return withDependencies {
            $0.calendar = self.calendar
        } operation: {
            timelineCard.frame(
                in: layoutSize,
                groupMapping: groupMapping,
                range: range,
                orientation: scheduleTimelineOrientation
            )
        }
    }
}

public extension TimelineCard {
    func timeOrigin(containerLength: ScheduleCGFloat, in range: DateInterval) -> ScheduleCGFloat {
        containerLength * ScheduleCGFloat(dateInterval.start.timeIntervalSince(range.start) / range.duration)
    }

    func timeLength(in containerLength: ScheduleCGFloat, range: DateInterval) -> ScheduleCGFloat {
        containerLength * ScheduleCGFloat(dateInterval.duration / range.duration)
    }

    func groupOrigin(containerLength: ScheduleCGFloat, groupMapping: [Int: Int]) -> ScheduleCGFloat {
        guard groupMapping.count > 1 else { return 0 }
        return containerLength / ScheduleCGFloat(groupMapping.count) * ScheduleCGFloat(groupMapping[groupWidth.lowerBound] ?? 0)
    }

    func groupLength(in containerLength: ScheduleCGFloat, groupMapping: [Int: Int]) -> ScheduleCGFloat {
        guard !groupMapping.isEmpty else { return containerLength }
        guard groupMapping.count > 1 else { return containerLength }

        let groupSpanCount = (groupMapping[groupWidth.upperBound] ?? 0)
            - (groupMapping[groupWidth.lowerBound] ?? 0)
            + 1
        return (containerLength / ScheduleCGFloat(groupMapping.count)) * ScheduleCGFloat(groupSpanCount)
    }

    func xOrigin(containerWidth: ScheduleCGFloat, groupMapping: [Int: Int]) -> ScheduleCGFloat {
        groupOrigin(containerLength: containerWidth, groupMapping: groupMapping)
    }

    func yOrigin(containerHeight: ScheduleCGFloat, in range: DateInterval) -> ScheduleCGFloat {
        timeOrigin(containerLength: containerHeight, in: range)
    }

    func size(in containerSize: ScheduleCGSize, groupMapping: [Int: Int], range: DateInterval) -> ScheduleCGSize {
        ScheduleCGSize(
            width: width(in: containerSize, groupMapping: groupMapping),
            height: height(in: containerSize, range: range)
        )
    }

    func height(in containerSize: ScheduleCGSize, range: DateInterval) -> ScheduleCGFloat {
        timeLength(in: containerSize.height, range: range)
    }

    func width(in containerSize: ScheduleCGSize, groupMapping: [Int: Int]) -> ScheduleCGFloat {
        groupLength(in: containerSize.width, groupMapping: groupMapping)
    }

    func frame(in containerSize: ScheduleCGSize, groupMapping: [Int: Int], range: DateInterval) -> ScheduleCGRect {
        frame(
            in: containerSize,
            groupMapping: groupMapping,
            range: range,
            orientation: .verticalTime
        )
    }

    func frame(
        in containerSize: ScheduleCGSize,
        groupMapping: [Int: Int],
        range: DateInterval,
        orientation: ScheduleTimelineOrientation
    ) -> ScheduleCGRect {
        switch orientation {
        case .verticalTime:
            return ScheduleCGRect(
                origin: ScheduleCGPoint(
                    x: groupOrigin(containerLength: containerSize.width, groupMapping: groupMapping),
                    y: timeOrigin(containerLength: containerSize.height, in: range)
                ),
                size: ScheduleCGSize(
                    width: groupLength(in: containerSize.width, groupMapping: groupMapping),
                    height: timeLength(in: containerSize.height, range: range)
                )
            )

        case .horizontalTime:
            return ScheduleCGRect(
                origin: ScheduleCGPoint(
                    x: timeOrigin(containerLength: containerSize.width, in: range),
                    y: groupOrigin(containerLength: containerSize.height, groupMapping: groupMapping)
                ),
                size: ScheduleCGSize(
                    width: timeLength(in: containerSize.width, range: range),
                    height: groupLength(in: containerSize.height, groupMapping: groupMapping)
                )
            )
        }
    }
}

private extension View {
    func placement(_ frame: ScheduleCGRect) -> some View {
        self
            .frame(width: frame.width, height: frame.height)
            .position(frame.offsetBy(dx: frame.size.width / 2, dy: frame.size.height / 2).origin)
    }
}
