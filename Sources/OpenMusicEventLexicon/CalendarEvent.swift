import ATProto
import Foundation
import XRPCClient

extension OpenMusicEvent {
    public struct CalendarEvent: Codable, Equatable, Identifiable, Sendable {
        public init(
            uri: ATProto.URI,
            cid: ATProto.CID? = nil,
            name: String,
            description: String? = nil,
            startsAt: Date? = nil,
            endsAt: Date? = nil,
            createdAt: Date? = nil,
            status: Status? = nil,
            mode: Mode? = nil,
            locations: [Location] = [],
            links: [Link] = [],
            media: [Media] = [],
            organizer: Organizer,
            attendance: Attendance = Attendance(),
            source: Source,
            timeZoneIdentifier: String? = nil,
            event: OpenMusicEvent.Event? = nil
        ) {
            self.uri = uri
            self.cid = cid
            self.name = name
            self.description = description
            self.startsAt = startsAt
            self.endsAt = endsAt
            self.createdAt = createdAt
            self.status = status
            self.mode = mode
            self.locations = locations
            self.links = links
            self.media = media
            self.organizer = organizer
            self.attendance = attendance
            self.source = source
            self.timeZoneIdentifier = timeZoneIdentifier
            self.event = event
        }

        public let uri: ATProto.URI
        public var cid: ATProto.CID?
        public var name: String
        public var description: String?
        public var startsAt: Date?
        public var endsAt: Date?
        public var createdAt: Date?
        public var status: Status?
        public var mode: Mode?
        public var locations: [Location]
        public var links: [Link]
        public var media: [Media]
        public var organizer: Organizer
        public var attendance: Attendance
        public var source: Source
        public var timeZoneIdentifier: String?
        public var event: OpenMusicEvent.Event?

        public var id: ATProto.URI { uri }
    }
}

public extension OpenMusicEvent.CalendarEvent {
    struct Attendance: Codable, Equatable, Sendable {
        public init(
            going: Int = 0,
            interested: Int = 0,
            notGoing: Int = 0
        ) {
            self.going = going
            self.interested = interested
            self.notGoing = notGoing
        }

        public var going: Int
        public var interested: Int
        public var notGoing: Int

        public var total: Int {
            going + interested + notGoing
        }
    }

    struct Link: Codable, Equatable, Sendable {
        public init(name: String? = nil, uri: URL, source: String? = nil) {
            self.name = name
            self.uri = uri
            self.source = source
        }

        public var name: String?
        public var uri: URL
        public var source: String?
    }

    struct Location: Codable, Equatable, Sendable {
        public init(
            name: String? = nil,
            street: String? = nil,
            locality: String? = nil,
            region: String? = nil,
            postalCode: String? = nil,
            country: String? = nil,
            latitude: String? = nil,
            longitude: String? = nil,
            source: String? = nil
        ) {
            self.name = name
            self.street = street
            self.locality = locality
            self.region = region
            self.postalCode = postalCode
            self.country = country
            self.latitude = latitude
            self.longitude = longitude
            self.source = source
        }

        public var name: String?
        public var street: String?
        public var locality: String?
        public var region: String?
        public var postalCode: String?
        public var country: String?
        public var latitude: String?
        public var longitude: String?
        public var source: String?

        public var summary: String? {
            if let name, !name.isEmpty { return name }
            let address = [street, locality, region, postalCode, country]
                .compactMap { value in
                    guard let value, !value.isEmpty else { return nil }
                    return value
                }
                .joined(separator: ", ")
            return address.isEmpty ? nil : address
        }
    }

    struct Media: Codable, Equatable, Sendable {
        public init(url: URL, alt: String? = nil, role: String? = nil) {
            self.url = url
            self.alt = alt
            self.role = role
        }

        public var url: URL
        public var alt: String?
        public var role: String?
    }

    enum Mode: Equatable, Hashable, Sendable {
        case hybrid
        case inPerson
        case virtual
        case unknown(String)
    }

    struct Organizer: Codable, Equatable, Hashable, Identifiable, Sendable {
        public init(
            id: DID,
            handle: String? = nil,
            displayName: String? = nil,
            description: String? = nil,
            avatarURL: URL? = nil
        ) {
            self.id = id
            self.handle = handle
            self.displayName = displayName
            self.description = description
            self.avatarURL = avatarURL
        }

        public let id: DID
        public var handle: String?
        public var displayName: String?
        public var description: String?
        public var avatarURL: URL?

