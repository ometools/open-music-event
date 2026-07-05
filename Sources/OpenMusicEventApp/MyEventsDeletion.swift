import Foundation
import OpenMusicEventAppEventViewer
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceEditing
import SQLiteData

enum MyEventsDeletion {
    static func deleteDownloadedSource(
        _ sourceBaselineID: SourceBaselineRecord.ID,
        in db: Database
    ) throws -> OMERecord.DeletedOrganizerSourceData {
        let sourceData = try OMERecord.deleteDownloadedSourceData(
            for: sourceBaselineID,
            in: db
        )
        let eventIDs = sourceData.eventIDs
        let appState = try AppState.find(1).fetchOne(db)
        if let selectedEventID = appState?.selectedEventID,
           eventIDs.contains(selectedEventID) {
            try AppState.update {
                $0.organizerID = #bind(nil as OMERecord.Organizer.ID?)
                $0.eventID = #bind(nil as OMERecord.ID<OMERecord.Event>?)
            }
            .execute(db)
        }

        try deleteEventOwnedRecords(eventIDs, in: db)
        try deleteUnreferencedOrganizers(eventIDs.map(\.organizerID), in: db)
        return sourceData
    }

    static func deleteCreatedLocalEvents(
        _ eventIDs: [OMERecord.Event.ID],
        in db: Database
    ) throws {
        var deletableEventIDs: [OMERecord.Event.ID] = []

        for eventID in eventIDs.uniqued() {
            let eventExists = try OMERecord.Event
                .where { $0.id.eq(eventID) }
                .fetchOne(db) != nil
            let hasSourceProvenance = try EventSourceProvenanceRecord
                .where { $0.id.eq(eventID) }
                .fetchOne(db) != nil

            if eventExists && !hasSourceProvenance {
                deletableEventIDs.append(eventID)
            }
        }

        guard !deletableEventIDs.isEmpty else {
            throw DeleteCreatedEventsError()
        }

        let appState = try AppState.find(1).fetchOne(db)
        if let selectedEventID = appState?.selectedEventID,
           deletableEventIDs.contains(selectedEventID) {
            try AppState.update {
                $0.organizerID = #bind(nil as OMERecord.Organizer.ID?)
                $0.eventID = #bind(nil as OMERecord.ID<OMERecord.Event>?)
            }
            .execute(db)
        }

        try deleteEventOwnedRecords(deletableEventIDs, in: db)
        try deleteUnreferencedOrganizers(deletableEventIDs.map(\.organizerID), in: db)
    }

