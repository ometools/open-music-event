import Dependencies
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceEditing
import SQLiteData

public extension SourceReferenceDatabaseMigrator {
    static let openMusicEvent = Self { database in
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database.database)
    }
}

public extension OME.SourceDatabaseInsertion {
    func migrateAndInsertIntoDefaultDatabase() async throws {
        @Dependency(\.defaultDatabase) var database
        try await migrateAndInsert(into: database)
    }

    func migrateAndInsert(into database: any DatabaseWriter) async throws {
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        try await insert(into: database)
    }

    func insert(into database: any DatabaseWriter) async throws {
        try await database.read { db in
            try validateEventSourceProvenanceConflicts(in: db)
        }

        @Dependency(\.sourceReferenceDatabase) var sourceReferenceDatabase
        let sourceReferenceDatabases = try sourceReferenceDatabasesByBaselineID(
            sourceReferenceDatabase: sourceReferenceDatabase
        )
        let prepared = try await preparedInsertion(
            sourceReferenceDatabases: sourceReferenceDatabases
        )

        try insert(
            prepared,
            intoSourceReferenceDatabases: sourceReferenceDatabases.values
        )

        try await database.write { db in
            try prepared.insert(into: db)
        }
    }

    func prepareSourceReferenceDatabases() async throws {
        @Dependency(\.sourceReferenceDatabase) var sourceReferenceDatabase
        let sourceReferenceDatabases = try sourceReferenceDatabasesByBaselineID(
            sourceReferenceDatabase: sourceReferenceDatabase
        )
        let prepared = try await preparedInsertion(
            sourceReferenceDatabases: sourceReferenceDatabases
        )
        try insert(
            prepared,
            intoSourceReferenceDatabases: sourceReferenceDatabases.values
        )
    }

    private func insert(
        _ prepared: PreparedSourceDatabaseInsertion,
        intoSourceReferenceDatabases sourceReferenceDatabases: Dictionary<
            SourceBaselineRecord.ID,
            SourceBaselineDatabase
        >.Values
    ) throws {
        for sourceReferenceDatabase in sourceReferenceDatabases {
            try sourceReferenceDatabase.write { db in
                try prepared.insert(into: db)
            }
        }
    }

    private func preparedInsertion(
        sourceReferenceDatabases: [SourceBaselineRecord.ID: SourceBaselineDatabase]
    ) async throws -> PreparedSourceDatabaseInsertion {
        let baselineDatabaseFileNamesByID = Dictionary(
            uniqueKeysWithValues: sourceReferenceDatabases.map { baselineID, database in
                (
                    baselineID,
                    URL(fileURLWithPath: database.path).lastPathComponent
                )
            }
        )
        return try await PreparedSourceDatabaseInsertion(
            sourceInsertion: self,
            baselineDatabaseFileNamesByID: baselineDatabaseFileNamesByID,
            importedAt: Date()
        )
    }

    private func sourceReferenceDatabasesByBaselineID(
        sourceReferenceDatabase: SourceReferenceDatabaseClient
    ) throws -> [SourceBaselineRecord.ID: SourceBaselineDatabase] {
        var databases: [SourceBaselineRecord.ID: SourceBaselineDatabase] = [:]
        for sourceProvenance in eventSourceProvenances.map(\.source).uniquedSourceProvenances() {
            let database = try sourceReferenceDatabase.prepareForImport(sourceProvenance)
            try SourceReferenceDatabaseMigrator.openMusicEvent.migrate(database)
            databases[SourceBaselineRecord.ID(source: sourceProvenance)] = database
        }
        return databases
    }

