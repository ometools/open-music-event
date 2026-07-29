import ATProto
import Foundation
import Lexicon
import LexiconSQLiteData
import OpenMusicEventTimeZones
import SQLiteData
import Tagged

// MARK: - Shared types

extension DID: SQLiteType {
    public static var typeAffinity: SQLiteTypeAffinity { .text }
}

public protocol TimelineRepresentable {
    var startTime: Date { get }
    var endTime: Date { get }
}

public struct OMEColor: Equatable, Codable, Sendable, ExpressibleByIntegerLiteral, RawRepresentable, SQLiteType {
    public var rawValue: Int

    public init(rawValue: Int) { self.rawValue = rawValue }
    public init(_ rawValue: Int) { self.rawValue = rawValue }
    public init(integerLiteral value: Int) { self.rawValue = value }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self.rawValue = value
            return
        }

        let string = try container.decode(String.self)
        let value: Int?
        if string.hasPrefix("0x") || string.hasPrefix("0X") {
            value = Int(string.dropFirst(2), radix: 16)
        } else {
            value = Int(string)
        }

        guard let value else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid OME color: \(string)"
            )
        }

        self.rawValue = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Namespace
// @Lexicon("openmusicevent.app")
public enum OpenMusicEvent {}
public typealias OME = OpenMusicEvent

// MARK: - Source (app.openmusicevent.source)

extension OpenMusicEvent {
    public struct SourceRecord: Codable, Equatable, Sendable {
        public static let nsid = ATProto.NSID("app.openmusicevent.source")
        public static let canonicalRecordKey = "canonical"

        public enum Kind: String, Codable, Equatable, Sendable {
            case tangled
        }

        public var kind: Kind
        public var reference: String
        public var ref: String?
        public var createdAt: String?

        public init(
            kind: Kind,
            reference: String,
            ref: String? = nil,
            createdAt: String? = nil
        ) {
            self.kind = kind
            self.reference = reference
            self.ref = ref
            self.createdAt = createdAt
        }

        enum CodingKeys: String, CodingKey {
            case type = "$type"
            case kind
            case reference
            case ref
            case createdAt
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.kind = try container.decode(Kind.self, forKey: .kind)
            self.reference = try container.decode(String.self, forKey: .reference)
            self.ref = try container.decodeIfPresent(String.self, forKey: .ref)
            self.createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(Self.nsid.rawValue, forKey: .type)
            try container.encode(kind.rawValue, forKey: .kind)
            try container.encode(reference, forKey: .reference)
            try container.encodeIfPresent(ref, forKey: .ref)
            try container.encodeIfPresent(createdAt, forKey: .createdAt)
        }
    }
}

// MARK: - Organizer  (app.openmusicevent.organizer)

extension OpenMusicEvent {
    @Table("organizers")
    public struct Organizer: Equatable, Sendable, Identifiable {
        public static let nsid = ATProto.NSID("app.openmusicevent.organizer")

        @Column(primaryKey: true)
        public var id: DID
    }
}

// MARK: - Event  (app.openmusicevent.event)

extension OpenMusicEvent {
    // The standard ID Types for records in OpenMusicEvent
    public typealias ID<T> = Tagged<T, ATProto.Record.Key>


    @Table("events")
    public struct Event: Equatable, Sendable, Identifiable {
        public static let nsid = ATProto.NSID("app.openmusicevent.event")

        @Selection public struct ID: Codable, Hashable, Sendable {
            public init(
                organizerID: OME.Organizer.ID,
                eventID: OME.ID<OME.Event>
            ) {
                self.organizerID = organizerID
                self.eventID = eventID
            }

            public var organizerID: OME.Organizer.ID
            public var eventID: OME.ID<OME.Event>
        }

        public var id: ID


        // community.lexicon.calendar.event superset
        public var name: String
        public var description: String?
        public var startDate: LocalDate?
        public var endDate: LocalDate?
        public var status: Open<Status>?

