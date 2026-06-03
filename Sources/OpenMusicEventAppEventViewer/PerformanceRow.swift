import OpenMusicEventDatabase
import SQLiteData

@Selection
public struct PerformanceRow: Identifiable, Sendable {
    public let performance: OMERecord.Performance
    public let stage: OMERecord.Stage?

    public var id: OMERecord.Performance.ID {
        performance.id
    }

    public var performanceID: OMERecord.ID<OMERecord.Performance> {
        performance.id.performanceID
    }

    public var title: String {
        performance.title
    }
}

extension PerformanceRow {
    public static func all(
        eventID: OMERecord.Event.ID
    ) -> some Statement<PerformanceRow> {
        OMERecord.Performance
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .leftJoin(OMERecord.Stage.all) { performance, stage in
                stage.id.organizerID.eq(eventID.organizerID)
                    .and(stage.id.eventID.eq(eventID.eventID))
                    .and(stage.id.stageID.eq(performance.stageID))
            }
            .order { performance, _ in
                (performance.startTime, performance.title.collate(.nocase))
            }
            .select { performance, stage -> PerformanceRow.Columns in
                PerformanceRow.Columns(
                    performance: performance,
                    stage: stage
                )
            }
    }

    public static func all(
        eventID: OMERecord.Event.ID,
        scheduleID: OMERecord.ID<OMERecord.Schedule>
    ) -> some Statement<PerformanceRow> {
        OMERecord.Performance
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .where { $0.scheduleID.eq(scheduleID) }
            .leftJoin(OMERecord.Stage.all) { performance, stage in
                stage.id.organizerID.eq(eventID.organizerID)
                    .and(stage.id.eventID.eq(eventID.eventID))
                    .and(stage.id.stageID.eq(performance.stageID))
            }
            .order { performance, _ in
                (performance.startTime, performance.title.collate(.nocase))
            }
            .select { performance, stage -> PerformanceRow.Columns in
                PerformanceRow.Columns(
                    performance: performance,
                    stage: stage
                )
            }
    }

    public static func forContributor(
        contributorID: OMERecord.ID<OMERecord.Contributor>,
        eventID: OMERecord.Event.ID
    ) -> some Statement<PerformanceRow> {
        OMERecord.Performance
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .where { performance in
                OMERecord.Performance.Contributors
                    .where { $0.organizerID.eq(eventID.organizerID) }
                    .where { $0.eventID.eq(eventID.eventID) }
                    .where { $0.performanceID.eq(performance.id.performanceID) }
                    .where { $0.contributorID.eq(contributorID) }
                    .exists()
            }
            .leftJoin(OMERecord.Stage.all) { performance, stage in
                stage.id.organizerID.eq(eventID.organizerID)
                    .and(stage.id.eventID.eq(eventID.eventID))
                    .and(stage.id.stageID.eq(performance.stageID))
            }
            .order { performance, _ in
                (performance.startTime, performance.title.collate(.nocase))
            }
            .select { performance, stage -> PerformanceRow.Columns in
                PerformanceRow.Columns(
                    performance: performance,
                    stage: stage
                )
            }
    }
}