    private func validateEventSourceProvenanceConflicts(in db: Database) throws {
        for provenance in eventSourceProvenances
        where provenance.eventIDOrigin == .inferred {
            let existingProvenance = try EventSourceProvenanceRecord
                .where { $0.id.eq(provenance.eventID) }
                .fetchOne(db)

            if let existingProvenance {
                guard existingProvenance.eventIDOrigin == .inferred,
                      existingProvenance.sourceKind == provenance.source.kind,
                      existingProvenance.sourceReference == provenance.source.reference
                else {
                    throw OME.SourceDatabaseInsertion.Error.conflictingInferredEventID(
                        eventID: provenance.eventID,
                        existingSourceKind: existingProvenance.sourceKind,
                        existingSourceReference: existingProvenance.sourceReference,
                        incomingSourceKind: provenance.source.kind,
                        incomingSourceReference: provenance.source.reference
                    )
                }
                continue
            }

            let existingEventCount = try OME.Event
                .where { $0.id.eq(provenance.eventID) }
                .fetchCount(db)
            guard existingEventCount == 0 else {
                throw OME.SourceDatabaseInsertion.Error.conflictingInferredEventID(
                    eventID: provenance.eventID,
                    existingSourceKind: nil,
                    existingSourceReference: nil,
                    incomingSourceKind: provenance.source.kind,
                    incomingSourceReference: provenance.source.reference
                )
            }
        }
    }
}

private extension OME.SourceDatabaseInsertion.SourceProvenance {
    var stableStorageKey: String {
        [
            kind.rawValue,
            reference,
            ref ?? "",
        ]
        .joined(separator: "\u{1F}")
    }
}

private extension Sequence where Element == OME.SourceDatabaseInsertion.SourceProvenance {
    func uniquedSourceProvenances() -> [Element] {
        var seen: Set<String> = []
        var result: [Element] = []
        for element in self where seen.insert(element.stableStorageKey).inserted {
            result.append(element)
        }
        return result
    }
}

private enum PreparedSourceDatabaseInsertionError: Error {
    case missingSourceReferenceDatabase(SourceBaselineRecord.ID)
}

private struct PreparedSourceDatabaseInsertion {
    var sourceBaselines: [SourceBaselineRecord]
    var editingWorkspaces: [EditingWorkspaceRecord]
    var organizers: [OME.Organizer.Draft]
    var calendars: [OME.Calendar.Draft]
    var calendarEntries: [OME.CalendarEntry.Draft]
    var events: [OME.Event.Draft]
    var eventOrganizers: [OME.EventOrganizer.Draft]
    var eventSourceProvenances: [EventSourceProvenanceRecord]
    var eventEditingWorkspaces: [EventEditingWorkspaceRecord]
    var stages: [OME.Stage.Draft]
    var schedules: [OME.Schedule.Draft]
    var contributors: [OME.Contributor.Draft]
    var channels: [OME.Channel.Draft]
    var commsPosts: [CommsPost]
    var posters: [OME.Poster.Draft]
    var scheduleItems: [OME.ScheduleItem.Draft]
    var scheduleItemPerformanceDetails: [OME.ScheduleItem.PerformanceDetails.Draft]
    var scheduleItemContributors: [OME.ScheduleItem.Contributor.Draft]
    var relationships: [OME.Relationship]
    var localImageBlobs: [LocalImageBlob]