        public var mode: Open<Mode>?

        @Column(as: [OpenMusicEvent.Event.Location].JSONRepresentation?.self)
        public var locations: [OpenMusicEvent.Event.Location]?

        @Column(as: [OpenMusicEvent.Event.EventURI].JSONRepresentation?.self)
        public var uris: [OpenMusicEvent.Event.EventURI]?

        // ome-specific
        public var timeZone: TimeZone
        @Column(as: [OpenMusicEvent.ImageAsset].JSONRepresentation?.self)
        public var images: [OpenMusicEvent.ImageAsset]?

        @Column(as: [OpenMusicEvent.Event.ContactNumber].JSONRepresentation?.self)
        public var contactNumbers: [OpenMusicEvent.Event.ContactNumber]?

        @Column(as: OpenMusicEvent.Event.CategoryConfigs.JSONRepresentation?.self)
        public var categoryConfigs: OpenMusicEvent.Event.CategoryConfigs?

        @Column(as: OpenMusicEvent.Event.Policies.JSONRepresentation?.self)
        public var policies: OpenMusicEvent.Event.Policies?

        @Column(as: OpenMusicEvent.Event.ReportingLink.JSONRepresentation?.self)
        public var reportingLink: OpenMusicEvent.Event.ReportingLink?

        public var owner: OME.Contributor.Actor?
    }
}


extension OpenMusicEvent.Event {
    public enum Status: String, Codable, Sendable, Hashable, SQLiteType, OpenValue {
        case planned, scheduled, rescheduled, cancelled, postponed
    }

    public enum Mode: String, Codable, Sendable, Equatable, OpenValue, SQLiteType {
        case inPerson = "community.lexicon.calendar.event#inperson"
        case virtual  = "community.lexicon.calendar.event#virtual"
        case hybrid   = "community.lexicon.calendar.event#hybrid"
    }

    public struct Location: Codable, Sendable, Equatable {
        public init(
            address: String? = nil,
            directions: String? = nil,
            coordinates: Coordinates? = nil,
            appleMapsLink: URL? = nil,
            googleMapsLink: URL? = nil
        ) {
            self.address = address
            self.directions = directions
            self.coordinates = coordinates
            self.appleMapsLink = appleMapsLink
            self.googleMapsLink = googleMapsLink
        }

        public var address: String?
        public var directions: String?
        public var coordinates: Coordinates?
        public var appleMapsLink: URL?
        public var googleMapsLink: URL?

        public struct Coordinates: Codable, Sendable, Equatable {
            public init(latitude: Double, longitude: Double) {
                self.latitude = latitude
                self.longitude = longitude
            }

            public var latitude: Double
            public var longitude: Double
        }
    }

    public struct EventURI: Codable, Sendable, Equatable {
        public var uri: URL
        public var name: String?
    }

    public struct Reference: Codable, Sendable, Equatable {
        public init(uri: ATProto.URI, cid: ATProto.CID? = nil) {
            self.uri = uri
            self.cid = cid
        }

        public var uri: ATProto.URI
        public var cid: ATProto.CID?
    }

    public struct ContactNumber: Codable, Sendable, Equatable {
        public init(
            phoneNumber: String,
            title: String,
            description: String? = nil
        ) {
            self.phoneNumber = phoneNumber
            self.title = title
            self.description = description
        }

        public var phoneNumber: String
        public var title: String
        public var description: String?
    }

    public struct ReportingLink: Codable, Sendable, Equatable {
        public init(
            name: String,
            url: URL,
            description: String? = nil
        ) {
            self.name = name
            self.url = url
            self.description = description
        }

        public var name: String
        public var url: URL
        public var description: String?
    }

    public typealias CategoryConfigs = [OpenMusicEvent.Stage.Category: CategoryConfig]

    public struct CategoryConfig: Codable, Sendable, Equatable {
        public var showStageNameLabels: Bool
    }

