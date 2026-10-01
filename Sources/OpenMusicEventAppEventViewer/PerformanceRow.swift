import OpenMusicEventLexicon
import SQLiteData

@Selection
public struct PerformanceRow: Identifiable, Sendable {
    public let performance: ProgramItem
    public let stage: EventPlace?

    public var id: ProgramItem.ID { performance.id }
    public var performanceID: ProgramItem.ID { performance.id }
    public var title: String { performance.title }
}

extension PerformanceRow {
    public static func all(
        eventID: Event.ID
    ) -> some Statement<PerformanceRow> {
        ProgramItem
            .where { $0.event.eq(eventID) }
            .leftJoin(EventPlace.all) { item, place in
                item.eventPlace.eq(place.id)
                    .and(place.event.eq(eventID))
            }
            .order { item, _ in
                (item.startsAt.asc(nulls: .last), item.title.collate(.nocase))
            }
            .select { item, place -> PerformanceRow.Columns in
                PerformanceRow.Columns(performance: item, stage: place)
            }
    }

    public static func all(
        eventID: Event.ID,
        scheduleID: Schedule.ID
    ) -> some Statement<PerformanceRow> {
        ProgramItem
            .where { $0.event.eq(eventID) }
            .where { $0.schedule.eq(scheduleID) }
            .leftJoin(EventPlace.all) { item, place in
                item.eventPlace.eq(place.id)
                    .and(place.event.eq(eventID))
            }
            .order { item, _ in
                (item.startsAt.asc(nulls: .last), item.title.collate(.nocase))
            }
            .select { item, place -> PerformanceRow.Columns in
                PerformanceRow.Columns(performance: item, stage: place)
            }
    }

    public static func forContributor(
        contributorID: Contributor.ID,
        eventID: Event.ID
    ) -> some Statement<PerformanceRow> {
        let itemTable = ProgramItem.tableName
        return ProgramItem
            .where { $0.event.eq(eventID) }
            .where { _ in
                #sql(
                    """
                    EXISTS (
                      SELECT 1
                      FROM json_each(\(quote: itemTable)."credits") AS "credit"
                      WHERE json_extract("credit"."value", '$.contributor') = \(contributorID.description)
                    )
                    """,
                    as: Bool.self
                )
            }
            .leftJoin(EventPlace.all) { item, place in
                item.eventPlace.eq(place.id)
                    .and(place.event.eq(eventID))
            }
            .order { item, _ in
                (item.startsAt.asc(nulls: .last), item.title.collate(.nocase))
            }
            .select { item, place -> PerformanceRow.Columns in
                PerformanceRow.Columns(performance: item, stage: place)
            }
    }
}
