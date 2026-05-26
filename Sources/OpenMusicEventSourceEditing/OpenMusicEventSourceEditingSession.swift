import Dependencies
import Foundation
import OpenMusicEventLexicon
import SQLiteData
import SourceEditing

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
}