    public static func reference(
        id: ID,
        cid: ATProto.CID? = nil
    ) -> Reference {
        Reference(
            uri: ATProto.URI(
                authority: .did(id.organizerID),
                collection: nsid,
                rkey: id.eventID.rawValue
            ),
            cid: cid
        )
    }
}

// MARK: - Calendar  (app.openmusicevent.calendar)

extension OpenMusicEvent {
    @Table("calendars")
    public struct Calendar: Equatable, Sendable, Identifiable {
        public static let nsid = ATProto.NSID("app.openmusicevent.calendar")
        public static let defaultID = OME.ID<OME.Calendar>(.init("self"))

        @Selection public struct ID: Codable, Hashable, Sendable {
            public init(
                ownerID: OME.Organizer.ID,
                calendarID: OME.ID<OME.Calendar>
            ) {
                self.ownerID = ownerID
                self.calendarID = calendarID
            }

            public var ownerID: OME.Organizer.ID
            public var calendarID: OME.ID<OME.Calendar>
        }

        public init(
            id: ID,
            name: String,
            description: String? = nil,
            images: [OpenMusicEvent.ImageAsset]? = nil
        ) {
            self.id = id
            self.name = name
            self.description = description
            self.images = images
        }

        public var id: ID
        public var name: String
        public var description: String?
        @Column(as: [OpenMusicEvent.ImageAsset].JSONRepresentation?.self)
        public var images: [OpenMusicEvent.ImageAsset]?
    }
}

// MARK: - CalendarEntry  (app.openmusicevent.calendar.entry)

extension OpenMusicEvent {
    @Table("calendarEntries")
    public struct CalendarEntry: Equatable, Sendable, Identifiable {
        public static let nsid = ATProto.NSID("app.openmusicevent.calendar.entry")

        @Selection public struct ID: Codable, Hashable, Sendable {
            public init(
                calendarOwnerID: OME.Organizer.ID,
                calendarID: OME.ID<OME.Calendar>,
                entryID: OME.ID<OME.CalendarEntry>
            ) {
                self.calendarOwnerID = calendarOwnerID
                self.calendarID = calendarID
                self.entryID = entryID
            }

            public var calendarOwnerID: OME.Organizer.ID
            public var calendarID: OME.ID<OME.Calendar>
            public var entryID: OME.ID<OME.CalendarEntry>
        }

        public init(
            id: ID,
            event: OpenMusicEvent.Event.Reference,
            createdAt: Date,
            note: String? = nil,
            pinned: Bool = false
        ) {
            self.id = id
            self.event = event
            self.createdAt = createdAt
            self.note = note
            self.pinned = pinned
        }

        public var id: ID

        @Column(as: OpenMusicEvent.Event.Reference.JSONRepresentation.self)
        public var event: OpenMusicEvent.Event.Reference
        public var createdAt: Date
        public var note: String?
        public var pinned: Bool
    }
}

// MARK: - EventOrganizer  (app.openmusicevent.event.organizer)

extension OpenMusicEvent {
    @Table("eventOrganizers")
    public struct EventOrganizer: Equatable, Sendable, Identifiable {
        public static let nsid = ATProto.NSID("app.openmusicevent.event.organizer")

        @Selection public struct ID: Codable, Hashable, Sendable {
            public init(
                organizerID: OME.Organizer.ID,
                eventID: OME.ID<OME.Event>,
                eventOrganizerID: OME.Organizer.ID
            ) {
                self.organizerID = organizerID
                self.eventID = eventID
                self.eventOrganizerID = eventOrganizerID
            }

            public var organizerID: OME.Organizer.ID
            public var eventID: OME.ID<OME.Event>
            public var eventOrganizerID: OME.Organizer.ID
        }

        public var id: ID

        public init(
            organizerID: OME.Organizer.ID,
            eventID: OME.ID<OME.Event>,
            eventOrganizerID: OME.Organizer.ID
        ) {
            self.id = ID(
                organizerID: organizerID,
                eventID: eventID,
                eventOrganizerID: eventOrganizerID
            )
        }
    }
}

