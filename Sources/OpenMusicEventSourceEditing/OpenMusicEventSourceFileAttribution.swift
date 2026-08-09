import Foundation
import GRDB
import OpenMusicEventLexicon
import SourceEditing

public func openMusicEventSourceFileAttributions(
    patch: SourcePatch,
    groups: [SourceChangeGroup],
    recordComparisons: SourceRecordComparisons,
    in db: Database
) throws -> [SourceFileAttribution] {
    let patchPaths = Set(patch.fileChanges.map(\.path))
    guard !patchPaths.isEmpty else { return [] }

    let recordIDsByPath = try openMusicEventSourceRecordIDsByFilePath(
        groups: groups,
        includedFilePaths: patchPaths,
        recordComparisons: recordComparisons,
        in: db
    )

    return patch.fileChanges.compactMap { fileChange in
        guard let recordIDs = recordIDsByPath[fileChange.path],
              !recordIDs.isEmpty
        else { return nil }

        return SourceFileAttribution(
            filePath: fileChange.path,
            recordChangeIDs: recordIDs.sorted()
        )
    }
}

public func openMusicEventSourceFileAttributions(
    groups: [SourceChangeGroup],
    recordComparisons: SourceRecordComparisons,
    in db: Database
) throws -> [SourceFileAttribution] {
    try openMusicEventSourceRecordIDsByFilePath(
        groups: groups,
        includedFilePaths: nil,
        recordComparisons: recordComparisons,
        in: db
    )
    .map { filePath, recordIDs in
        SourceFileAttribution(
            filePath: filePath,
            recordChangeIDs: recordIDs.sorted()
        )
    }
    .sorted { $0.filePath < $1.filePath }
}

private func openMusicEventSourceRecordIDsByFilePath(
    groups: [SourceChangeGroup],
    includedFilePaths: Set<String>?,
    recordComparisons: SourceRecordComparisons,
    in db: Database
) throws -> [String: Set<SourceRecordChange.ID>] {
    let records = groups.flatMap(\.records)
    var recordIDsByPath: [String: Set<SourceRecordChange.ID>] = [:]
    var eventDirectoriesByID: [OME.Event.ID: String] = [:]

    for record in records {
        let paths = try openMusicEventSourceFilePaths(
            for: record,
            includedFilePaths: includedFilePaths,
            recordComparisons: recordComparisons,
            eventDirectoriesByID: &eventDirectoriesByID,
            in: db
        )
        for path in paths where includedFilePaths?.contains(path) ?? true {
            recordIDsByPath[path, default: []].insert(record.id)
        }
    }

    return recordIDsByPath
}

private func openMusicEventSourceFilePaths(
    for record: SourceRecordChange,
    includedFilePaths: Set<String>?,
    recordComparisons: SourceRecordComparisons,
    eventDirectoriesByID: inout [OME.Event.ID: String],
    in db: Database
) throws -> [String] {
    guard let projection = OME.sourceProjectionsByTableID[record.tableID] else {
        return []
    }

    switch projection.fileFamily {
    case .calendar:
        return ["calendar.yml"]

    case .collaborator:
        guard let collaborator = comparedRecord(
            for: record,
            as: WorkspaceRelationshipRecord.self,
            in: recordComparisons
        ) else { return [] }
        return ["collaborators/\(collaborator.recordKey).yml"]

    case .event:
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

    case .stage:
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

    case .contributor:
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

    case .poster:
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

    case .schedule where record.tableID == OME.Schedule.tableName:
        guard let schedule = comparedRecord(
            for: record,
            as: OME.Schedule.self,
            in: recordComparisons
        ) else { return [] }
        let eventID = OME.Event.ID(
            organizerID: schedule.id.organizerID,
            eventID: schedule.id.eventID
        )
        return try eventScheduleSourcePaths(
            eventID: eventID,
            scheduleID: schedule.id.scheduleID,
            includedFilePaths: includedFilePaths,
            eventDirectoriesByID: &eventDirectoriesByID,
            in: db
        )

    case .schedule where record.tableID == OME.Performance.tableName:
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
        return try eventScheduleSourcePaths(
            eventID: eventID,
            scheduleID: scheduleID,
            includedFilePaths: includedFilePaths,
            eventDirectoriesByID: &eventDirectoriesByID,
            in: db
        )

    case .channel:
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

    case .communicationPost:
        guard let post = comparedRecord(
            for: record,
            as: CommsPost.self,
            in: recordComparisons
        ) else { return [] }
        return try eventSourcePath(
            eventID: OME.Event.ID(
                organizerID: post.id.organizerID,
                eventID: post.id.eventID
            ),
            filePath: "communications/\(post.id.channelID.rawValue.rawValue)/\(post.id.postID.rawValue).md",
            eventDirectoriesByID: &eventDirectoriesByID,
            in: db
        )

    default:
        return []
    }
}

private func eventScheduleSourcePaths(
    eventID: OME.Event.ID,
    scheduleID: OME.ID<OME.Schedule>,
    includedFilePaths: Set<String>?,
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
        filePath: "schedules/\(scheduleID.rawValue.rawValue).yml",
        eventDirectoriesByID: &eventDirectoriesByID,
        in: db
    )

    if let includedFilePaths {
        if schedulePath.contains(where: includedFilePaths.contains) {
            return schedulePath
        }
        if eventPath.contains(where: includedFilePaths.contains) {
            return eventPath
        }
    }

    return scheduleID == OME.Schedule.singletonID ? eventPath : schedulePath
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