        public var name: String {
            displayName ?? handle ?? id.description
        }
    }

    struct Page: Codable, Equatable, Sendable {
        public init(events: [OpenMusicEvent.CalendarEvent], cursor: String? = nil) {
            self.events = events
            self.cursor = cursor
        }

        public var events: [OpenMusicEvent.CalendarEvent]
        public var cursor: String?
    }

    struct Source: Codable, Equatable, Sendable {
        public init(
            collection: ATProto.NSID,
            appViewHost: ATProto.PDSHost? = nil,
            sourceRecord: OpenMusicEvent.SourceRecord? = nil
        ) {
            self.collection = collection
            self.appViewHost = appViewHost
            self.sourceRecord = sourceRecord
        }

        public var collection: ATProto.NSID
        public var appViewHost: ATProto.PDSHost?
        public var sourceRecord: OpenMusicEvent.SourceRecord?
    }

    enum Status: Equatable, Hashable, Sendable {
        case cancelled
        case planned
        case postponed
        case rescheduled
        case scheduled
        case unknown(String)
    }

    struct GetEvent: XRPC.Query, Sendable {
        public static let nsid = ATProto.NSID("app.openmusicevent.calendar.getEvent")

        public typealias Input = Never
        public typealias Output = OpenMusicEvent.CalendarEvent

        public init(uri: ATProto.URI) {
            self.parameters = Parameters(uri: uri)
        }

        public var parameters: Parameters

        public struct Parameters: Codable, Equatable, Sendable {
            public init(uri: ATProto.URI) {
                self.uri = uri
            }

            public var uri: ATProto.URI
        }
    }

    struct GetEvents: XRPC.Query, Sendable {
        public static let nsid = ATProto.NSID("app.openmusicevent.calendar.getEvents")

        public typealias Input = Never
        public typealias Output = OpenMusicEvent.CalendarEvent.Page

        public init(
            catalog: ATProto.NSID,
            cursor: String? = nil,
            limit: Int = 100
        ) {
            self.parameters = Parameters(
                catalog: catalog,
                cursor: cursor,
                limit: limit
            )
        }

        public var parameters: Parameters

        public struct Parameters: Codable, Equatable, Sendable {
            public init(
                catalog: ATProto.NSID,
                cursor: String? = nil,
                limit: Int = 100
            ) {
                self.catalog = catalog
                self.cursor = cursor
                self.limit = limit
            }

            public var catalog: ATProto.NSID
            public var cursor: String?
            public var limit: Int

            enum CodingKeys: String, CodingKey {
                case catalog
                case cursor
                case limit
            }

            public init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self.catalog = try container.decode(ATProto.NSID.self, forKey: .catalog)
                self.cursor = try container.decodeIfPresent(String.self, forKey: .cursor)
                self.limit = try container.decodeIfPresent(Int.self, forKey: .limit) ?? 100

                guard (1...100).contains(limit) else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .limit,
                        in: container,
                        debugDescription: "XRPC limit must be between 1 and 100."
                    )
                }
            }
        }
    }
}

extension OpenMusicEvent.CalendarEvent.Mode: Codable {
    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "community.lexicon.calendar.event#hybrid": self = .hybrid
        case "community.lexicon.calendar.event#inperson": self = .inPerson
        case "community.lexicon.calendar.event#virtual": self = .virtual
        default: self = .unknown(value)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        let value = switch self {
        case .hybrid: "community.lexicon.calendar.event#hybrid"
        case .inPerson: "community.lexicon.calendar.event#inperson"
        case .virtual: "community.lexicon.calendar.event#virtual"
        case let .unknown(value): value
        }
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

extension OpenMusicEvent.CalendarEvent.Status: Codable {
    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "community.lexicon.calendar.event#cancelled": self = .cancelled
        case "community.lexicon.calendar.event#planned": self = .planned
        case "community.lexicon.calendar.event#postponed": self = .postponed
        case "community.lexicon.calendar.event#rescheduled": self = .rescheduled
        case "community.lexicon.calendar.event#scheduled": self = .scheduled
        default: self = .unknown(value)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        let value = switch self {
        case .cancelled: "community.lexicon.calendar.event#cancelled"
        case .planned: "community.lexicon.calendar.event#planned"
        case .postponed: "community.lexicon.calendar.event#postponed"
        case .rescheduled: "community.lexicon.calendar.event#rescheduled"
        case .scheduled: "community.lexicon.calendar.event#scheduled"
        case let .unknown(value): value
        }
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
