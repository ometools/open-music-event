import Dependencies
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceEditing
import SQLiteData

public extension SourceWorkspaceReferenceMigrator {
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
        let prepared = try await PreparedSourceDatabaseInsertion(
            sourceInsertion: self,
            importedAt: Date()
        )

        try await database.write { db in
            try prepared.insert(into: db)
        }
    }

    /// Installs one published event and records the attendee's installation intent in the same
    /// transaction.
    func installPublishedEvent(
        _ eventID: OME.Event.ID,
        from workspace: SourceWorkspace,
        in database: any DatabaseWriter,
        initializeInstalledEvent: @escaping @Sendable (Database) throws -> Void = { _ in }
    ) async throws {
        try validatePublishedEvent(eventID, from: workspace)
        let prepared = try await PreparedSourceDatabaseInsertion(
            sourceInsertion: self,
            importedAt: Date()
        )
        try await database.write { db in
            try validateEventSourceProvenanceConflicts(in: db)
            try OME.Event.find(eventID).delete().execute(db)
            try prepared.insert(into: db)
            try initializeInstalledEvent(db)
            try InstalledEventRecord.upsert {
                InstalledEventRecord(
                    id: eventID,
                    sourceProvenance: workspace.sourceProvenance
                )
            }
            .execute(db)
        }
    }

    /// Replaces exactly the rows owned by `workspace`, preserving every unrelated source already
    /// installed in the writable application database.
    func replaceSourceWorkspace(
        _ workspace: SourceWorkspace,
        branch: String,
        revision: String,
        in database: any DatabaseWriter
    ) async throws {
        let replacement = try await PreparedSourceWorkspaceReplacement(
            sourceInsertion: self,
            workspace: workspace
        )
        try await replacement.replace(branch: branch, revision: revision, in: database)
    }

    /// Prepares every parse and asset-materialization step before an external publication write.
    internal func prepareWorkspaceReplacement(
        _ workspace: SourceWorkspace
    ) async throws -> PreparedSourceWorkspaceReplacement {
        try await PreparedSourceWorkspaceReplacement(
            sourceInsertion: self,
            workspace: workspace
        )
    }

    /// Replaces one event installed as read-only published content without creating or advancing
    /// authoring-workspace revision state.
    ///
    /// Event-scoped installs deliberately do not prepare a source workspace. If that workspace has
    /// since been prepared for authoring, its mounted context owns source updates and this
    /// operation refuses to overwrite the writable editing database.
    func replacePublishedEvent(
        _ eventID: OME.Event.ID,
        from publishedWorkspace: SourceWorkspace,
        replacing installedWorkspace: SourceWorkspace,
        in database: any DatabaseWriter
    ) async throws {
        guard publishedWorkspace.referencesSameRepository(as: installedWorkspace) else {
            throw SourceWorkspaceInstallationError.mismatchedSource(installedWorkspace.id)
        }
        try validatePublishedEvent(eventID, from: publishedWorkspace)

        let prepared = try await PreparedSourceDatabaseInsertion(
            sourceInsertion: self,
            importedAt: Date()
        )
        try await database.write { db in
            guard try SourceWorkspaceInstallationRecord
                .find(installedWorkspace.id)
                .fetchOne(db) == nil
            else {
                throw SourceWorkspaceInstallationError.preparedWorkspace(installedWorkspace.id)
            }
            guard let installedProvenance = try EventSourceProvenanceRecord
                .find(eventID)
                .fetchOne(db),
                  installedProvenance.workspace?.id == installedWorkspace.id
            else {
                throw SourceWorkspaceInstallationError.mismatchedEvent(
                    eventID,
                    installedWorkspace.id
                )
            }

            try OME.Event.find(eventID).delete().execute(db)
            try prepared.insert(into: db)
            try InstalledEventRecord.upsert {
                InstalledEventRecord(
                    id: eventID,
                    sourceProvenance: publishedWorkspace.sourceProvenance
                )
            }
            .execute(db)
        }
    }

    func replacePublishedEvent(
        _ eventID: OME.Event.ID,
        from workspace: SourceWorkspace,
        in database: any DatabaseWriter
    ) async throws {
        try await replacePublishedEvent(
            eventID,
            from: workspace,
            replacing: workspace,
            in: database
        )
    }

    /// Restores the attendee view of a prepared workspace from published event-scoped source.
    ///
    /// Every event currently owned by the workspace is removed, but only events represented by an
    /// explicit `InstalledEventRecord` are reinserted. Volatile activation and writable
    /// installation rows are removed in the same transaction, while the exact selected context
    /// remains available to remount on the next authoring entry.
    static func restorePublishedEvents(
        _ publishedEvents: [OME.SourceDatabaseInsertion],
        replacing installedWorkspace: SourceWorkspace,
        in database: any DatabaseWriter
    ) async throws {
        var preparedEvents: [(
            eventID: OME.Event.ID,
            workspace: SourceWorkspace,
            insertion: PreparedSourceDatabaseInsertion
        )] = []
        preparedEvents.reserveCapacity(publishedEvents.count)
        for insertion in publishedEvents {
            guard let eventID = insertion.events.only?.id,
                  let publishedWorkspace = insertion.eventSourceProvenances
                    .first(where: { $0.eventID == eventID })
                    .flatMap({ EventSourceProvenanceRecord($0).workspace }),
                  publishedWorkspace.referencesSameRepository(as: installedWorkspace)
            else {
                throw SourceWorkspaceInstallationError.mismatchedSource(installedWorkspace.id)
            }
            try insertion.validatePublishedEvent(eventID, from: publishedWorkspace)
            preparedEvents.append(
                (
                    eventID: eventID,
                    workspace: publishedWorkspace,
                    insertion: try await PreparedSourceDatabaseInsertion(
                        sourceInsertion: insertion,
                        importedAt: Date()
                    )
                )
            )
        }
        let publishedEventIDs = Set(preparedEvents.map(\.eventID))
        let replacements = preparedEvents

        try await database.write { db in
            let installedEventIDs = Set(
                try InstalledEventRecord.all
                    .fetchAll(db)
                    .filter {
                        $0.workspace?.referencesSameRepository(as: installedWorkspace) == true
                    }
                    .map(\.id)
            )
            guard installedEventIDs == publishedEventIDs else {
                throw SourceWorkspaceInstallationError.installedEventSetChanged(
                    installedWorkspace.id
                )
            }

            let workspaceEventIDs = try EventSourceProvenanceRecord
                .where { $0.id.organizerID.eq(installedWorkspace.organizerID) }
                .fetchAll(db)
                .filter {
                    $0.workspace?.referencesSameRepository(as: installedWorkspace) == true
                }
                .map(\.id)
            for eventID in workspaceEventIDs {
                try OME.Event.find(eventID).delete().execute(db)
            }
            for publishedEvent in replacements {
                try publishedEvent.insertion.insert(into: db)
                try InstalledEventRecord.upsert {
                    InstalledEventRecord(
                        id: publishedEvent.eventID,
                        sourceProvenance: publishedEvent.workspace.sourceProvenance
                    )
                }
                .execute(db)
            }
            try SourceWorkspaceEditingState.deactivate(installedWorkspace.id, in: db)
        }
    }

    static func restorePublishedEvents(
        _ publishedEvents: [OME.SourceDatabaseInsertion],
        from workspace: SourceWorkspace,
        in database: any DatabaseWriter
    ) async throws {
        try await restorePublishedEvents(
            publishedEvents,
            replacing: workspace,
            in: database
        )
    }

    private func validatePublishedEvent(
        _ eventID: OME.Event.ID,
        from workspace: SourceWorkspace
    ) throws {
        let incomingProvenances = eventSourceProvenances.map(EventSourceProvenanceRecord.init)
        guard !incomingProvenances.isEmpty,
              incomingProvenances.allSatisfy({
                  $0.id == eventID && $0.workspace?.id == workspace.id
              }),
              events.count == 1,
              events.first?.id == eventID
        else {
            throw SourceWorkspaceInstallationError.mismatchedEvent(
                eventID,
                workspace.id
            )
        }
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

struct PreparedSourceWorkspaceReplacement: Sendable {
    private let prepared: PreparedSourceDatabaseInsertion
    private let workspace: SourceWorkspace

    init(
        sourceInsertion: OME.SourceDatabaseInsertion,
        workspace: SourceWorkspace
    ) async throws {
        let incomingProvenances = sourceInsertion.eventSourceProvenances.map(
            EventSourceProvenanceRecord.init
        )
        guard incomingProvenances.allSatisfy({ $0.workspace?.id == workspace.id }) else {
            throw SourceWorkspaceInstallationError.mismatchedSource(workspace.id)
        }
        self.workspace = workspace
        self.prepared = try await PreparedSourceDatabaseInsertion(
            sourceInsertion: sourceInsertion,
            importedAt: Date()
        )
    }

    func replace(
        branch: String,
        revision: String,
        recordsReferenceRevision: Bool = false,
        in database: any DatabaseWriter
    ) async throws {
        try await database.write { db in
            try replace(
                branch: branch,
                revision: revision,
                recordsReferenceRevision: recordsReferenceRevision,
                in: db
            )
        }
    }

    func replace(
        branch: String,
        revision: String,
        recordsReferenceRevision: Bool = false,
        in database: Database
    ) throws {
        let organizerProvenances = try EventSourceProvenanceRecord
            .where { $0.id.organizerID.eq(workspace.organizerID) }
            .fetchAll(database)
        guard organizerProvenances.allSatisfy({ $0.workspace != nil }) else {
            throw SourceWorkspaceInstallationError.unscopedOrganizerSource(
                workspace.organizerID
            )
        }
        let conflictingWorkspaceIDs = Set(
            organizerProvenances.compactMap { $0.workspace?.id }
        )
        .subtracting([workspace.id])
        guard conflictingWorkspaceIDs.isEmpty else {
            throw SourceWorkspaceInstallationError.conflictingOrganizerSource(
                organizerID: workspace.organizerID,
                existingWorkspaceIDs: conflictingWorkspaceIDs.sorted {
                    $0.rawValue < $1.rawValue
                },
                incomingWorkspaceID: workspace.id
            )
        }

        let existingEventIDs = organizerProvenances
            .filter { $0.workspace?.id == workspace.id }
            .map(\.id)
        for eventID in existingEventIDs {
            try OME.Event.find(eventID).delete().execute(database)
        }
        try OME.Calendar
            .find(
                OME.Calendar.ID(
                    ownerID: workspace.organizerID,
                    calendarID: OME.Calendar.defaultID
                )
            )
            .delete()
            .execute(database)
        try WorkspaceRelationshipRecord
            .where { $0.id.workspaceID.eq(workspace.id) }
            .delete()
            .execute(database)

        try prepared.insert(into: database)
        try SourceWorkspaceInstallationRecord.upsert {
            SourceWorkspaceInstallationRecord(id: workspace.id, revision: revision)
        }
        .execute(database)
        try SourceWorkspaceSelectionRecord.upsert {
            SourceWorkspaceSelectionRecord(
                id: workspace.id,
                branch: branch,
                revision: revision
            )
        }
        .execute(database)
        if recordsReferenceRevision {
            try SourceWorkspaceReferenceRecord.upsert {
                SourceWorkspaceReferenceRecord(
                    id: workspace.id,
                    revision: revision
                )
            }
            .execute(database)
        }
    }
}

private enum SourceWorkspaceInstallationError: Error, Equatable {
    case conflictingOrganizerSource(
        organizerID: OME.Organizer.ID,
        existingWorkspaceIDs: [SourceWorkspace.ID],
        incomingWorkspaceID: SourceWorkspace.ID
    )
    case mismatchedEvent(OME.Event.ID, SourceWorkspace.ID)
    case mismatchedSource(SourceWorkspace.ID)
    case preparedWorkspace(SourceWorkspace.ID)
    case installedEventSetChanged(SourceWorkspace.ID)
    case unscopedOrganizerSource(OME.Organizer.ID)
}

private extension Array {
    var only: Element? {
        count == 1 ? self[0] : nil
    }
}

private struct PreparedSourceDatabaseInsertion: Sendable {
    var workspaceIDs: [SourceWorkspace.ID]
    var workspaceRelationships: [WorkspaceRelationshipRecord]
    var organizers: [OME.Organizer.Draft]
    var calendars: [OME.Calendar.Draft]
    var calendarEntries: [OME.CalendarEntry.Draft]
    var events: [OME.Event.Draft]
    var siteMaps: [OME.Event.SiteMap]
    var eventOrganizers: [OME.EventOrganizer.Draft]
    var eventSourceProvenances: [EventSourceProvenanceRecord]
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
        importedAt: Date
    ) async throws {
        @Dependency(\.localImageFileStore) var localImageFileStore

        self.eventSourceProvenances = sourceInsertion.eventSourceProvenances.map(
            EventSourceProvenanceRecord.init
        )
        self.workspaceIDs = Array(
            Set(eventSourceProvenances.compactMap { $0.workspace?.id })
        )
        .sorted { $0.rawValue < $1.rawValue }
        self.workspaceRelationships = workspaceIDs.flatMap { workspaceID in
            sourceInsertion.workspaceRelationships.compactMap { file in
                guard case let .known(.identity(identity)) = file.data.subject else {
                    return nil
                }
                return WorkspaceRelationshipRecord(
                    id: WorkspaceRelationshipRecord.ID(
                        workspaceID: workspaceID,
                        actorID: identity.did
                    ),
                    recordKey: file.fileName,
                    relationship: file.data
                )
            }
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
        self.siteMaps = sourceInsertion.siteMaps
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

        for index in siteMaps.indices {
            let result = try await materializer.materialize(
                siteMap: siteMaps[index],
                pendingFileAssets: pendingFileAssets
            )
            siteMaps[index] = result.value
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

        for index in commsPosts.indices {
            let result = try await materializer.materialize(
                commsPost: commsPosts[index],
                pendingFileAssets: pendingFileAssets
            )
            commsPosts[index] = result.value
            localImageBlobs.append(contentsOf: result.blobs)
        }
    }

    func insert(into db: Database) throws {
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
        if !siteMaps.isEmpty {
            try OME.Event.SiteMap.insert { siteMaps }.execute(db)
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
        for workspaceID in workspaceIDs {
            try WorkspaceRelationshipRecord
                .where { $0.id.workspaceID.eq(workspaceID) }
                .delete()
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
        if !workspaceRelationships.isEmpty {
            try WorkspaceRelationshipRecord.insert { workspaceRelationships }
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
            images: post.images,
            timestamp: post.timestamp,
            isPinned: post.isPinned,
            delivery: post.delivery,
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
        commsPost: CommsPost,
        pendingFileAssets: [String: OME.SourceDatabaseInsertion.PendingFileImageAsset]
    ) async throws -> Result<CommsPost> {
        let context = LocalImageCacheContext(commsPostID: commsPost.id)
        let images = try await materializeImages(
            images: commsPost.images,
            organizerID: context.organizerID,
            eventID: context.eventID,
            parentKind: context.parentKind,
            parentLocalID: context.parentLocalID,
            pendingFileAssets: pendingFileAssets
        )
        var commsPost = commsPost
        commsPost.images = images.images
        return .init(value: commsPost, blobs: images.blobs)
    }

    func materialize(
        siteMap: OME.Event.SiteMap,
        pendingFileAssets: [String: OME.SourceDatabaseInsertion.PendingFileImageAsset]
    ) async throws -> Result<OME.Event.SiteMap> {
        var siteMap = siteMap
        var blobs: [LocalImageBlob] = []
        for index in siteMap.styles.indices {
            let styleID = siteMap.styles[index].id.rawValue.rawValue
            let images = try await materializeImages(
                images: [siteMap.styles[index].image],
                organizerID: siteMap.id.organizerID,
                eventID: siteMap.id.eventID,
                parentKind: .event,
                parentLocalID: [
                    siteMap.id.eventID.rawValue.rawValue,
                    "site-map",
                    styleID,
                ].joined(separator: "|"),
                pendingFileAssets: pendingFileAssets
            )
            if let image = images.images?.first {
                siteMap.styles[index].image = image
            }
            blobs.append(contentsOf: images.blobs)
        }
        return .init(value: siteMap, blobs: blobs)
    }

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
