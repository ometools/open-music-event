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
    public var resetEvent: @Sendable (OME.Event.ID) throws -> Void
    public var resetWorkspace: @Sendable (SourceWorkspace) throws -> Void

    public init(
        resetEvent: @escaping @Sendable (OME.Event.ID) throws -> Void,
        resetWorkspace: @escaping @Sendable (SourceWorkspace) throws -> Void
    ) {
        self.resetEvent = resetEvent
        self.resetWorkspace = resetWorkspace
    }
}

public extension EventWorkspaceResetter {
    static var openMusicEvent: Self {
        Self(
            resetEvent: { eventID in
                @Dependency(\.defaultDatabase) var database
                try database.write { db in
                    guard let workspace = try EventSourceProvenanceRecord
                        .find(eventID)
                        .fetchOne(db)?
                        .workspace
                    else { throw EventWorkspaceResetError.unconfigured }
                    guard let baseline = try SourceEditingSession
                        .attachedBaselineSchemaName(in: db)
                    else {
                        throw EventWorkspaceResetError.workspaceNeedsPreparation(workspace.id)
                    }
                    for projection in OME.sourceEventProjections {
                        try SourceEditingResetter().reset(
                            in: db,
                            baselineSchemaName: baseline,
                            descriptors: [projection.recordType.descriptor],
                            scope: .openMusicEvent(eventID: eventID)
                        )
                    }
                }
            },
            resetWorkspace: { workspace in
                @Dependency(\.defaultDatabase) var database
                try database.write { db in
                    guard let baseline = try SourceEditingSession
                        .attachedBaselineSchemaName(in: db)
                    else {
                        throw EventWorkspaceResetError.workspaceNeedsPreparation(workspace.id)
                    }
                    for projection in OME.sourceProjections {
                        try SourceEditingResetter().reset(
                            in: db,
                            baselineSchemaName: baseline,
                            descriptors: [projection.recordType.descriptor],
                            scope: sourceScope(for: projection, workspace: workspace)
                        )
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
