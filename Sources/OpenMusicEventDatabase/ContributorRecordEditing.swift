import ATProto
import ATProtoTypes
import Foundation
import OpenMusicEventLexicon
import SQLiteData

public enum ContributorRecordEditing {
    public enum Error: Swift.Error, Equatable {
        case eventUnavailable
        case contributorUnavailable
    }

    public struct Fields: Equatable, Sendable {
        public var name: String
        public var subject: DID?
        public var source: Contributor.Source?
        public var description: String?
        public var roles: [Open<Contributor.Role>]?
        public var links: [OME.Link]?
        public var media: [Open<OME.Media>]?

        public init(
            name: String,
            subject: DID? = nil,
            source: Contributor.Source? = nil,
            description: String? = nil,
            roles: [Open<Contributor.Role>]? = nil,
            links: [OME.Link]? = nil,
            media: [Open<OME.Media>]? = nil
        ) {
            self.name = name
            self.subject = subject
            self.source = source
            self.description = description
            self.roles = roles
            self.links = links
            self.media = media
        }

        public init(_ contributor: Contributor) {
            self.init(
                name: contributor.name,
                subject: contributor.subject,
                source: contributor.source,
                description: contributor.description,
                roles: contributor.roles,
                links: contributor.links,
                media: contributor.media
            )
        }

        fileprivate func apply(to contributor: inout Contributor) {
            contributor.name = name
            contributor.subject = subject
            contributor.source = source
            contributor.description = description
            contributor.roles = roles
            contributor.links = links
            contributor.media = media
        }
    }

    public static func create(
        eventID: Event.ID,
        fields: Fields,
        createdAt: Date,
        in db: Database
    ) throws -> Contributor.ID {
        guard try Event.find(eventID).fetchOne(db) != nil else {
            throw Error.eventUnavailable
        }
        let existing = try Contributor.all.fetchAll(db)
            .filter { $0.id.authority == eventID.authority }
        let previousKey = existing.map(\.id).compactMap(\.rkey)
            .max { $0.rawValue < $1.rawValue }
        let id = try CanonicalRecordID.next(
            collection: Contributor.lexiconID,
            in: eventID.authority,
            at: createdAt,
            after: previousKey
        )
        var contributor = try Contributor(
            id: id,
            event: eventID,
            name: fields.name,
            createdAt: ATProto.DateTime(rawValue: ISO8601DateFormatter().string(from: createdAt))
        )
        fields.apply(to: &contributor)
        try contributor.validateReferences()
        try Contributor.insert { contributor }.execute(db)
        return id
    }

    public static func update(
        _ contributorID: Contributor.ID,
        eventID: Event.ID,
        fields: Fields,
        in db: Database
    ) throws {
        guard try Event.find(eventID).fetchOne(db) != nil else {
            throw Error.eventUnavailable
        }
        guard var contributor = try Contributor.find(contributorID).fetchOne(db),
              contributor.event == eventID else {
            throw Error.contributorUnavailable
        }
        fields.apply(to: &contributor)
        try contributor.validateReferences()
        try Contributor.upsert { contributor }.execute(db)
    }

    public static func delete(
        _ contributorID: Contributor.ID,
        eventID: Event.ID,
        in db: Database
    ) throws {
        guard let contributor = try Contributor.find(contributorID).fetchOne(db),
              contributor.event == eventID else {
            throw Error.contributorUnavailable
        }
        let items = try ProgramItem.where { $0.event.eq(eventID) }.fetchAll(db)
        for var item in items where item.credits?.contains(where: { $0.contributor == contributorID }) == true {
            item.credits = item.credits?.map { credit in
                var credit = credit
                if credit.contributor == contributorID { credit.contributor = nil }
                return credit
            }
            try item.validateReferences()
            try ProgramItem.upsert { item }.execute(db)
        }
        let places = try EventPlace.where { $0.event.eq(eventID) }.fetchAll(db)
        for var place in places {
            guard case let .known(.stage(stageUse)) = place.kind,
                  stageUse.lineup?.contains(contributorID) == true
            else { continue }
            var stage = stageUse
            stage.lineup?.removeAll { $0 == contributorID }
            if stage.lineup?.isEmpty == true { stage.lineup = nil }
            place.kind = .known(.stage(stage))
            try place.validateReferences()
            try EventPlace.upsert { place }.execute(db)
        }
        try Contributor.find(contributorID).delete().execute(db)
    }
}