// MARK: - Stage  (app.openmusicevent.stage)
//
extension OpenMusicEvent {
    @Table("stages")
    public struct Stage: Codable, Equatable, Sendable, Identifiable {
        public static let nsid = ATProto.NSID("app.openmusicevent.stage")
        public static let singletonID = OME.ID<OME.Stage>(.init("stage"))
        public static let singletonName = "Stage"
        public static let singletonColor: OMEColor = 0x336699

        @Selection public struct ID: Codable, Hashable, Sendable {
            public init(
                organizerID: OME.Organizer.ID,
                eventID: OME.ID<OME.Event>,
                stageID: OME.ID<OME.Stage>
            ) {
                self.organizerID = organizerID
                self.eventID = eventID
                self.stageID = stageID
            }

            public var organizerID: OME.Organizer.ID
            public var eventID: OME.ID<OME.Event>
            public var stageID: OME.ID<OME.Stage>
        }

        public var id: ID

        public var name: String
        public var color: OMEColor
        public var category: Category?
        public var sortIndex: Int?
        @Column(as: [OpenMusicEvent.ImageAsset].JSONRepresentation?.self)
        public var images: [OpenMusicEvent.ImageAsset]?
        public var systemIconName: String?
        public var iconShortCode: String?

        @Column(as: [OME.ID<OpenMusicEvent.Contributor>].JSONRepresentation?.self)
        public var lineup: [OME.ID<OpenMusicEvent.Contributor>]?
    }
}

extension OpenMusicEvent.Stage {
    public enum _CategoryTag {}
    public typealias Category = Tagged<_CategoryTag, String>
}

extension OpenMusicEvent.Stage {
    private enum CodingKeys: String, CodingKey {
        case id
        case organizerID
        case eventID
        case stageID
        case name
        case color
        case category
        case sortIndex
        case images
        case systemIconName
        case iconShortCode
        case lineup
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let id = try container.decodeIfPresent(ID.self, forKey: .id) {
            self.id = id
        } else {
            self.id = ID(
                organizerID: try container.decode(OME.Organizer.ID.self, forKey: .organizerID),
                eventID: try container.decode(OME.ID<OME.Event>.self, forKey: .eventID),
                stageID: try container.decode(OME.ID<OME.Stage>.self, forKey: .stageID)
            )
        }
        self.name = try container.decode(String.self, forKey: .name)
        self.color = try container.decode(OMEColor.self, forKey: .color)
        self.category = try container.decodeIfPresent(Category.self, forKey: .category)
        self.sortIndex = try container.decodeIfPresent(Int.self, forKey: .sortIndex)
        self.images = try container.decodeIfPresent([OpenMusicEvent.ImageAsset].self, forKey: .images)
        self.systemIconName = try container.decodeIfPresent(String.self, forKey: .systemIconName)
        self.iconShortCode = try container.decodeIfPresent(String.self, forKey: .iconShortCode)
        self.lineup = try container.decodeIfPresent([OME.ID<OpenMusicEvent.Contributor>].self, forKey: .lineup)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.organizerID, forKey: .organizerID)
        try container.encode(id.eventID, forKey: .eventID)
        try container.encode(id.stageID, forKey: .stageID)
        try container.encode(name, forKey: .name)
        try container.encode(color, forKey: .color)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encodeIfPresent(sortIndex, forKey: .sortIndex)
        try container.encodeIfPresent(images, forKey: .images)
        try container.encodeIfPresent(systemIconName, forKey: .systemIconName)
        try container.encodeIfPresent(iconShortCode, forKey: .iconShortCode)
        try container.encodeIfPresent(lineup, forKey: .lineup)
    }
}

// MARK: - Schedule  (app.openmusicevent.schedule)

extension OpenMusicEvent {
    @Table("schedules")
    public struct Schedule: Equatable, Sendable, Identifiable {
        public static let nsid = ATProto.NSID("app.openmusicevent.schedule")
        public static let singletonID = OME.ID<OME.Schedule>(.init("schedule"))

