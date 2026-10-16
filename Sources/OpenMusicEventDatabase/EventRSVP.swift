import ATProto
import ATProtoSQLite
import Foundation
import SQLiteData

/// A device-local RSVP. Its identity is the event's durable AT URI plus the
/// currently selected account, or the one stable logged-out consumer.
@Table("app.openmusicevent.rsvp")
public struct EventRSVP: Equatable, Identifiable, Sendable {
    public enum Status: String, Codable, Equatable, Sendable, SQLiteType {
        case interested = "app.openmusicevent.rsvp#interested"
        case going = "app.openmusicevent.rsvp#going"
        case notGoing = "app.openmusicevent.rsvp#notgoing"
    }

    public init(
        eventURI: ATProto.URI,
        eventCID: ATProto.CID? = nil,
        consumer: Consumer,
        status: Status,
        createdAt: Date
    ) {
        self.id = ID(eventURI: eventURI, consumer: consumer)
        self.eventCID = eventCID
        self.status = status
        self.createdAt = createdAt
    }

    @Selection
    public struct ID: Codable, Equatable, Hashable, Sendable {
        public init(eventURI: ATProto.URI, consumer: EventRSVP.Consumer) {
            self.eventURI = eventURI
            self.consumer = consumer
        }

        public var eventURI: ATProto.URI
        public var consumer: EventRSVP.Consumer
    }

    public var id: ID
    public var eventCID: ATProto.CID?
    public var status: Status
    public var createdAt: Date

    public struct Consumer: Codable, Equatable, Hashable, RawRepresentable, Sendable, SQLiteType {
        public static let loggedOut = Self(rawValue: "")!

        public init?(rawValue: String) {
            if rawValue.isEmpty {
                accountDID = nil
            } else if let did = DID(rawValue) {
                accountDID = did
            } else {
                return nil
            }
        }

        public init(accountDID: DID?) {
            self.accountDID = accountDID
        }

        public var accountDID: DID?

        public var rawValue: String {
            accountDID?.description ?? ""
        }
    }

    public static func forEvent(
        _ eventURI: ATProto.URI,
        consumer: Consumer
    ) -> some SelectStatementOf<Self> {
        Self.find(ID(eventURI: eventURI, consumer: consumer))
    }

    public static func save(
        eventURI: ATProto.URI,
        eventCID: ATProto.CID?,
        consumer: Consumer,
        status: Status,
        createdAt: Date,
        in database: Database
    ) throws {
        try Self.upsert {
            Self(
                eventURI: eventURI,
                eventCID: eventCID,
                consumer: consumer,
                status: status,
                createdAt: createdAt
            )
        }
        .execute(database)
    }
}
