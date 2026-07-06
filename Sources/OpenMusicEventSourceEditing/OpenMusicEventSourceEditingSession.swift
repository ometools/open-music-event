import Dependencies
import Foundation
import OpenMusicEventLexicon
import SQLiteData
import SourceEditing

public enum OpenMusicEventEditResetError: Error, Equatable, Sendable {
    case workspaceNeedsPreparation(OME.Event.ID)
    case notInWorkspace(OME.Event.ID)
    case unconfigured
}

public struct OpenMusicEventEditResetter: Sendable {
    public var reset: @Sendable (OME.Event.ID) throws -> Void

    public init(reset: @escaping @Sendable (OME.Event.ID) throws -> Void) {
        self.reset = reset
    }
}

public extension OpenMusicEventEditResetter {
    static var openMusicEvent: Self {
        OpenMusicEventEditResetter { eventID in
            @Dependency(\.defaultDatabase) var database
            @Dependency(\.workspaceReferenceDatabase) var workspaceReferenceDatabase
            @Dependency(\.sourceEditingSession) var sourceEditingSession

            try database.write { db in
                guard let eventWorkspace = try (EventEditingWorkspaceRecord
                    .where { $0.id.eq(eventID) }
                    .fetchOne(db))
                else {
                    throw OpenMusicEventEditResetError.notInWorkspace(eventID)
                }

                guard let workspace = try (EditingWorkspaceRecord
                    .where { $0.id.eq(eventWorkspace.workspaceID) }
                    .fetchOne(db))
                else {
                    throw OpenMusicEventEditResetError.workspaceNeedsPreparation(eventID)
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
                        throw OpenMusicEventEditResetError.workspaceNeedsPreparation(eventID)
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
    var openMusicEventEditResetter: OpenMusicEventEditResetter {
        get { self[OpenMusicEventEditResetterKey.self] }
        set { self[OpenMusicEventEditResetterKey.self] = newValue }
    }
}

private enum OpenMusicEventEditResetterKey: DependencyKey {
    static var liveValue: OpenMusicEventEditResetter {
        .openMusicEvent
    }

    static var testValue: OpenMusicEventEditResetter {
        OpenMusicEventEditResetter { _ in
            throw OpenMusicEventEditResetError.unconfigured
        }
    }
}
