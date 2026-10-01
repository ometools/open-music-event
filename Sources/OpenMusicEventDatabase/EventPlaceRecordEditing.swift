import ATProto
import ATProtoTypes
import Foundation
import OpenMusicEventLexicon
import SQLiteData

public enum EventPlaceRecordEditing {
    public enum Error: Swift.Error, Equatable {
        case eventUnavailable
        case placeUnavailable
        case placeInUse
    }

    public struct Fields: Equatable, Sendable {
        public var name: String
        public var description: String?
        public var locators: [Open<Event.Locator>]?
        public var links: [OME.Link]?
        public var media: [Open<OME.Media>]?
        public var kind: Open<EventPlace.Kind>?

        public init(
            name: String,
            description: String? = nil,
            locators: [Open<Event.Locator>]? = nil,
            links: [OME.Link]? = nil,
            media: [Open<OME.Media>]? = nil,
            kind: Open<EventPlace.Kind>? = nil
        ) {
            self.name = name
            self.description = description
            self.locators = locators
            self.links = links
            self.media = media
            self.kind = kind
        }

        public init(_ place: EventPlace) {
            self.init(
                name: place.name,
                description: place.description,
                locators: place.locators,
                links: place.links,
                media: place.media,
                kind: place.kind
            )
        }

        fileprivate func apply(to place: inout EventPlace) {
            place.name = name
            place.description = description
            place.locators = locators
            place.links = links
            place.media = media
            place.kind = kind
        }
    }

    public static func create(
        eventID: Event.ID,
        fields: Fields,
        createdAt: Date,
        in db: Database
    ) throws -> EventPlace.ID {
        guard try Event.find(eventID).fetchOne(db) != nil else {
            throw Error.eventUnavailable
        }
        let existing = try EventPlace.all.fetchAll(db)
            .filter { $0.id.authority == eventID.authority }
        let previousKey = existing.map(\.id).compactMap(\.rkey)
            .max { $0.rawValue < $1.rawValue }
        let id = try CanonicalRecordID.next(
            collection: EventPlace.lexiconID,
            in: eventID.authority,
            at: createdAt,
            after: previousKey
        )
        var place = try EventPlace(
            id: id,
            event: eventID,
            name: fields.name,
            createdAt: ATProto.DateTime(rawValue: ISO8601DateFormatter().string(from: createdAt))
        )
        fields.apply(to: &place)
        try place.validateReferences()
        try EventPlace.insert { place }.execute(db)
        return id
    }

    public static func update(
        _ placeID: EventPlace.ID,
        eventID: Event.ID,
        fields: Fields,
        in db: Database
    ) throws {
        guard try Event.find(eventID).fetchOne(db) != nil else {
            throw Error.eventUnavailable
        }
        guard var place = try EventPlace.find(placeID).fetchOne(db),
              place.event == eventID else {
            throw Error.placeUnavailable
        }
        fields.apply(to: &place)
        try place.validateReferences()
        try EventPlace.upsert { place }.execute(db)
    }

    public static func delete(
        _ placeID: EventPlace.ID,
        eventID: Event.ID,
        in db: Database
    ) throws {
        guard let place = try EventPlace.find(placeID).fetchOne(db),
              place.event == eventID else {
            throw Error.placeUnavailable
        }
        let items = try ProgramItem.where { $0.event.eq(eventID) }.fetchAll(db)
        guard !items.contains(where: { $0.eventPlace == placeID }) else {
            throw Error.placeInUse
        }
        let programs = try Program.where { $0.event.eq(eventID) }.fetchAll(db)
        for var program in programs where program.eventPlaces.contains(placeID) {
            program.eventPlaces.removeAll { $0 == placeID }
            try program.validateReferences()
            try Program.upsert { program }.execute(db)
        }
        try EventPlace.find(placeID).delete().execute(db)
    }
}
