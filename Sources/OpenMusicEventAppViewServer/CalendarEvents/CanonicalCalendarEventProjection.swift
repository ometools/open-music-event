import ATProto
import ATProtoAppView
import ATProtoTypes
import Foundation
import GRDB
import OpenMusicEventLexicon
import SQLiteData

typealias CanonicalEvent = OpenMusicEventLexicon.Event

extension CalendarEventBrowseProjection {
    static func upsertCanonicalEvent(
        id: CanonicalEvent.ID,
        deleteExistingSearchDocument: Bool = true,
        in database: Database
    ) throws {
        guard let event = try CanonicalEvent.find(id).fetchOne(database) else {
            try delete(uri: id.description, in: database)
            return
        }
        let places = try EventPlace.where { $0.event.eq(id) }.fetchAll(database)
        let contributors = try Contributor.where { $0.event.eq(id) }.fetchAll(database)
        let items = try ProgramItem.where { $0.event.eq(id) }.fetchAll(database)
        let profile = try VenueProfileProjection.find(id.authority.description).fetchOne(database)
        let calendarEvent = try OME.CalendarEvent(
            event: event,
            profile: profile
        )
        let searchText = contributors.map(\.name)
            + places.flatMap { [$0.name, $0.description].compactMap { $0 } }
            + items.flatMap { item in
                [item.title, item.description].compactMap { $0 }
                    + (item.credits ?? []).map(\.name)
            }
        try upsert(
            calendarEvent,
            hasEventViewer: event.projectionVersion == nil && event.id.collection?.rawValue == CanonicalEvent.lexiconID.rawValue && event.hasDetailsBeyondBrowse,
            searchText: searchText.joined(separator: " "),
            sourceID: event.projectionVersion == nil ? "venue:\(id.authority.description)" : nil,
            deleteExistingSearchDocument: deleteExistingSearchDocument,
            in: database
        )
    }
}

@Table("venueProfileProjections")
struct VenueProfileProjection: Codable, Equatable, Sendable {
    @Column(primaryKey: true) var did: String
    var displayName: String?
    var description: String?
    var avatarCID: String?

    static func registerMigration(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("Create venue actor profile projections") { database in
            try #sql(
                """
                CREATE TABLE \(quote: Self.tableName) (
                  "did" TEXT PRIMARY KEY NOT NULL,
                  "displayName" TEXT,
                  "description" TEXT,
                  "avatarCID" TEXT
                ) STRICT
                """
            )
            .execute(database)
        }
    }
}

extension OpenMusicEventAppViewStore {
    func venueActorProfileRecordIndex() -> AppViewRecordIndex<Data> {
        AppViewRecordIndex<Data>(
            collection: ATProto.NSID("app.bsky.actor.profile"),
            decode: { $0 }
        )
        .project { mutation, database in
            let did: String
            switch mutation {
            case let .create(current), let .update(_, current):
                did = current.uri.authority.description
                let profile = try JSONDecoder().decode(VenueActorProfileRecord.self, from: current.value)
                try VenueProfileProjection.upsert {
                    VenueProfileProjection(
                        did: did,
                        displayName: profile.displayName,
                        description: profile.description,
                        avatarCID: profile.avatar?.ref.rawValue
                    )
                }
                .execute(database)
            case let .delete(_, current):
                did = current.uri.authority.description
                try VenueProfileProjection.find(did).delete().execute(database)
            }
            for event in try CanonicalEvent.all.fetchAll(database)
            where event.id.authority.description == did {
                try CalendarEventBrowseProjection.upsertCanonicalEvent(
                    id: event.id,
                    in: database
                )
            }
        }
    }

    func containsVenueProfileBlob(did: String, cid: String) throws -> Bool {
        try database.read { database in
            try VenueProfileProjection.find(did)
                .where { $0.avatarCID.eq(cid) }
                .fetchOne(database) != nil
        }
    }
}

private struct VenueActorProfileRecord: Decodable {
    var displayName: String?
    var description: String?
    var avatar: ATProto.Blob?
}

extension OME.CalendarEvent {
    init(
        event: CanonicalEvent,
        profile: VenueProfileProjection?
    ) throws {
        guard case let .did(organizerID) = event.id.authority else {
            throw CanonicalCalendarEventProjectionError.invalidOrganizer(event.id.description)
        }
        let locations = (event.locations ?? []).map(OME.CalendarEvent.Location.init)
        self.init(
            uri: event.id,
            cid: event.cid,
            name: event.name,
            description: event.description,
            startsAt: event.start?.date(in: event.timeZone),
            endsAt: event.end?.date(in: event.timeZone),
            createdAt: Self.date(event.createdAt),
            status: event.status.map(Self.status),
            mode: event.mode.map(Self.mode),
            locations: locations,
            links: (event.links ?? []).map {
                OME.CalendarEvent.Link(name: $0.title, uri: $0.url)
            },
            media: (event.media ?? []).compactMap {
                guard case let .known(media) = $0 else { return nil }
                return Self.media(media, record: event.id)
            },
            organizer: Organizer(
                id: organizerID,
                displayName: profile?.displayName,
                description: profile?.description,
                avatarURL: profile?.avatarCID.flatMap {
                    Self.profileMediaURL(did: organizerID.description, cid: $0)
                }
            ),
            source: Source(collection: event.id.collection!),
            timeZoneIdentifier: event.timeZone?.identifier
        )
    }

