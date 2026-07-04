import Dependencies
import Foundation
import OpenMusicEventLexicon
import SQLiteData
import SourceEditing

public enum OpenMusicEventEditResetError: Error, Equatable, Sendable {
    case missingBaseline(OME.Event.ID)
    case notSourceBacked(OME.Event.ID)
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
            @Dependency(\.sourceReferenceDatabase) var sourceReferenceDatabase

            try database.write { db in
                guard let provenance = try (EventSourceProvenanceRecord
                    .where { $0.id.eq(eventID) }
                    .fetchOne(db))
                else {
                    throw OpenMusicEventEditResetError.notSourceBacked(eventID)
                }
                guard let sourceBaselineID = provenance.sourceBaselineID,
                      try (SourceBaselineRecord
                        .where { $0.id.eq(sourceBaselineID) }
                        .fetchOne(db)) != nil,
                      let baselineDatabase = try sourceReferenceDatabase.existing(
                        provenance.sourceProvenance
                      )
                else {
                    throw OpenMusicEventEditResetError.missingBaseline(eventID)
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
