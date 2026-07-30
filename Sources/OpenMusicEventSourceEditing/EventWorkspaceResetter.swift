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
    @Dependency(\.workspaceReferenceDatabase) var workspaceReferenceDatabase
    @Dependency(\.sourceEditingSession) var sourceEditingSession

    try database.write { db in
        try resetOpenMusicEvent(
            eventID: eventID,
            in: db,
            workspaceReferenceDatabase: workspaceReferenceDatabase,
            sourceEditingSession: sourceEditingSession
        )
    }
}

private func resetOpenMusicEventSourceChanges(
    target: OpenMusicEventSourceTarget
) throws {
    @Dependency(\.defaultDatabase) var database
    @Dependency(\.sourceEditingSession) var sourceEditingSession
    @Dependency(\.sourceReferenceDatabase) var sourceReferenceDatabase
    @Dependency(\.workspaceReferenceDatabase) var workspaceReferenceDatabase

    try database.write { db in
        switch target {
        case let .calendar(calendarID, sourceBaselineID):
            try resetOpenMusicEventSourceChanges(
                sourceBaselineID: sourceBaselineID,
                calendarID: calendarID,
                in: db,
                sourceEditingSession: sourceEditingSession,
                sourceReferenceDatabase: sourceReferenceDatabase
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
                    in: db,
                    sourceEditingSession: sourceEditingSession,
                    sourceReferenceDatabase: sourceReferenceDatabase
                )
            } else {
                try resetOpenMusicEvent(
                    eventID: eventID,
                    in: db,
                    workspaceReferenceDatabase: workspaceReferenceDatabase,
                    sourceEditingSession: sourceEditingSession
                )
            }
        }
    }
}

private func resetOpenMusicEvent(
    eventID: OME.Event.ID,
    in db: Database,
    workspaceReferenceDatabase: WorkspaceReferenceDatabaseClient,
    sourceEditingSession: SourceEditingSession?
) throws {
    guard let eventWorkspace = try (EventEditingWorkspaceRecord
        .where { $0.id.eq(eventID) }
        .fetchOne(db))
    else {
        throw EventWorkspaceResetError.notInWorkspace(eventID)
    }

    guard let workspace = try (EditingWorkspaceRecord
        .where { $0.id.eq(eventWorkspace.workspaceID) }
        .fetchOne(db))
    else {
        throw EventWorkspaceResetError.workspaceNeedsPreparation(eventID)
    }
    let sourceBaseline = try workspace.sourceBaselineID.flatMap { sourceBaselineID in
        try SourceBaselineRecord
            .where { $0.id.eq(sourceBaselineID) }
            .fetchOne(db)
    }

    if let sourceEditingSession {
        try sourceEditingSession.withAttachedBaseline(to: db) { baselineSchemaName in
            try SourceEditingResetter().reset(
                in: db,
                baselineSchemaName: baselineSchemaName,
                descriptors: OME.sourceTableDescriptors,
                scope: .openMusicEvent(eventID: eventID)
            )
        }
    } else {
        let baselineDatabase: SourceBaselineDatabase?
        do {
            baselineDatabase = try workspaceReferenceDatabase.existing(
                workspace,
                sourceBaseline: sourceBaseline
            )
        } catch WorkspaceReferenceDatabaseError.sourceBaselineMissing(_),
                WorkspaceReferenceDatabaseError.teamWorkspaceMissingSourceBaseline(_) {
            baselineDatabase = nil
        }
        guard let baselineDatabase else {
            throw EventWorkspaceResetError.workspaceNeedsPreparation(eventID)
        }
        try SourceEditingResetter().reset(
            in: db,
            baselineDatabase: baselineDatabase,
            descriptors: OME.sourceTableDescriptors,
            scope: .openMusicEvent(eventID: eventID)
        )
    }
}

private func resetOpenMusicEventSourceChanges(
    sourceBaselineID: SourceBaselineRecord.ID,
    calendarID: OME.Calendar.ID,
    in db: Database,
    sourceEditingSession: SourceEditingSession?,
    sourceReferenceDatabase: SourceReferenceDatabaseClient
) throws {
    guard let sourceBaseline = try (SourceBaselineRecord
        .where { $0.id.eq(sourceBaselineID) }
        .fetchOne(db))
    else {
        throw EventWorkspaceResetError.sourceBaselineNotFound(sourceBaselineID)
    }

    if let sourceEditingSession {
        try sourceEditingSession.withAttachedBaseline(to: db) { baselineSchemaName in
            try resetOpenMusicEventSourceChanges(
                sourceBaselineID: sourceBaselineID,
                calendarID: calendarID,
                in: db,
                baselineSchemaName: baselineSchemaName
            )
        }
    } else {
        guard let baselineDatabase = try sourceReferenceDatabase.existing(
            sourceBaseline.sourceProvenance
        ) else {
            throw EventWorkspaceResetError.sourceWorkspaceNeedsPreparation(sourceBaselineID)
        }
        try resetOpenMusicEventSourceChanges(
            sourceBaselineID: sourceBaselineID,
            calendarID: calendarID,
            in: db,
            baselineDatabase: baselineDatabase
        )
    }
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

private func resetOpenMusicEventSourceChanges(
    sourceBaselineID: SourceBaselineRecord.ID,
    calendarID: OME.Calendar.ID,
    in db: Database,
    baselineDatabase: SourceBaselineDatabase
) throws {
    let baselineSchemaName = "source_baseline_\(UUID().uuidString.replacingOccurrences(of: "-", with: "_"))"

    try #sql(
        "ATTACH DATABASE \(bind: baselineDatabase.path) AS \(quote: baselineSchemaName)"
    )
    .execute(db)
    defer {
        try? #sql("DETACH DATABASE \(quote: baselineSchemaName)").execute(db)
    }

    try resetOpenMusicEventSourceChanges(
        sourceBaselineID: sourceBaselineID,
        calendarID: calendarID,
        in: db,
        baselineSchemaName: baselineSchemaName
    )
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