    init(
        sourceInsertion: OME.SourceDatabaseInsertion,
        baselineDatabaseFileNamesByID: [SourceBaselineRecord.ID: String],
        importedAt: Date
    ) async throws {
        @Dependency(\.localImageFileStore) var localImageFileStore

        var sourceBaselinesByID: [SourceBaselineRecord.ID: SourceBaselineRecord] = [:]
        self.eventSourceProvenances = try sourceInsertion.eventSourceProvenances.map { provenance in
            let baselineID = SourceBaselineRecord.ID(source: provenance.source)
            guard let databaseFileName = baselineDatabaseFileNamesByID[baselineID] else {
                throw PreparedSourceDatabaseInsertionError.missingSourceReferenceDatabase(baselineID)
            }
            let baseline = SourceBaselineRecord(
                source: provenance.source,
                databaseFileName: databaseFileName,
                importedAt: importedAt
            )
            sourceBaselinesByID[baseline.id] = baseline
            return EventSourceProvenanceRecord(provenance, sourceBaselineID: baseline.id)
        }
        self.sourceBaselines = sourceBaselinesByID.values.sorted { $0.id.rawValue < $1.id.rawValue }
        self.editingWorkspaces = sourceBaselines.map {
            EditingWorkspaceRecord(teamSourceBaseline: $0)
        }
        self.eventEditingWorkspaces = eventSourceProvenances.map { provenance in
            EventEditingWorkspaceRecord(
                id: provenance.id,
                workspaceID: EditingWorkspaceRecord.ID(
                    sourceBaselineID: provenance.sourceBaselineID!
                )
            )
        }
        self.organizers = sourceInsertion.organizers
        self.calendars = sourceInsertion.calendars
        self.calendarEntries = sourceInsertion.calendarEntries.map { entry in
            OME.CalendarEntry.Draft(
                id: entry.id,
                event: entry.event,
                createdAt: importedAt,
                note: entry.note,
                pinned: entry.pinned
            )
        }
        self.events = sourceInsertion.events
        self.eventOrganizers = sourceInsertion.eventOrganizers
        self.stages = sourceInsertion.stages
        self.schedules = sourceInsertion.schedules
        self.contributors = sourceInsertion.contributors
        self.channels = sourceInsertion.channels
        self.commsPosts = sourceInsertion.communicationPosts.map(CommsPost.init)
        self.posters = sourceInsertion.posters
        self.scheduleItems = sourceInsertion.scheduleItems
        self.scheduleItemPerformanceDetails = sourceInsertion.scheduleItemPerformanceDetails
        self.scheduleItemContributors = sourceInsertion.scheduleItemContributors
        self.relationships = sourceInsertion.relationships.map {
            var relationship = $0
            relationship.createdAt = Self.relationshipCreatedAt(importedAt)
            return relationship
        }
        self.localImageBlobs = []

        let materializer = LocalImageMaterializer(
            now: Date(),
            httpClientGet: { _ in
                throw SourceImportImageMaterializationError.remoteFetchDisabled
            },
            localFileWriter: localImageFileStore.write
        )
        let pendingFileAssets = Dictionary(
            uniqueKeysWithValues: sourceInsertion.pendingFileImageAssets.map { ($0.assetKey, $0) }
        )

        for index in calendars.indices {
            guard let calendarID = calendars[index].id else { continue }
            let result = try await materializer.materialize(
                calendar: calendars[index],
                pendingFileAssets: pendingFileAssets,
                parentLocalID: calendarID.calendarID.rawValue.rawValue
            )
            calendars[index] = result.value
            localImageBlobs.append(contentsOf: result.blobs)
        }

        for index in events.indices {
            guard let eventID = events[index].id else { continue }
            let result = try await materializer.materialize(
                event: events[index],
                pendingFileAssets: pendingFileAssets,
                parentLocalID: eventID.eventID.rawValue.rawValue
            )
            events[index] = result.value
            localImageBlobs.append(contentsOf: result.blobs)
        }

        for index in stages.indices {
            guard let stageID = stages[index].id else { continue }
            let result = try await materializer.materialize(
                stage: stages[index],
                pendingFileAssets: pendingFileAssets,
                parentLocalID: stageID.stageID.rawValue.rawValue
            )
            stages[index] = result.value
            localImageBlobs.append(contentsOf: result.blobs)
        }

        for index in contributors.indices {
            guard let contributorID = contributors[index].id else { continue }
            let result = try await materializer.materialize(
                contributor: contributors[index],
                pendingFileAssets: pendingFileAssets,
                parentLocalID: contributorID.contributorID.rawValue.rawValue
            )
            contributors[index] = result.value
            localImageBlobs.append(contentsOf: result.blobs)
        }
    }

