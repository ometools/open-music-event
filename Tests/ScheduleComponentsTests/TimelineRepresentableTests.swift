import CoreGraphics
import Foundation
import ScheduleComponents
import Testing

private struct TestTimelineCard: TimelineCard {
    let id: Int
    let dateInterval: DateInterval
    var groupWidth: Range<Int> = 0..<0
}

struct TimelineRepresentableTests {
    @Test
    func groupedToPreventOverlapsSeparatesOverlappingCards() throws {
        let baseDate = Date(timeIntervalSinceReferenceDate: 0)
        let cards = [
            TestTimelineCard(
                id: 1,
                dateInterval: DateInterval(start: baseDate, duration: 60.minutes)
            ),
            TestTimelineCard(
                id: 2,
                dateInterval: DateInterval(start: baseDate.addingTimeInterval(30.minutes), duration: 60.minutes)
            ),
            TestTimelineCard(
                id: 3,
                dateInterval: DateInterval(start: baseDate.addingTimeInterval(90.minutes), duration: 30.minutes)
            ),
        ]

        let grouped = cards.groupedToPreventOverlaps
        let groupWidthsByID = Dictionary(uniqueKeysWithValues: grouped.map { ($0.id, $0.groupWidth) })

        #expect(groupWidthsByID[1]?.lowerBound == 0)
        #expect(groupWidthsByID[2]?.lowerBound == 1)
        #expect(groupWidthsByID[3] == 0..<1)
    }

    @Test
    func verticalTimeFrameMapsTimeToYAndGroupsToX() {
        let baseDate = Date(timeIntervalSinceReferenceDate: 0)
        let card = TestTimelineCard(
            id: 1,
            dateInterval: DateInterval(
                start: baseDate.addingTimeInterval(60.minutes),
                duration: 120.minutes
            ),
            groupWidth: 1..<1
        )
        let frame = card.frame(
            in: CGSize(width: 300, height: 400),
            groupMapping: [0: 0, 1: 1, 2: 2],
            range: DateInterval(start: baseDate, duration: 240.minutes),
            orientation: .verticalTime
        )

        #expect(frame.origin.x == 100)
        #expect(frame.origin.y == 100)
        #expect(frame.width == 100)
        #expect(frame.height == 200)
    }

    @Test
    func horizontalTimeFrameMapsTimeToXAndGroupsToY() {
        let baseDate = Date(timeIntervalSinceReferenceDate: 0)
        let card = TestTimelineCard(
            id: 1,
            dateInterval: DateInterval(
                start: baseDate.addingTimeInterval(60.minutes),
                duration: 120.minutes
            ),
            groupWidth: 1..<1
        )
        let frame = card.frame(
            in: CGSize(width: 400, height: 300),
            groupMapping: [0: 0, 1: 1, 2: 2],
            range: DateInterval(start: baseDate, duration: 240.minutes),
            orientation: .horizontalTime
        )

        #expect(frame.origin.x == 100)
        #expect(frame.origin.y == 100)
        #expect(frame.width == 200)
        #expect(frame.height == 100)
    }
}
