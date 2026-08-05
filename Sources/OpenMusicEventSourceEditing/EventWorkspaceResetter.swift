import Dependencies
import GRDB
import OpenMusicEventLexicon
import SQLiteData
import SourceEditing

public enum EventWorkspaceResetError: Error, Equatable, Sendable {
    case workspaceNeedsPreparation(SourceWorkspace.ID)
    case unconfigured
}

public struct EventWorkspaceResetter: Sendable {
    public var resetEvent: @Sendable (
        OME.Event.ID,
        SourceBaselineDatabase
    ) throws -> Void
    public var resetWorkspace: @Sendable (
        SourceWorkspace,
        SourceBaselineDatabase
    ) throws -> Void

    public init(
        resetEvent: @escaping @Sendable (
            OME.Event.ID,
            SourceBaselineDatabase
        ) throws -> Void,
        resetWorkspace: @escaping @Sendable (
            SourceWorkspace,
            SourceBaselineDatabase
        ) throws -> Void
    ) {
        self.resetEvent = resetEvent
        self.resetWorkspace = resetWorkspace
    }
}

public extension EventWorkspaceResetter {
    static var openMusicEvent: Self {
        Self(
            resetEvent: { eventID, referenceDatabase in
                @Dependency(\.defaultDatabase) var database
                try database.write { db in
                    guard try EventSourceProvenanceRecord
                        .find(eventID)
                        .fetchOne(db)?
                        .workspace != nil
                    else { throw EventWorkspaceResetError.unconfigured }
                    try referenceDatabase.read { baselineDatabase in
                        for projection in OME.sourceEventProjections {
                            try SourceEditingResetter().reset(
                                workingDatabase: db,
                                baselineDatabase: baselineDatabase,
                                descriptors: [projection.recordType.descriptor],
                                scope: .openMusicEvent(eventID: eventID)
                            )
                        }
                    }
                }
            },
            resetWorkspace: { workspace, referenceDatabase in
                @Dependency(\.defaultDatabase) var database
                try database.write { db in
                    try referenceDatabase.read { baselineDatabase in
                        for projection in OME.sourceProjections {
                            try SourceEditingResetter().reset(
                                workingDatabase: db,
                                baselineDatabase: baselineDatabase,
                                descriptors: [projection.recordType.descriptor],
                                scope: sourceScope(for: projection, workspace: workspace)
                            )
                        }
                    }
                }
            }
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
    static var liveValue: EventWorkspaceResetter { .openMusicEvent }
    static var testValue: EventWorkspaceResetter {
        .openMusicEvent
    }
}
