import Foundation
import ScheduleComponents
import Testing

private struct TestTimelineCard: DateIntervalRepresentable, Equatable, Identifiable {
    let id: Int
    let dateInterval: DateInterval
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
}
