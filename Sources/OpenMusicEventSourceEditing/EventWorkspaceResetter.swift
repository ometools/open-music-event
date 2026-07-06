import Dependencies
import Foundation
import OpenMusicEventLexicon
import SQLiteData
import SourceEditing

public enum EventWorkspaceResetError: Error, Equatable, Sendable {
    case workspaceNeedsPreparation(OME.Event.ID)
    case notInWorkspace(OME.Event.ID)
    case unconfigured
}

public struct EventWorkspaceResetter: Sendable {
    public var reset: @Sendable (OME.Event.ID) throws -> Void

    public init(reset: @escaping @Sendable (OME.Event.ID) throws -> Void) {
        self.reset = reset
    }
}

public extension EventWorkspaceResetter {
    static var openMusicEvent: Self {
        EventWorkspaceResetter { eventID in
            @Dependency(\.defaultDatabase) var database
            @Dependency(\.workspaceReferenceDatabase) var workspaceReferenceDatabase
            @Dependency(\.sourceEditingSession) var sourceEditingSession

            try database.write { db in
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
                    try SourceEditingResetter().reset(
                        in: db,
                        baselineSchemaName: sourceEditingSession.baselineSchemaName,
                        descriptors: OME.sourceTableDescriptors,
                        scope: .openMusicEvent(eventID: eventID)
                    )
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
        }
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