    private static func deleteEventOwnedRecords(
        _ eventIDs: [OMERecord.Event.ID],
        in db: Database
    ) throws {
        for eventID in eventIDs.uniqued() {
            try deleteRelationshipsOwnedByEvent(eventID, in: db)

            try db.execute(
                sql: #"""
                DELETE FROM "calendarEntries"
                WHERE json_extract("event", '$.uri') = ?
                """#,
                arguments: [OMERecord.Event.reference(id: eventID).uri.description]
            )
            try OMERecord.Performance.Contributors
                .where { $0.performanceID.organizerID.eq(eventID.organizerID) }
                .where { $0.performanceID.eventID.eq(eventID.eventID) }
                .delete()
                .execute(db)
            try OMERecord.Performance
                .where { $0.id.organizerID.eq(eventID.organizerID) }
                .where { $0.id.eventID.eq(eventID.eventID) }
                .delete()
                .execute(db)
            try OMERecord.Poster
                .where { $0.id.organizerID.eq(eventID.organizerID) }
                .where { $0.id.eventID.eq(eventID.eventID) }
                .delete()
                .execute(db)
            try OMERecord.Channel
                .where { $0.id.organizerID.eq(eventID.organizerID) }
                .where { $0.id.eventID.eq(eventID.eventID) }
                .delete()
                .execute(db)
            try OMERecord.Contributor.Claim
                .where { $0.contributorID.organizerID.eq(eventID.organizerID) }
                .where { $0.contributorID.eventID.eq(eventID.eventID) }
                .delete()
                .execute(db)
            try OMERecord.Contributor
                .where { $0.id.organizerID.eq(eventID.organizerID) }
                .where { $0.id.eventID.eq(eventID.eventID) }
                .delete()
                .execute(db)
            try OMERecord.Schedule
                .where { $0.id.organizerID.eq(eventID.organizerID) }
                .where { $0.id.eventID.eq(eventID.eventID) }
                .delete()
                .execute(db)
            try OMERecord.Stage
                .where { $0.id.organizerID.eq(eventID.organizerID) }
                .where { $0.id.eventID.eq(eventID.eventID) }
                .delete()
                .execute(db)
            try OMERecord.EventOrganizer
                .where { $0.id.organizerID.eq(eventID.organizerID) }
                .where { $0.id.eventID.eq(eventID.eventID) }
                .delete()
                .execute(db)
            try OMERecord.Event
                .where { $0.id.eq(eventID) }
                .delete()
                .execute(db)

            try EventViewerState
                .where { $0.id.eq(eventID) }
                .delete()
                .execute(db)
            try ScheduleViewerState
                .where { $0.id.eventID.eq(eventID) }
                .delete()
                .execute(db)
            try ContributorPreferences
                .where { $0.id.organizerID.eq(eventID.organizerID) }
                .where { $0.id.eventID.eq(eventID.eventID) }
                .delete()
                .execute(db)
            try PerformancePreferences
                .where { $0.id.organizerID.eq(eventID.organizerID) }
                .where { $0.id.eventID.eq(eventID.eventID) }
                .delete()
                .execute(db)
            try ChannelPreferences
                .where { $0.id.organizerID.eq(eventID.organizerID) }
                .where { $0.id.eventID.eq(eventID.eventID) }
                .delete()
                .execute(db)
            try PosterPreferences
                .where { $0.id.organizerID.eq(eventID.organizerID) }
                .where { $0.id.eventID.eq(eventID.eventID) }
                .delete()
                .execute(db)
            try LocalImageBlob
                .where { $0.organizerID.eq(eventID.organizerID) }
                .where { $0.eventID.eq(eventID.eventID) }
                .delete()
                .execute(db)
        }
    }

    private static func deleteRelationshipsOwnedByEvent(
        _ eventID: OMERecord.Event.ID,
        in db: Database
    ) throws {
        var recordURIs = [
            OMERecord.Relationship.RecordReference(eventID: eventID).uri.description
        ]
        recordURIs.append(
            contentsOf: try OMERecord.Performance
                .where { $0.id.organizerID.eq(eventID.organizerID) }
                .where { $0.id.eventID.eq(eventID.eventID) }
                .fetchAll(db)
                .map { OMERecord.Relationship.RecordReference(performanceID: $0.id).uri.description }
        )
        recordURIs.append(
            contentsOf: try OMERecord.Contributor
                .where { $0.id.organizerID.eq(eventID.organizerID) }
                .where { $0.id.eventID.eq(eventID.eventID) }
                .fetchAll(db)
                .map { OMERecord.Relationship.RecordReference(contributorID: $0.id).uri.description }
        )

        for recordURI in recordURIs.uniqued() {
            try db.execute(
                sql: #"""
                DELETE FROM "relationships"
                WHERE json_extract("subject", '$.uri') = ?
                   OR json_extract("object", '$.uri') = ?
                """#,
                arguments: [recordURI, recordURI]
            )
        }
    }

    private static func deleteUnreferencedOrganizers(
        _ organizerIDs: [OMERecord.Organizer.ID],
        in db: Database
    ) throws {
        for organizerID in organizerIDs.uniqued() {
            let eventOrganizerCount = try OMERecord.EventOrganizer
                .where { $0.id.eventOrganizerID.eq(organizerID) }
                .fetchCount(db)
            let ownedEventCount = try OMERecord.Event
                .where { $0.id.organizerID.eq(organizerID) }
                .fetchCount(db)
            if eventOrganizerCount == 0 && ownedEventCount == 0 {
                try OrganizerPreferences
                    .where { $0.organizerID.eq(organizerID) }
                    .delete()
                    .execute(db)
                try OMERecord.Organizer
                    .where { $0.id.eq(organizerID) }
                    .delete()
                    .execute(db)
            }
        }
    }
}

private struct DeleteCreatedEventsError: Error {}

extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        var result: [Element] = []
        for element in self where seen.insert(element).inserted {
            result.append(element)
        }
        return result
    }
}
