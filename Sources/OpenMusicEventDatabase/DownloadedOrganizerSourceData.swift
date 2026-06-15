import Dependencies
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceEditing
import SQLiteData

public extension OME {
    struct DeletedOrganizerSourceData: Equatable, Sendable {
        public var eventIDs: [Event.ID]
        public var sourceProvenances: [SourceDatabaseInsertion.SourceProvenance]

        public init(
            eventIDs: [Event.ID] = [],
            sourceProvenances: [SourceDatabaseInsertion.SourceProvenance]
        ) {
            self.eventIDs = eventIDs
            self.sourceProvenances = sourceProvenances
        }
    }

    static func deleteDownloadedSourceData(
        for sourceBaselineID: SourceBaselineRecord.ID,
        in db: Database
    ) throws -> DeletedOrganizerSourceData {
        let provenanceRecords = try EventSourceProvenanceRecord
            .where { $0.sourceBaselineID.eq(sourceBaselineID) }
            .fetchAll(db)
        let eventIDs = provenanceRecords.map(\.id).uniqued()
        let sourceProvenances = provenanceRecords.sourceProvenances()

        guard !eventIDs.isEmpty || !sourceProvenances.isEmpty else {
            return DeletedOrganizerSourceData(sourceProvenances: [])
        }

        @Dependency(\.sourceReferenceDatabase) var sourceReferenceDatabase
        for sourceProvenance in sourceProvenances {
            guard let referenceDatabase = try sourceReferenceDatabase.existing(sourceProvenance) else {
                continue
            }
            try SourceReferenceDatabaseMigrator.openMusicEvent.migrate(referenceDatabase)
            try referenceDatabase.write { baselineDB in
                try EventSourceProvenanceRecord
                    .where { $0.sourceBaselineID.eq(sourceBaselineID) }
                    .delete()
                    .execute(baselineDB)
                try SourceBaselineRecord
                    .where { $0.id.eq(sourceBaselineID) }
                    .delete()
                    .execute(baselineDB)
                try deleteOrganizersWithNoRemainingSourceLinks(
                    eventIDs.map(\.organizerID),
                    in: baselineDB
                )
            }
        }

        try SourceBaselineRecord
            .where { $0.id.eq(sourceBaselineID) }
            .delete()
            .execute(db)
        try EventSourceProvenanceRecord
            .where { $0.sourceBaselineID.eq(sourceBaselineID) }
            .delete()
            .execute(db)

        return DeletedOrganizerSourceData(
            eventIDs: eventIDs,
            sourceProvenances: sourceProvenances
        )
    }

    static func deleteDownloadedOrganizerSourceData(
        for organizerID: Organizer.ID,
        in db: Database
    ) throws -> DeletedOrganizerSourceData {
        let provenanceRecords = try EventSourceProvenanceRecord
            .where { $0.id.organizerID.eq(organizerID) }
            .fetchAll(db)
        let sourceProvenances = provenanceRecords.sourceProvenances()
        let sourceBaselineIDs = provenanceRecords
            .compactMap(\.sourceBaselineID)
            .uniqued()

        guard !sourceBaselineIDs.isEmpty || !sourceProvenances.isEmpty else {
            return DeletedOrganizerSourceData(sourceProvenances: [])
        }

        @Dependency(\.sourceReferenceDatabase) var sourceReferenceDatabase
        for sourceProvenance in sourceProvenances {
            guard let referenceDatabase = try sourceReferenceDatabase.existing(sourceProvenance) else {
                continue
            }
            try SourceReferenceDatabaseMigrator.openMusicEvent.migrate(referenceDatabase)
            try referenceDatabase.write { baselineDB in
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

        return DeletedOrganizerSourceData(
            eventIDs: provenanceRecords.map(\.id).uniqued(),
            sourceProvenances: sourceProvenances
        )
    }
}

private func deleteOrganizersWithNoRemainingSourceLinks(
    _ organizerIDs: [OME.Organizer.ID],
    in db: Database
) throws {
    for organizerID in organizerIDs.uniqued() {
        let remainingSourceLinkCount = try EventSourceProvenanceRecord
            .where { $0.id.organizerID.eq(organizerID) }
            .fetchCount(db)
        if remainingSourceLinkCount == 0 {
            try OME.Organizer
                .where { $0.id.eq(organizerID) }
                .delete()
                .execute(db)
        }
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

private extension Sequence where Element == EventSourceProvenanceRecord {
    func sourceProvenances() -> [OME.SourceDatabaseInsertion.SourceProvenance] {
        map(\.sourceProvenance)
            .uniqued { provenance in
                [
                    provenance.kind.rawValue,
                    provenance.reference,
                    provenance.ref ?? "",
                ]
                .joined(separator: "\u{1F}")
            }
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