    func insert(into db: Database) throws {
        if !sourceBaselines.isEmpty {
            try SourceBaselineRecord.insert {
                sourceBaselines
            } onConflict: {
                $0.id
            }
            .execute(db)
        }
        if !editingWorkspaces.isEmpty {
            try EditingWorkspaceRecord.insert {
                editingWorkspaces
            } onConflict: {
                $0.id
            }
            .execute(db)
        }
        if !organizers.isEmpty {
            try OME.Organizer.insert {
                organizers
            } onConflict: {
                $0.id
            }
            .execute(db)
        }
        if !calendars.isEmpty {
            try OME.Calendar.insert {
                calendars
            } onConflict: {
                (
                    $0.id.ownerID,
                    $0.id.calendarID
                )
            }
            .execute(db)
        }
        if !events.isEmpty {
            try OME.Event.insert { events }.execute(db)
        }
        if !eventOrganizers.isEmpty {
            try OME.EventOrganizer.insert {
                eventOrganizers
            } onConflict: {
                (
                    $0.id.organizerID,
                    $0.id.eventID,
                    $0.id.eventOrganizerID
                )
            }
            .execute(db)
        }
        if !eventSourceProvenances.isEmpty {
            try EventSourceProvenanceRecord.insert {
                eventSourceProvenances
            }
            .execute(db)
        }
        if !eventEditingWorkspaces.isEmpty {
            try EventEditingWorkspaceRecord.insert {
                eventEditingWorkspaces
            }
            .execute(db)
        }
        for calendar in calendars {
            guard let calendarID = calendar.id else { continue }
            try OME.CalendarEntry
                .where { $0.id.calendarOwnerID.eq(calendarID.ownerID) }
                .where { $0.id.calendarID.eq(calendarID.calendarID) }
                .delete()
                .execute(db)
        }
        if !calendarEntries.isEmpty {
            try OME.CalendarEntry.insert {
                calendarEntries
            }
            .execute(db)
        }
        if !stages.isEmpty {
            try OME.Stage.insert { stages }.execute(db)
        }
        if !schedules.isEmpty {
            try OME.Schedule.insert { schedules }.execute(db)
        }
        if !contributors.isEmpty {
            try OME.Contributor.insert { contributors }.execute(db)
        }
        if !channels.isEmpty {
            try OME.Channel.insert { channels }.execute(db)
        }
        for channel in channels {
            guard let channelID = channel.id else { continue }
            try CommsPost
                .where { $0.id.organizerID.eq(channelID.organizerID) }
                .where { $0.id.eventID.eq(channelID.eventID) }
                .where { $0.id.channelID.eq(channelID.channelID) }
                .delete()
                .execute(db)
        }
        if !commsPosts.isEmpty {
            try CommsPost.insert { commsPosts }.execute(db)
        }
        if !posters.isEmpty {
            try OME.Poster.insert { posters }.execute(db)
        }
        if !scheduleItems.isEmpty {
            try OME.ScheduleItem.insert { scheduleItems }.execute(db)
        }
        if !scheduleItemPerformanceDetails.isEmpty {
            try OME.ScheduleItem.PerformanceDetails.insert {
                scheduleItemPerformanceDetails
            }
            .execute(db)
        }
        if !scheduleItemContributors.isEmpty {
            try OME.ScheduleItem.Contributor.insert { scheduleItemContributors }.execute(db)
        }
        if !relationships.isEmpty {
            try OME.Relationship.insert { relationships }.execute(db)
        }
        if !localImageBlobs.isEmpty {
            try LocalImageBlob.insert { localImageBlobs }.execute(db)
        }
    }