        @Selection public struct ID: Codable, Hashable, Sendable {
            public init(
                organizerID: OME.Organizer.ID,
                eventID: OME.ID<OME.Event>,
                scheduleID: OME.ID<OME.Schedule>
            ) {
                self.organizerID = organizerID
                self.eventID = eventID
                self.scheduleID = scheduleID
            }

            public var organizerID: OME.Organizer.ID
            public var eventID: OME.ID<OME.Event>
            public var scheduleID: OME.ID<OME.Schedule>
        }

        public var id: ID

        public var date: LocalDate
        public var startsAt: Date?
        public var endsAt: Date?
        public var customTitle: String?
    }
}

// MARK: - ScheduleItem

extension OpenMusicEvent {
    @Table("scheduleItems")
    public struct ScheduleItem: Equatable, Sendable, Identifiable, TimelineRepresentable {
        @Selection public struct ID: Codable, Hashable, Sendable {
            public init(
                organizerID: OME.Organizer.ID,
                eventID: OME.ID<OME.Event>,
                scheduleItemID: OME.ID<OME.ScheduleItem>
            ) {
                self.organizerID = organizerID
                self.eventID = eventID
                self.scheduleItemID = scheduleItemID
            }

            public var organizerID: OME.Organizer.ID
            public var eventID: OME.ID<OME.Event>
            public var scheduleItemID: OME.ID<OME.ScheduleItem>
        }

        public var id: ID
        public var stageID: OME.ID<OME.Stage>
        public var scheduleID: OME.ID<OME.Schedule>?
        public var kind: Open<Kind>
        public var startTime: Date
        public var endTime: Date
        public var title: String
        public var description: String?
    }
}

extension OpenMusicEvent.ScheduleItem {
    public enum Kind: String, Codable, Equatable, Hashable, Sendable, SQLiteType, OpenValue {
        case performance
    }

    @Table("scheduleItemPerformanceDetails")
    public struct PerformanceDetails: Equatable, Sendable, Identifiable {
        public var id: OME.ScheduleItem.ID

        @Column(as: [ExternalPlatform.Asset].JSONRepresentation.self)
        public var recordings: [ExternalPlatform.Asset]
    }

    @Table("scheduleItemContributors")
    public struct Contributor: Equatable, Sendable, Identifiable {
        @Selection public struct ID: Codable, Hashable, Sendable {
            public init(
                scheduleItemID: OME.ScheduleItem.ID,
                sortIndex: Int
            ) {
                self.organizerID = scheduleItemID.organizerID
                self.eventID = scheduleItemID.eventID
                self.scheduleItemID = scheduleItemID.scheduleItemID
                self.sortIndex = sortIndex
            }

            public var organizerID: OME.Organizer.ID
            public var eventID: OME.ID<OME.Event>
            public var scheduleItemID: OME.ID<OME.ScheduleItem>
            public var sortIndex: Int
        }

        public init(
            id: ID,
            contributorID: OME.ID<OME.Contributor>? = nil,
            anonymousName: String? = nil,
            contributorActor: OME.Contributor.Actor? = nil,
            billing: Billing = .primary,
            role: Role? = nil
        ) {
            self.id = id
            self.contributorID = contributorID
            self.anonymousName = anonymousName
            self.contributorActor = contributorActor
            self.billing = billing
            self.role = role
        }

        public var id: ID
        public var contributorID: OME.ID<OME.Contributor>?
        public var anonymousName: String?
        public var contributorActor: OME.Contributor.Actor?
        public var billing: Billing = .primary
        public var role: Role?
    }
}

extension OpenMusicEvent.ScheduleItem.Draft: Codable, Equatable, Sendable {}
extension OpenMusicEvent.ScheduleItem.PerformanceDetails.Draft: Codable, Equatable, Sendable {}
extension OpenMusicEvent.ScheduleItem.Contributor.Draft: Codable, Equatable, Sendable {}

