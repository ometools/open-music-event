import Dependencies
import Foundation
import OpenMusicEventLexicon
import SQLiteData
import SourceEditing

public enum OpenMusicEventEditResetError: Error, Equatable, Sendable {
    case missingSourceEditingSession
}

public struct OpenMusicEventEditResetter: Sendable {
    public var reset: @Sendable (OME.Event.ID) throws -> Void

    public init(reset: @escaping @Sendable (OME.Event.ID) throws -> Void) {
        self.reset = reset
    }
}

public extension SourceEditingSession {
    static func openMusicEvent(eventID: OME.Event.ID) throws -> Self? {
        @Dependency(\.defaultDatabase) var database
        @Dependency(\.defaultBaselineDatabase) var defaultBaselineDatabase
        @Dependency(\.sourceReferenceDatabase) var sourceReferenceDatabase
        @Dependency(\.sourcePatchInvalidations) var sourcePatchInvalidations
        @Dependency(\.sourceEditingWorkingDatabasePath) var workingDatabasePath

        guard let workingDatabasePath else {
            return nil
        }

        let sourceContext: (
            provenance: EventSourceProvenanceRecord,
            baseline: SourceBaselineRecord
        )? = try database.read { db -> (
            provenance: EventSourceProvenanceRecord,
            baseline: SourceBaselineRecord
        )? in
            let fetchedProvenance = try EventSourceProvenanceRecord
                .where { $0.id.eq(eventID) }
                .fetchOne(db)
            guard let provenance = fetchedProvenance,
                  let sourceBaselineID = provenance.sourceBaselineID
            else {
                return nil
            }
            guard let baseline = try SourceBaselineRecord.where({
                $0.id.eq(sourceBaselineID)
            }).fetchOne(db) else {
                return nil
            }
            return (provenance, baseline)
        }
        guard let sourceContext else {
            return nil
        }

        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        configuration.foreignKeysEnabled = true

        let baselineDatabasePath: String
        if let sourceLocalDatabase = try sourceReferenceDatabase.existing(sourceContext.provenance.sourceProvenance) {
            baselineDatabasePath = sourceLocalDatabase.path
        } else {
            let fallbackURL = URL(fileURLWithPath: defaultBaselineDatabase.path)
                .deletingLastPathComponent()
                .appendingPathComponent(sourceContext.baseline.databaseFileName)
            guard FileManager.default.fileExists(atPath: fallbackURL.path) else {
                return nil
            }
            baselineDatabasePath = fallbackURL.path
        }

        let session = try Self(
            workingDatabasePath: workingDatabasePath,
            baselineDatabasePath: baselineDatabasePath,
            configuration: configuration
        )
        try session.database.write { db in
            try sourcePatchInvalidations.installTriggers(db)
        }
        return session
    }

    func resetOpenMusicEventEdits(eventID: OME.Event.ID) throws {
        try reset(
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
    var openMusicEventEditResetter: OpenMusicEventEditResetter {
        get { self[OpenMusicEventEditResetterKey.self] }
        set { self[OpenMusicEventEditResetterKey.self] = newValue }
    }
}

private enum OpenMusicEventEditResetterKey: DependencyKey {
    static var liveValue: OpenMusicEventEditResetter {
        OpenMusicEventEditResetter { eventID in
            @Dependency(\.sourceEditingSession) var sourceEditingSession
            guard let sourceEditingSession else {
                throw OpenMusicEventEditResetError.missingSourceEditingSession
            }
            try sourceEditingSession.resetOpenMusicEventEdits(eventID: eventID)
        }
    }

    static var testValue: OpenMusicEventEditResetter {
        OpenMusicEventEditResetter { _ in
            throw OpenMusicEventEditResetError.missingSourceEditingSession
        }
    }
}