    private static func relationshipCreatedAt(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

private extension CommsPost {
    init(_ post: OME.SourceDatabaseInsertion.CommunicationPost) {
        self.init(
            id: CommsPost.ID(
                organizerID: post.id.organizerID,
                eventID: post.id.eventID,
                channelID: post.id.channelID,
                postID: CommsPost.PostID(post.id.postID.rawValue.rawValue)
            ),
            title: post.title,
            contents: post.contents,
            headerImageURL: post.headerImageURL,
            timestamp: post.timestamp,
            isPinned: post.isPinned,
            sortIndex: post.sortIndex
        )
    }
}

public extension OpenMusicEventSourceValidator {
    func validateAndInsertIntoDefaultDatabase() async throws -> OpenMusicEventSourceValidationResult {
        @Dependency(\.defaultDatabase) var database
        return try await validateAndInsert(into: database)
    }

    func validateAndInsert(into database: any DatabaseWriter) async throws -> OpenMusicEventSourceValidationResult {
        let result = try await validate()
        try await result.insertion.migrateAndInsert(into: database)
        return result
    }
}

private extension LocalImageMaterializer {
    func materialize(
        calendar: OME.Calendar.Draft,
        pendingFileAssets: [String: OME.SourceDatabaseInsertion.PendingFileImageAsset],
        parentLocalID: String
    ) async throws -> Result<OME.Calendar.Draft> {
        let images = try await materializeImages(
            images: calendar.images,
            organizerID: calendar.id?.ownerID,
            eventID: nil,
            parentKind: .calendar,
            parentLocalID: parentLocalID,
            pendingFileAssets: pendingFileAssets
        )
        var calendar = calendar
        calendar.images = images.images
        return .init(value: calendar, blobs: images.blobs)
    }

    func materialize(
        event: OME.Event.Draft,
        pendingFileAssets: [String: OME.SourceDatabaseInsertion.PendingFileImageAsset],
        parentLocalID: String
    ) async throws -> Result<OME.Event.Draft> {
        let images = try await materializeImages(
            images: event.images,
            organizerID: event.id?.organizerID,
            eventID: event.id?.eventID,
            parentKind: .event,
            parentLocalID: parentLocalID,
            pendingFileAssets: pendingFileAssets
        )
        var event = event
        event.images = images.images
        return .init(value: event, blobs: images.blobs)
    }

    func materialize(
        stage: OME.Stage.Draft,
        pendingFileAssets: [String: OME.SourceDatabaseInsertion.PendingFileImageAsset],
        parentLocalID: String
    ) async throws -> Result<OME.Stage.Draft> {
        let images = try await materializeImages(
            images: stage.images,
            organizerID: stage.id?.organizerID,
            eventID: stage.id?.eventID,
            parentKind: .stage,
            parentLocalID: parentLocalID,
            pendingFileAssets: pendingFileAssets
        )
        var stage = stage
        stage.images = images.images
        return .init(value: stage, blobs: images.blobs)
    }

    func materialize(
        contributor: OME.Contributor.Draft,
        pendingFileAssets: [String: OME.SourceDatabaseInsertion.PendingFileImageAsset],
        parentLocalID: String
    ) async throws -> Result<OME.Contributor.Draft> {
        let images = try await materializeImages(
            images: contributor.images,
            organizerID: contributor.id?.organizerID,
            eventID: contributor.id?.eventID,
            parentKind: .contributor,
            parentLocalID: parentLocalID,
            pendingFileAssets: pendingFileAssets
        )
        var contributor = contributor
        contributor.images = images.images
        return .init(value: contributor, blobs: images.blobs)
    }

    private func materializeImages(
        images: [OME.ImageAsset]?,
        organizerID: OME.Organizer.ID?,
        eventID: OME.ID<OME.Event>?,
        parentKind: LocalImageBlob.ParentKind,
        parentLocalID: String,
        pendingFileAssets: [String: OME.SourceDatabaseInsertion.PendingFileImageAsset]
    ) async throws -> (images: [OME.ImageAsset]?, blobs: [LocalImageBlob]) {
        guard let organizerID, let images else {
            return (images, [])
        }

        var resolvedImages: [OME.ImageAsset] = []
        resolvedImages.reserveCapacity(images.count)
        var blobs: [LocalImageBlob] = []

        for var image in images {
            guard let assetKey = image.assetKey else {
                resolvedImages.append(image)
                continue
            }

            if let pendingFileAsset = pendingFileAssets[assetKey] {
                let localFileURL = try localFileWriter(assetKey, pendingFileAsset.data, pendingFileAsset.mimeType)
                image.source = .url(localFileURL)

                if image.materializationPolicy == .prefetchOnOpen {
                    blobs.append(
                        LocalImageBlob(
                            assetKey: assetKey,
                            organizerID: organizerID,
                            eventID: eventID,
                            parentKind: parentKind,
                            parentLocalID: parentLocalID,
                            role: image.role,
                            renderKind: image.renderKind,
                            mimeType: pendingFileAsset.mimeType,
                            data: pendingFileAsset.data,
                            sourceURL: pendingFileAsset.sourceURL,
                            lastFetchedAt: now
                        )
                    )
                }

                resolvedImages.append(image)
                continue
            }

            resolvedImages.append(image)
        }

        return (resolvedImages.isEmpty ? nil : resolvedImages, blobs)
    }
}

private enum SourceImportImageMaterializationError: Error {
    case remoteFetchDisabled
}