extension OpenMusicEvent.ScheduleItem.Contributor {
    public enum Billing: String, Codable, Equatable, Hashable, Sendable, SQLiteType {
        case primary
        case supporting
    }

    public struct Role: Codable, Equatable, Hashable, Sendable, ExpressibleByStringLiteral, RawRepresentable, SQLiteType {
        public var type: String
        public var rawValue: String { type }
        public init(stringLiteral value: String) { self.type = value }
        public init(_ type: String) { self.type = type }
        public init(rawValue: String) { self.type = rawValue }
    }
}

// MARK: - Performance compatibility projection  (app.openmusicevent.performance)
extension OpenMusicEvent {
    @Table("performances")
    public struct Performance: Equatable, Sendable, Identifiable, TimelineRepresentable {
        public static let nsid = ATProto.NSID("app.openmusicevent.performance")

        @Selection public struct ID: Codable, Hashable, Sendable {
            public init(
                organizerID: OME.Organizer.ID,
                eventID: OME.ID<OME.Event>,
                performanceID: OME.ID<OME.Performance>
            ) {
                self.organizerID = organizerID
                self.eventID = eventID
                self.performanceID = performanceID
            }

            public var organizerID: OME.Organizer.ID
            public var eventID: OME.ID<OME.Event>
            public var performanceID: OME.ID<OME.Performance>
        }

        public var id: ID
        public var stageID: OME.ID<OME.Stage>
        public var scheduleID: OME.ID<OME.Schedule>?

        public var startTime: Date
        public var endTime: Date
        public var title: String
        public var description: String?

        @Column(as: [ExternalPlatform.Asset].JSONRepresentation.self)
        public var recordings: [ExternalPlatform.Asset]
    }
}

extension OpenMusicEvent.Performance {
    @Table("performanceContributors")
    public struct Contributors: Equatable, Sendable, Codable {
        public init(
            performanceID: OME.Performance.ID,
            contributorID: OME.ID<OME.Contributor>? = nil,
            anonymousName: String? = nil,
            contributorActor: OME.Contributor.Actor? = nil,
            billing: Billing = .primary,
            role: Role? = nil,
            sortIndex: Int = 0
        ) {
            self.performanceID = performanceID
            self.contributorID = contributorID
            self.anonymousName = anonymousName
            self.contributorActor = contributorActor
            self.billing = billing
            self.role = role
            self.sortIndex = sortIndex
        }

        public var performanceID: OME.Performance.ID
        public var contributorID: OME.ID<OME.Contributor>?
        public var anonymousName: String?
        public var contributorActor: OME.Contributor.Actor?
        public var billing: Billing
        public var role: Role?
        public var sortIndex: Int
    }
}

extension OpenMusicEvent.Performance.Contributors {
    public typealias Draft = Self
    public typealias Billing = OME.ScheduleItem.Contributor.Billing
    public typealias Role = OME.ScheduleItem.Contributor.Role
}

// MARK: - Contributor  (app.openmusicevent.contributor)

extension OpenMusicEvent {
    @Table("contributors")
    public struct Contributor: Equatable, Sendable, Identifiable {
        public static let nsid = ATProto.NSID("app.openmusicevent.contributor")

        @Selection public struct ID: Codable, Hashable, Sendable {
            public init(
                organizerID: OME.Organizer.ID,
                eventID: OME.ID<OME.Event>,
                contributorID: OME.ID<OME.Contributor>
            ) {
                self.organizerID = organizerID
                self.eventID = eventID
                self.contributorID = contributorID
            }

            public var organizerID: OME.Organizer.ID
            public var eventID: OME.ID<OME.Event>
            public var contributorID: OME.ID<OME.Contributor>
        }

        public var id: ID

        public var name: String
        public var did: DID? = nil
        public var bio: String?
        @Column(as: [OpenMusicEvent.ImageAsset].JSONRepresentation?.self)
        public var images: [OpenMusicEvent.ImageAsset]?

