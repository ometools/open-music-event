import Dependencies
import Foundation
import GRDB
import OpenMusicEventLexicon
import SQLiteData
import SourceEditing

public enum EventWorkspaceResetError: Error, Equatable, Sendable {
    case sourceBaselineNotFound(SourceBaselineRecord.ID)
    case sourceWorkspaceNeedsPreparation(SourceBaselineRecord.ID)
    case workspaceNeedsPreparation(OME.Event.ID)
    case notInWorkspace(OME.Event.ID)
    case unconfigured
}

public struct EventWorkspaceResetter: Sendable {
    public var reset: @Sendable (OME.Event.ID) throws -> Void
    public var resetSourceChanges: @Sendable (OpenMusicEventSourceTarget) throws -> Void

    public init(
        reset: @escaping @Sendable (OME.Event.ID) throws -> Void,
        resetSourceChanges: (@Sendable (OpenMusicEventSourceTarget) throws -> Void)? = nil
    ) {
        self.reset = reset
        self.resetSourceChanges = resetSourceChanges ?? { target in
            guard case let .event(eventID) = target else {
                throw EventWorkspaceResetError.unconfigured
            }
            try reset(eventID)
        }
    }
}

public extension EventWorkspaceResetter {
    static var openMusicEvent: Self {
        EventWorkspaceResetter(
            reset: { eventID in
                try resetOpenMusicEvent(eventID: eventID)
            },
            resetSourceChanges: { target in
                try resetOpenMusicEventSourceChanges(target: target)
            }
        )
    }
}

private func resetOpenMusicEvent(eventID: OME.Event.ID) throws {
    @Dependency(\.defaultDatabase) var database

    try database.write { db in
        try resetOpenMusicEvent(eventID: eventID, in: db)
    }
}

private func resetOpenMusicEventSourceChanges(
    target: OpenMusicEventSourceTarget
) throws {
    @Dependency(\.defaultDatabase) var database

    try database.write { db in
        switch target {
        case let .calendar(calendarID, sourceBaselineID):
            try resetOpenMusicEventSourceChanges(
                sourceBaselineID: sourceBaselineID,
                calendarID: calendarID,
                in: db
            )

        case let .event(eventID):
            let sourceBaselineID = try EventSourceProvenanceRecord
                .where { $0.id.eq(eventID) }
                .fetchOne(db)?
                .sourceBaselineID
            if let sourceBaselineID {
                try resetOpenMusicEventSourceChanges(
                    sourceBaselineID: sourceBaselineID,
                    calendarID: OME.Calendar.ID(
                        ownerID: eventID.organizerID,
                        calendarID: OME.Calendar.defaultID
                    ),
                    in: db
                )
            } else {
                try resetOpenMusicEvent(eventID: eventID, in: db)
            }
        }
    }
}

private func resetOpenMusicEvent(
    eventID: OME.Event.ID,
    in db: Database
) throws {
    guard let eventWorkspace = try (EventEditingWorkspaceRecord
        .where { $0.id.eq(eventID) }
        .fetchOne(db))
    else {
        throw EventWorkspaceResetError.notInWorkspace(eventID)
    }

    guard try (
        EditingWorkspaceRecord
            .where { $0.id.eq(eventWorkspace.workspaceID) }
            .fetchCount(db)
    ) == 1 else {
        throw EventWorkspaceResetError.workspaceNeedsPreparation(eventID)
    }
    guard let baselineSchemaName = try SourceEditingSession
        .attachedBaselineSchemaName(in: db)
    else {
        throw EventWorkspaceResetError.workspaceNeedsPreparation(eventID)
    }
    try SourceEditingResetter().reset(
        in: db,
        baselineSchemaName: baselineSchemaName,
        descriptors: OME.sourceTableDescriptors,
        scope: .openMusicEvent(eventID: eventID)
    )
}

private func resetOpenMusicEventSourceChanges(
    sourceBaselineID: SourceBaselineRecord.ID,
    calendarID: OME.Calendar.ID,
    in db: Database
) throws {
    guard try (
        SourceBaselineRecord
            .where { $0.id.eq(sourceBaselineID) }
            .fetchCount(db)
    ) == 1 else {
        throw EventWorkspaceResetError.sourceBaselineNotFound(sourceBaselineID)
    }

    guard let baselineSchemaName = try SourceEditingSession
        .attachedBaselineSchemaName(in: db)
    else {
        throw EventWorkspaceResetError.sourceWorkspaceNeedsPreparation(sourceBaselineID)
    }
    try resetOpenMusicEventSourceChanges(
        sourceBaselineID: sourceBaselineID,
        calendarID: calendarID,
        in: db,
        baselineSchemaName: baselineSchemaName
    )
}

private func resetOpenMusicEventSourceChanges(
    sourceBaselineID: SourceBaselineRecord.ID,
    calendarID: OME.Calendar.ID,
    in db: Database,
    baselineSchemaName: String
) throws {
    try SourceEditingResetter().reset(
        in: db,
        baselineSchemaName: baselineSchemaName,
        descriptors: OME.sourceMetadataProjections
            .filter { $0.fileFamily == .calendar }
            .map(\.recordType.descriptor),
        scope: .openMusicEventCalendar(calendarID: calendarID)
    )

    try SourceEditingResetter().reset(
        in: db,
        baselineSchemaName: baselineSchemaName,
        descriptors: OME.sourceMetadataProjections
            .filter { $0.fileFamily == .collaborator }
            .map(\.recordType.descriptor),
        scope: .openMusicEventWorkspace(
            EditingWorkspaceRecord.ID(sourceBaselineID: sourceBaselineID)
        )
    )

    for eventID in try openMusicEventSourceEventIDs(
        in: db,
        baselineSchemaName: baselineSchemaName,
        sourceBaselineID: sourceBaselineID,
        organizerID: calendarID.ownerID
    ) {
        try SourceEditingResetter().reset(
            in: db,
            baselineSchemaName: baselineSchemaName,
            descriptors: OME.sourceTableDescriptors,
            scope: .openMusicEvent(eventID: eventID)
        )
    }
}

public extension SourceRecordScope {
    static func openMusicEvent(eventID: OME.Event.ID) -> Self {
        SourceRecordScope(
            filters: [
                SourceRecordScope.Filter(
                    columnName: "organizerID",
                    value: eventID.organizerID.queryBinding
                ),
                SourceRecordScope.Filter(
                    columnName: "eventID",
                    value: eventID.eventID.rawValue.rawValue.queryBinding
                ),
            ]
        )
    }
}

public extension DependencyValues {
    var eventWorkspaceResetter: EventWorkspaceResetter {
        get { self[EventWorkspaceResetterKey.self] }
        set { self[EventWorkspaceResetterKey.self] = newValue }
    }
}

private enum EventWorkspaceResetterKey: DependencyKey {
    static var liveValue: EventWorkspaceResetter {
        .openMusicEvent
    }

    static var testValue: EventWorkspaceResetter {
        EventWorkspaceResetter { _ in
            throw EventWorkspaceResetError.unconfigured
        }
    }
}
