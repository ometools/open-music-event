//
//  File.swift
//  
//
//  Created by Woodrow Melling on 5/23/23.
//

import SwiftUI; import SkipFuse

public struct SchedulePageView<
    Element: TimelineCard,
    CardContent: View
>: View {
    
    @Environment(\.dayStartsAtNoon) var dayStartsAtNoon
    
    var cards: [Element]
    var cardContent: (Element) -> CardContent
    var groups: [Int]
    
    var groupMapping: [Int:Int] = [:]
    
    public init(
        _ cards: [Element],
        @ViewBuilder cardContent: @escaping (Element) -> CardContent
    ) {
        self.cards = cards
        self.cardContent = cardContent
        
        // Calculate distinct group numbers
        var groups = Set<Int>.init()
        for card in cards {
            groups.insert(card.groupWidth.lowerBound)
        }
        
        self.groups = Array(groups).sorted()
        
        var groupMapping: [Int:Int] = [:]
        for (idx, group) in self.groups.enumerated() {
            groupMapping[group] = idx
        }
        self.groupMapping = groupMapping
    }
    
    public var body: some View {
        ScheduleGrid {
            GeometryReader { geo in
                ForEach(cards) { scheduleItem in
                    cardContent(scheduleItem)
                        .id(scheduleItem.id)
                        .zIndex(0)
                        .placement(frame(for: scheduleItem, in: geo.size))
                }
            }
        }
    }
    
    func frame(for timelineCard: Element, in size: CGSize) -> CGRect {
        let frame = timelineCard.frame(in: size, groupMapping: self.groupMapping, dayStartsAtNoon: self.dayStartsAtNoon)
        return frame
    }
}
//
//extension SchedulePageView {
//    public init<T>(
//        _ cards: T,
//        @ViewBuilder cardContent: @escaping (T.Element) -> CardContent
//    )
//    where T: RandomAccessCollection,
//        ListType == Array<TimelineWrapper<T.Element>>,
//        T.Element: DateIntervalRepresentable & Equatable & Identifiable
//    {
//        self.init(cards.groupedToPreventOverlaps, cardContent: { cardContent($0.item) })
//    }
//
//    public init<T>(
//        _ cards: T,
//        groupedBy: KeyPath<T.Element, some Equatable>,
//        @ViewBuilder cardContent: @escaping (T.Element) -> CardContent
//    )
//    where T: RandomAccessCollection,
//        ListType == Array<TimelineWrapper<T.Element>>,
//        T.Element: DateIntervalRepresentable & Equatable & Identifiable
//    {
//        self.init(cards.groupedToPreventOverlaps, cardContent: { cardContent($0.item) })
//    }
//
//}



public extension TimelineCard {
    func xOrigin(containerWidth: CGFloat, groupMapping: [Int:Int]) -> CGFloat {
        guard groupMapping.count > 1 else { return 0 }
        return containerWidth / CGFloat(groupMapping.count) * CGFloat(groupMapping[groupWidth.lowerBound] ?? 0)
    }
    
    /// Get the y placement for a set in a container of a specific height
    func yOrigin(containerHeight: CGFloat, dayStartsAtNoon: Bool) -> CGFloat {
        return dateInterval.start.toY(containerHeight: containerHeight, dayStartsAtNoon: dayStartsAtNoon)
    }
    /// Get the frame size for an artistSet in a specfic container
    func size(in containerSize: CGSize, groupMapping: [Int:Int]) -> CGSize {
        return CGSize(width: width(in: containerSize, groupMapping: groupMapping), height: height(in: containerSize))
    }
    
    func height(in containerSize: CGSize) -> CGFloat {
        let setLengthInSeconds = dateInterval.duration
        return secondsToY(Int(setLengthInSeconds), containerHeight: containerSize.height)
    }
    
