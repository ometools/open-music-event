import ATProto
import ATProtoTypes
import Foundation
import OpenMusicEventLexicon
import SQLiteData

public enum PersistentStageRecordEditing {
    public enum Error: Swift.Error, Equatable {
        case eventUnavailable
        case stageUnavailable
        case stageInUse
        case invalidName
    }

    public struct Fields: Equatable, Sendable {
        public var name: String
        public var description: String?
        public var links: [OME.Link]?
        public var media: [Open<OME.Media>]?

        public init(
            name: String,
            description: String? = nil,
            links: [OME.Link]? = nil,
            media: [Open<OME.Media>]? = nil
        ) {
            self.name = name
            self.description = description
            self.links = links
            self.media = media
        }

        public init(_ stage: Stage) {
            self.init(
                name: stage.name,
                description: stage.description,
                links: stage.links,
                media: stage.media
            )
        }

        fileprivate func apply(to stage: inout Stage) {
            stage.name = name
            stage.description = description
            stage.links = links
            stage.media = media
        }
    }

    public static func create(
        eventID: Event.ID,
        fields: Fields,
        createdAt: Date,
        in db: Database
    ) throws -> Stage.ID {
        guard try Event.find(eventID).fetchOne(db) != nil else {
            throw Error.eventUnavailable
        }
        guard !fields.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Error.invalidName
        }
        let existing = try Stage.all.fetchAll(db)
            .filter { $0.id.authority == eventID.authority }
        let previousKey = existing.map(\.id).compactMap(\.rkey)
            .max { $0.rawValue < $1.rawValue }
        let id = try CanonicalRecordID.next(
            collection: Stage.lexiconID,
            in: eventID.authority,
            at: createdAt,
            after: previousKey
        )
        var stage = try Stage(
            id: id,
            name: fields.name,
            createdAt: ATProto.DateTime(rawValue: ISO8601DateFormatter().string(from: createdAt))
        )
        fields.apply(to: &stage)
        try Stage.insert { stage }.execute(db)
        return id
    }

    public static func update(
        _ stageID: Stage.ID,
        eventID: Event.ID,
        fields: Fields,
        in db: Database
    ) throws {
        guard try Event.find(eventID).fetchOne(db) != nil else {
            throw Error.eventUnavailable
        }
        guard !fields.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Error.invalidName
        }
        guard stageID.authority == eventID.authority,
              var stage = try Stage.find(stageID).fetchOne(db) else {
            throw Error.stageUnavailable
        }
        fields.apply(to: &stage)
        try Stage.upsert { stage }.execute(db)
    }

    public static func delete(
        _ stageID: Stage.ID,
        eventID: Event.ID,
        in db: Database
    ) throws {
        guard try Event.find(eventID).fetchOne(db) != nil else {
            throw Error.eventUnavailable
        }
        guard stageID.authority == eventID.authority,
              try Stage.find(stageID).fetchOne(db) != nil else {
            throw Error.stageUnavailable
        }
        let places = try EventPlace.all.fetchAll(db)
        guard !places.contains(where: { place in
            guard case let .known(.stage(use)) = place.kind else { return false }
            return use.stage == stageID
        }) else {
            throw Error.stageInUse
        }
        try Stage.find(stageID).delete().execute(db)
    }
}