        @Column(as: [ExternalPlatform.Link].JSONRepresentation?.self)
        public var links: [ExternalPlatform.Link]?
    }
}

// MARK: - Contributor.Claim  (app.openmusicevent.contributor.claim)

extension OpenMusicEvent.Contributor {
    @Table("contributorClaims")
    public struct Claim: Equatable, Sendable, Identifiable {
        public static let nsid = ATProto.NSID("app.openmusicevent.contributor.claim")

        @Column(primaryKey: true) public var id: OME.ID<Self>
        public var contributorID: OpenMusicEvent.Contributor.ID
    }
}

// MARK: - Channel  (app.openmusicevent.channel)

extension OpenMusicEvent {
    @Table("channels")
    public struct Channel: Equatable, Sendable, Identifiable {
        public static let nsid = ATProto.NSID("app.openmusicevent.channel")

        @Selection public struct ID: Codable, Hashable, Sendable {
            public init(
                organizerID: OME.Organizer.ID,
                eventID: OME.ID<OME.Event>,
                channelID: OME.ID<OME.Channel>
            ) {
                self.organizerID = organizerID
                self.eventID = eventID
                self.channelID = channelID
            }

            public var organizerID: OME.Organizer.ID
            public var eventID: OME.ID<OME.Event>
            public var channelID: OME.ID<OME.Channel>
        }

        public var id: ID

        public var name: String
        public var description: String
        public var iconImageURL: URL?
        public var headerImageURL: URL?
        public var sortIndex: Int?
        public var defaultNotificationState: NotificationState
        public var notificationsRequired: Bool
    }
}

extension OpenMusicEvent.Channel {
    public enum NotificationState: String, Codable, Sendable, Equatable, CaseIterable, SQLiteType {
        case subscribed, unsubscribed
    }
}
// //// MARK: - Announcement  (app.openmusicevent.announcement)


//
//// MARK: - Poster  (app.openmusicevent.poster)
//
extension OpenMusicEvent {
    @Table("posters")
    public struct Poster: Equatable, Sendable, Identifiable {
        public static let nsid = ATProto.NSID("app.openmusicevent.poster")

        @Selection public struct ID: Codable, Hashable, Sendable {
            public init(
                organizerID: OME.Organizer.ID,
                eventID: OME.ID<OME.Event>,
                posterID: OME.ID<OME.Poster>
            ) {
                self.organizerID = organizerID
                self.eventID = eventID
                self.posterID = posterID
            }

            public var organizerID: OME.Organizer.ID
            public var eventID: OME.ID<OME.Event>
            public var posterID: OME.ID<OME.Poster>
        }

        public var id: ID

        public var title: String?
        @Column(as: OpenMusicEvent.ImageAsset.JSONRepresentation.self)
        public var image: OpenMusicEvent.ImageAsset
    }
}

extension OpenMusicEvent.Organizer.Draft: Codable, Equatable, Sendable {}
extension OpenMusicEvent.Event.Draft: Codable, Equatable, Sendable {}
extension OpenMusicEvent.Calendar.Draft: Codable, Equatable, Sendable {}
extension OpenMusicEvent.CalendarEntry.Draft: Codable, Equatable, Sendable {}
extension OpenMusicEvent.EventOrganizer.Draft: Equatable, Sendable {}
extension OpenMusicEvent.Stage.Draft: Codable, Equatable, Sendable {}
extension OpenMusicEvent.Schedule.Draft: Codable, Equatable, Sendable {}
extension OpenMusicEvent.Performance.Draft: Codable, Equatable, Sendable {}
extension OpenMusicEvent.Contributor.Draft: Codable, Equatable, Sendable {}
extension OpenMusicEvent.Poster.Draft: Codable, Equatable, Sendable {}
extension OpenMusicEvent.Channel.Draft: Codable, Equatable, Sendable {}