    func width(in containerSize: CGSize, groupMapping: [Int:Int]) -> CGFloat {
        let width: CGFloat
        if groupMapping.count <= 1 {
            width = containerSize.width / CGFloat(groupMapping.count)
        } else {
            let groupSpanCount: Int
            groupSpanCount = (groupMapping[groupWidth.upperBound] ?? 0) - (groupMapping[groupWidth.lowerBound] ?? 0) + 1
            width = (containerSize.width / CGFloat(groupMapping.count)) * CGFloat(groupSpanCount)
        }
        return width
    }
    
    func frame(in containerSize: CGSize, groupMapping: [Int:Int], dayStartsAtNoon: Bool) -> CGRect {
        return CGRect(
            origin: CGPoint(
                x: xOrigin(containerWidth: containerSize.width, groupMapping: groupMapping),
                y: yOrigin(containerHeight: containerSize.height, dayStartsAtNoon: dayStartsAtNoon)
            ),
            size: size(in: containerSize, groupMapping: groupMapping))
    }
}

//public extension CGFloat {
//    func toTimeOfDay(containerHeight: CGFloat, on day: CalendarDate) -> Duration {
//        return .seconds((containerHeight / self) * 86400)
//    }
//    
//    func toSeconds(inDaySize dayHeight: CGFloat) -> Int {
//        return Int((dayHeight / self) * 86400)
//    }
//}

public extension View {
    func placement(_ frame: CGRect) -> some View {
        self
            .frame(width: frame.width, height: frame.height)
            .position(frame.offsetBy(dx: frame.size.width / 2, dy: frame.size.height / 2).origin)
    }
}


extension Range where Bound == Date {
    var lengthInSeconds: Double {
        return upperBound.timeIntervalSince(lowerBound)
    }
}


struct HorizontalPageView<Content: View, ID: Hashable>: View {

    var content: Content
    @Binding var page: ID?

    init(page: Binding<ID?>, @ViewBuilder content: () -> Content) {
        self.content = content()
        self._page = page
    }

    var body: some View {
        #if os(iOS)
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                content
                #if os(iOS)
                    .containerRelativeFrame(.horizontal)
                #endif
            }
        }
        .scrollTargetLayout()
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $page)
        .scrollIndicators(.never, axes: .horizontal)
        #elseif os(Android)
        TabView(selection: $page) {
            content
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        #endif
    }
}
//
//#Preview {
//    @Previewable @State var scrollID: Performance.ID? = 0
//    ScrollView {
//        HorizontalPageView(page: $scrollID) {
//
//            ForEach(0..<5) { page in
//                SchedulePageView(
//                    Event.testival.schedule.first!.stageSchedules.values.first!,
//                    cardContent: { performance in
//                        ScheduleCardView(performance, isSelected: false, isFavorite: false)
//                            .id(performance.id)
//                    }
//                )
//                .id(page)
//                .frame(height: 1000)
//                //                    .frame(maxWidth: .infinity)
//            }
//        }
//        .scrollClipDisabled()
//        .environment(\.dayStartsAtNoon, true)
//    }
//    .scrollPosition(id: $scrollID)
//    .overlay {
//        Text("\(scrollID)").font(.title)
//    }
//}
//
//#Preview {
//    @Previewable @State var scrollID: Performance.ID? = 0
//    ScrollView {
//        SchedulePageView(
//            Event.testival.schedule.first!.stageSchedules.values.first!,
//            cardContent: { performance in
//                ScheduleCardView(performance, isSelected: false, isFavorite: false)
//                    .id(performance.id)
//            }
//        )
//        .frame(height: 1000)
//        .environment(\.dayStartsAtNoon, true)
//    }
//    .scrollPosition(id: $scrollID, anchor: .center)
//    .overlay {
//        VStack {
//
//            Text("\(scrollID)").font(.title)
//            Button("Scroll") {
//                withAnimation {
//                    
//                    scrollID = .init(integerLiteral: 0)
//                }
//            }
//        }
//    }
//}
