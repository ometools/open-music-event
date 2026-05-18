import Dependencies
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceEditing
import SQLiteData

public extension OME {
    struct DeletedOrganizerSourceData: Equatable, Sendable {
        public var sourceProvenances: [SourceDatabaseInsertion.SourceProvenance]

        public init(
            sourceProvenances: [SourceDatabaseInsertion.SourceProvenance]
        ) {
            self.sourceProvenances = sourceProvenances
        }
    }

    static func deleteDownloadedOrganizerSourceData(
        for organizerID: Organizer.ID,
        in db: Database
    ) throws -> DeletedOrganizerSourceData {
        let provenanceRecords = try EventSourceProvenanceRecord
            .where { $0.id.organizerID.eq(organizerID) }
            .fetchAll(db)
        let sourceProvenances = provenanceRecords
            .map(\.sourceProvenance)
            .uniqued { provenance in
                [
                    provenance.kind.rawValue,
                    provenance.reference,
                    provenance.ref ?? "",
                ]
                .joined(separator: "\u{1F}")
            }
        let sourceBaselineIDs = provenanceRecords
            .compactMap(\.sourceBaselineID)
            .uniqued()

        guard !sourceBaselineIDs.isEmpty || !sourceProvenances.isEmpty else {
            return DeletedOrganizerSourceData(sourceProvenances: [])
        }

        @Dependency(\.defaultBaselineDatabase) var baselineDatabase
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(baselineDatabase.database)

        try baselineDatabase.write { baselineDB in
            try EventSourceProvenanceRecord
                .where { $0.id.organizerID.eq(organizerID) }
                .delete()
                .execute(baselineDB)
            try OME.Organizer
                .where { $0.id.eq(organizerID) }
                .delete()
                .execute(baselineDB)

            for sourceBaselineID in sourceBaselineIDs {
                try SourceBaselineRecord
                    .where { $0.id.eq(sourceBaselineID) }
                    .delete()
                    .execute(baselineDB)
            }
        }

        for sourceBaselineID in sourceBaselineIDs {
            try SourceBaselineRecord
                .where { $0.id.eq(sourceBaselineID) }
                .delete()
                .execute(db)
        }
        try EventSourceProvenanceRecord
            .where { $0.id.organizerID.eq(organizerID) }
            .delete()
            .execute(db)

        return DeletedOrganizerSourceData(sourceProvenances: sourceProvenances)
    }
}

private extension EventSourceProvenanceRecord {
    var sourceProvenance: OME.SourceDatabaseInsertion.SourceProvenance {
        OME.SourceDatabaseInsertion.SourceProvenance(
            kind: sourceKind,
            reference: sourceReference,
            ref: ref
        )
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        var result: [Element] = []
        for element in self where seen.insert(element).inserted {
            result.append(element)
        }
        return result
    }
}

private extension Sequence {
    func uniqued<ID: Hashable>(by id: (Element) -> ID) -> [Element] {
        var seen: Set<ID> = []
        var result: [Element] = []
        for element in self where seen.insert(id(element)).inserted {
            result.append(element)
        }
        return result
    }
}
