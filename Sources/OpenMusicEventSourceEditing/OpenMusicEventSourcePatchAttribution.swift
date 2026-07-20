import Foundation
import GRDB
import OpenMusicEventLexicon
import SourceEditing

public func openMusicEventSourcePatchAttributions(
    patch: SourcePatch,
    groups: [SourceChangeGroup],
    recordComparisons: SourceRecordComparisons,
    in db: Database
) throws -> [SourcePatchAttribution] {
    let patchPaths = Set(patch.fileChanges.map(\.path))
    guard !patchPaths.isEmpty else { return [] }

    let records = groups.flatMap(\.records)
    var recordIDsByPath: [String: Set<SourceRecordChange.ID>] = [:]
    var eventDirectoriesByID: [OME.Event.ID: String] = [:]

    for record in records {
        let paths = try openMusicEventSourcePatchPaths(
            for: record,
            patchPaths: patchPaths,
            recordComparisons: recordComparisons,
            eventDirectoriesByID: &eventDirectoriesByID,
            in: db
        )
        for path in paths where patchPaths.contains(path) {
            recordIDsByPath[path, default: []].insert(record.id)
        }
    }

    return patch.fileChanges.compactMap { fileChange in
        guard let recordIDs = recordIDsByPath[fileChange.path],
              !recordIDs.isEmpty
        else { return nil }

        return SourcePatchAttribution(
            filePath: fileChange.path,
            recordChangeIDs: recordIDs.sorted()
        )
    }
}

private func openMusicEventSourcePatchPaths(
    for record: SourceRecordChange,
    patchPaths: Set<String>,
    recordComparisons: SourceRecordComparisons,
    eventDirectoriesByID: inout [OME.Event.ID: String],
    in db: Database
) throws -> [String] {
    switch record.tableID {
    case OME.Calendar.tableName:
        return ["calendar.yml"]

    case OME.Event.tableName:
        guard let event = comparedRecord(
            for: record,
            as: OME.Event.self,
            in: recordComparisons
        ) else { return [] }
        return try eventSourcePath(
            eventID: event.id,
            filePath: "event.yml",
            eventDirectoriesByID: &eventDirectoriesByID,
            in: db
        )

    case OME.Stage.tableName:
        guard let stage = comparedRecord(
            for: record,
            as: OME.Stage.self,
            in: recordComparisons
        ) else { return [] }
        return try eventSourcePath(
            eventID: OME.Event.ID(
                organizerID: stage.id.organizerID,
                eventID: stage.id.eventID
            ),
            filePath: "stages/\(stage.id.stageID.rawValue.rawValue).yml",
            eventDirectoriesByID: &eventDirectoriesByID,
            in: db
        )

    case OME.Contributor.tableName:
        guard let contributor = comparedRecord(
            for: record,
            as: OME.Contributor.self,
            in: recordComparisons
        ) else { return [] }
        return try eventSourcePath(
            eventID: OME.Event.ID(
                organizerID: contributor.id.organizerID,
                eventID: contributor.id.eventID
            ),
            filePath: "contributors/\(contributor.id.contributorID.rawValue.rawValue).md",
            eventDirectoriesByID: &eventDirectoriesByID,
            in: db
        )

    case OME.Poster.tableName:
        guard let poster = comparedRecord(
            for: record,
            as: OME.Poster.self,
            in: recordComparisons
        ) else { return [] }
        return try eventSourcePath(
            eventID: OME.Event.ID(
                organizerID: poster.id.organizerID,
                eventID: poster.id.eventID
            ),
            filePath: "posters/\(poster.id.posterID.rawValue.rawValue).yml",
            eventDirectoriesByID: &eventDirectoriesByID,
            in: db
        )

    case OME.Schedule.tableName:
        guard let schedule = comparedRecord(
            for: record,
            as: OME.Schedule.self,
            in: recordComparisons
        ) else { return [] }
        let eventID = OME.Event.ID(
            organizerID: schedule.id.organizerID,
            eventID: schedule.id.eventID
        )
        let scheduleFilePath = "schedules/\(schedule.id.scheduleID.rawValue.rawValue).yml"
        return try eventScheduleSourcePaths(
            eventID: eventID,
            scheduleFilePath: scheduleFilePath,
            patchPaths: patchPaths,
            eventDirectoriesByID: &eventDirectoriesByID,
            in: db
        )

    case OME.Performance.tableName:
        guard let performance = comparedRecord(
            for: record,
            as: OME.Performance.self,
            in: recordComparisons
        ),
              let scheduleID = performance.scheduleID
        else { return [] }
        let eventID = OME.Event.ID(
            organizerID: performance.id.organizerID,
            eventID: performance.id.eventID
        )
        let scheduleFilePath = "schedules/\(scheduleID.rawValue.rawValue).yml"
        return try eventScheduleSourcePaths(
            eventID: eventID,
            scheduleFilePath: scheduleFilePath,
            patchPaths: patchPaths,
            eventDirectoriesByID: &eventDirectoriesByID,
            in: db
        )

    case OME.Channel.tableName:
        guard let channel = comparedRecord(
            for: record,
            as: OME.Channel.self,
            in: recordComparisons
        ) else { return [] }
        return try eventSourcePath(
            eventID: OME.Event.ID(
                organizerID: channel.id.organizerID,
                eventID: channel.id.eventID
            ),
            filePath: "channels/\(channel.id.channelID.rawValue.rawValue).yml",
            eventDirectoriesByID: &eventDirectoriesByID,
            in: db
        )

    default:
        return []
    }
}

private func eventScheduleSourcePaths(
    eventID: OME.Event.ID,
    scheduleFilePath: String,
    patchPaths: Set<String>,
    eventDirectoriesByID: inout [OME.Event.ID: String],
    in db: Database
) throws -> [String] {
    let eventPath = try eventSourcePath(
        eventID: eventID,
        filePath: "event.yml",
        eventDirectoriesByID: &eventDirectoriesByID,
        in: db
    )
    let schedulePath = try eventSourcePath(
        eventID: eventID,
        filePath: scheduleFilePath,
        eventDirectoriesByID: &eventDirectoriesByID,
        in: db
    )
    if schedulePath.contains(where: patchPaths.contains) {
        return schedulePath
    }
    if eventPath.contains(where: patchPaths.contains) {
        return eventPath
    }
    return schedulePath
}

private func eventSourcePath(
    eventID: OME.Event.ID,
    filePath: String,
    eventDirectoriesByID: inout [OME.Event.ID: String],
    in db: Database
) throws -> [String] {
    guard let eventDirectory = try eventSourceDirectory(
        eventID: eventID,
        eventDirectoriesByID: &eventDirectoriesByID,
        in: db
    ) else { return [] }
    return ["events/\(eventDirectory)/\(filePath)"]
}

private func eventSourceDirectory(
    eventID: OME.Event.ID,
    eventDirectoriesByID: inout [OME.Event.ID: String],
    in db: Database
) throws -> String? {
    if let directory = eventDirectoriesByID[eventID] {
        return directory
    }

    let directory = try EventSourceProvenanceRecord
        .where { $0.id.eq(eventID) }
        .fetchOne(db)?
        .sourceEventDirectory
    eventDirectoriesByID[eventID] = directory
    return directory
}

private func comparedRecord<Record: Sendable>(
    for record: SourceRecordChange,
    as recordType: Record.Type,
    in recordComparisons: SourceRecordComparisons
) -> Record? {
    guard let comparison = recordComparisons[record]?.as(recordType) else {
        return nil
    }
    return comparison.right ?? comparison.left
}
