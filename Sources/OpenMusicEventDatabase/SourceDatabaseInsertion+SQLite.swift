import Dependencies
import Foundation
import HTTPClient
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceEditing
import SQLiteData

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

        @Dependency(\.defaultBaselineDatabase) var baselineDatabase
        let prepared = try await PreparedSourceDatabaseInsertion(
            sourceInsertion: self,
            baselineDatabaseFileName: URL(fileURLWithPath: baselineDatabase.path).lastPathComponent,
            importedAt: Date()
        )

        if !prepared.sourceBaselines.isEmpty {
            var migrator = DatabaseMigrator()
            OME.DatabaseMigrations.register(into: &migrator)
            try migrator.migrate(baselineDatabase.database)

            try baselineDatabase.write { db in
                try prepared.insert(into: db)
            }
        }

        try await database.write { db in
            try prepared.insert(into: db)
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

private struct PreparedSourceDatabaseInsertion {
    var sourceBaselines: [SourceBaselineRecord]
    var organizers: [OME.Organizer.Draft]
    var events: [OME.Event.Draft]
    var eventOrganizers: [OME.EventOrganizer.Draft]
    var eventSourceProvenances: [EventSourceProvenanceRecord]
    var stages: [OME.Stage.Draft]
    var schedules: [OME.Schedule.Draft]
    var participants: [OME.Participant.Draft]
    var channels: [OME.Channel.Draft]
    var posters: [OME.Poster.Draft]
    var performances: [OME.Performance.Draft]
    var performanceParticipants: [OME.Performance.Participants.Draft]
    var localImageBlobs: [LocalImageBlob]

    init(
        sourceInsertion: OME.SourceDatabaseInsertion,
        baselineDatabaseFileName: String,
        importedAt: Date
    ) async throws {
        @Dependency(\.httpClient) var httpClient
        @Dependency(\.localImageFileStore) var localImageFileStore

        var sourceBaselinesByID: [SourceBaselineRecord.ID: SourceBaselineRecord] = [:]
        self.eventSourceProvenances = sourceInsertion.eventSourceProvenances.map { provenance in
            let baseline = SourceBaselineRecord(
                source: provenance.source,
                databaseFileName: baselineDatabaseFileName,
                importedAt: importedAt
            )
            sourceBaselinesByID[baseline.id] = baseline
            return EventSourceProvenanceRecord(provenance, sourceBaselineID: baseline.id)
        }
        self.sourceBaselines = sourceBaselinesByID.values.sorted { $0.id.rawValue < $1.id.rawValue }
        self.organizers = sourceInsertion.organizers
        self.events = sourceInsertion.events
        self.eventOrganizers = sourceInsertion.eventOrganizers
        self.stages = sourceInsertion.stages
        self.schedules = sourceInsertion.schedules
        self.participants = sourceInsertion.participants
        self.channels = sourceInsertion.channels
        self.posters = sourceInsertion.posters
        self.performances = sourceInsertion.performances
        self.performanceParticipants = sourceInsertion.performanceParticipants
        self.localImageBlobs = []

        let materializer = LocalImageMaterializer(
            now: Date(),
            httpClientGet: { url in
                try await httpClient.get(url, decodingTo: Data.self)
            },
            localFileWriter: localImageFileStore.write
        )
        let pendingFileAssets = Dictionary(
            uniqueKeysWithValues: sourceInsertion.pendingFileImageAssets.map { ($0.assetKey, $0) }
        )

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

        for index in participants.indices {
            guard let participantID = participants[index].id else { continue }
            let result = try await materializer.materialize(
                participant: participants[index],
                pendingFileAssets: pendingFileAssets,
                parentLocalID: participantID.participantID.rawValue.rawValue
            )
            participants[index] = result.value
            localImageBlobs.append(contentsOf: result.blobs)
        }
    }

    func insert(into db: Database) throws {
        if !sourceBaselines.isEmpty {
            try SourceBaselineRecord.insert {
                sourceBaselines
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
        if !stages.isEmpty {
            try OME.Stage.insert { stages }.execute(db)
        }
        if !schedules.isEmpty {
            try OME.Schedule.insert { schedules }.execute(db)
        }
        if !participants.isEmpty {
            try OME.Participant.insert { participants }.execute(db)
        }
        if !channels.isEmpty {
            try OME.Channel.insert { channels }.execute(db)
        }
        if !posters.isEmpty {
            try OME.Poster.insert { posters }.execute(db)
        }
        if !performances.isEmpty {
            try OME.Performance.insert { performances }.execute(db)
        }
        if !performanceParticipants.isEmpty {
            try OME.Performance.Participants.insert { performanceParticipants }.execute(db)
        }
        if !localImageBlobs.isEmpty {
            try LocalImageBlob.insert { localImageBlobs }.execute(db)
        }
    }
}

private extension LocalImageMaterializer {
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
        participant: OME.Participant.Draft,
        pendingFileAssets: [String: OME.SourceDatabaseInsertion.PendingFileImageAsset],
        parentLocalID: String
    ) async throws -> Result<OME.Participant.Draft> {
        let images = try await materializeImages(
            images: participant.images,
            organizerID: participant.id?.organizerID,
            eventID: participant.id?.eventID,
            parentKind: .participant,
            parentLocalID: parentLocalID,
            pendingFileAssets: pendingFileAssets
        )
        var participant = participant
        participant.images = images.images
        return .init(value: participant, blobs: images.blobs)
    }

    private func materializeImages(
        images: [OME.ImageAsset]?,
        organizerID: OME.Organizer.ID?,
        eventID: OME.ID<OME.Event>?,
        parentKind: LocalImageBlob.ParentKind,
        parentLocalID: String,
        pendingFileAssets: [String: OME.SourceDatabaseInsertion.PendingFileImageAsset]
    ) async throws -> (images: [OME.ImageAsset]?, blobs: [LocalImageBlob]) {
        guard let organizerID, let eventID, let images else {
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

        try await withThrowingTaskGroup(of: (Int, OME.ImageAsset, LocalImageBlob).self) { group in
            for (index, image) in resolvedImages.enumerated() {
                guard image.materializationPolicy == .prefetchOnOpen,
                      let assetKey = image.assetKey,
                      let remoteURL = image.url,
                      !remoteURL.isFileURL,
                      pendingFileAssets[assetKey] == nil else {
                    continue
                }

                group.addTask {
                    var image = image
                    let data = try await httpClientGet(remoteURL)
                    let mimeType = remoteURL.inferredImageMimeType
                    let localFileURL = try localFileWriter(assetKey, data, mimeType)
                    image.source = .url(localFileURL)
                    return (
                        index,
                        image,
                        LocalImageBlob(
                            assetKey: assetKey,
                            organizerID: organizerID,
                            eventID: eventID,
                            parentKind: parentKind,
                            parentLocalID: parentLocalID,
                            role: image.role,
                            renderKind: image.renderKind,
                            mimeType: mimeType,
                            data: data,
                            sourceURL: remoteURL,
                            lastFetchedAt: now
                        )
                    )
                }
            }

            for try await (index, image, blob) in group {
                resolvedImages[index] = image
                blobs.append(blob)
            }
        }

        return (resolvedImages.isEmpty ? nil : resolvedImages, blobs)
    }
}
