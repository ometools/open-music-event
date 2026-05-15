import Dependencies
import Foundation
import OpenMusicEventLexicon
import SQLiteData
import SourceEditing

public extension SourceEditingSession {
    static func openMusicEvent(eventID: OME.Event.ID) throws -> Self? {
        @Dependency(\.defaultDatabase) var database
        @Dependency(\.defaultBaselineDatabase) var defaultBaselineDatabase
        @Dependency(\.sourceEditingWorkingDatabasePath) var workingDatabasePath

        guard let workingDatabasePath else {
            return nil
        }

        let baseline: SourceBaselineRecord? = try database.read { db in
            let provenance = try EventSourceProvenanceRecord
                .where { $0.id.eq(eventID) }
                .fetchOne(db)
            guard let sourceBaselineID = provenance?.sourceBaselineID else {
                return nil
            }
            return try SourceBaselineRecord
                .where { $0.id.eq(sourceBaselineID) }
                .fetchOne(db)
        }
        guard let baseline else {
            return nil
        }

        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        configuration.foreignKeysEnabled = true

        let baselineDirectoryURL = URL(fileURLWithPath: defaultBaselineDatabase.path)
            .deletingLastPathComponent()
        return try Self(
            workingDatabasePath: workingDatabasePath,
            baselineDatabasePath: baselineDirectoryURL
                .appendingPathComponent(baseline.databaseFileName)
                .path,
            configuration: configuration
        )
    }
}