    static func date(_ value: ATProto.DateTime) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value.rawValue) { return date }
        let wholeSeconds = ISO8601DateFormatter()
        wholeSeconds.formatOptions = [.withInternetDateTime]
        return wholeSeconds.date(from: value.rawValue)
    }

    static func status(_ value: Open<CanonicalEvent.Status>) -> Status {
        let rawValue = switch value {
        case let .known(status): status.rawValue
        case let .unknown(value): value.string ?? "unknown"
        }
        return switch rawValue {
        case CanonicalEvent.Status.cancelled.rawValue: .cancelled
        case CanonicalEvent.Status.planned.rawValue: .planned
        case CanonicalEvent.Status.postponed.rawValue: .postponed
        case CanonicalEvent.Status.rescheduled.rawValue: .rescheduled
        case CanonicalEvent.Status.scheduled.rawValue: .scheduled
        default: .unknown(rawValue)
        }
    }

    static func mode(_ value: Open<CanonicalEvent.Mode>) -> Mode {
        let rawValue = switch value {
        case let .known(mode): mode.rawValue
        case let .unknown(value): value.string ?? "unknown"
        }
        return switch rawValue {
        case CanonicalEvent.Mode.hybrid.rawValue: .hybrid
        case CanonicalEvent.Mode.inPerson.rawValue: .inPerson
        case CanonicalEvent.Mode.virtual.rawValue: .virtual
        default: .unknown(rawValue)
        }
    }

    static func media(_ media: OME.Media, record: ATProto.URI) -> Media? {
        guard case let .image(image) = media else { return nil }
        let url: URL
        switch image.source {
        case let .known(.url(value)):
            url = value
        case let .known(.blob(blob)):
            guard let value = recordMediaURL(record: record, cid: blob.ref.rawValue) else {
                return nil
            }
            url = value
        case .unknown:
            return nil
        }
        let role: String? = switch image.role {
        case let .known(role): role.rawValue
        case let .unknown(value): value.string
        case nil: nil
        }
        let renderKind: OME.ImageAsset.RenderKind? = switch image.renderingMode {
        case .known(.template): .transparent
        case .known(.original): .fullImage
        case .unknown: nil
        }
        return Media(
            url: url,
            alt: image.alt?.rawValue,
            role: role,
            renderKind: renderKind
        )
    }

    static func recordMediaURL(record: ATProto.URI, cid: String) -> URL? {
        var components = URLComponents()
        components.path = "/event-media"
        components.queryItems = [
            URLQueryItem(name: "record", value: record.description),
            URLQueryItem(name: "cid", value: cid),
        ]
        return components.url
    }

    static func profileMediaURL(did: String, cid: String) -> URL? {
        var components = URLComponents()
        components.path = "/profile-media"
        components.queryItems = [
            URLQueryItem(name: "did", value: did),
            URLQueryItem(name: "cid", value: cid),
        ]
        return components.url
    }
}

private extension OME.CalendarEvent.Location {
    init(_ location: CanonicalEvent.Location) {
        self.init(name: location.name)
        apply(location.locators)
    }

    init(_ place: EventPlace) {
        self.init(name: place.name)
        apply(place.locators)
    }

    mutating func apply(_ locators: [Open<CanonicalEvent.Locator>]?) {
        for locator in locators ?? [] {
            switch locator {
            case let .known(.address(address)):
                name = address.name ?? name
                street = address.street
                locality = address.locality
                region = address.region
                postalCode = address.postalCode
                country = address.country
            case let .known(.geo(geo)):
                name = geo.name ?? name
                latitude = geo.latitude
                longitude = geo.longitude
            case let .known(.foursquare(foursquare)):
                name = foursquare.name ?? name
                latitude = foursquare.latitude ?? latitude
                longitude = foursquare.longitude ?? longitude
                source = foursquare.fsqPlaceID
            case let .known(.hthree(hthree)):
                name = hthree.name ?? name
                source = hthree.value
            case .unknown:
                continue
            }
        }
    }
}

private enum CanonicalCalendarEventProjectionError: Error {
    case invalidOrganizer(String)
}
