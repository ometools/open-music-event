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

        @Column(as: [Location].JSONRepresentation?.self)
        public var locations: [Location]?

        @Column(as: [EventURI].JSONRepresentation?.self)
        public var uris: [EventURI]?

        // ome-specific
        public var timeZone: TimeZone
        @Column(as: [OpenMusicEvent.ImageAsset].JSONRepresentation?.self)
        public var images: [OpenMusicEvent.ImageAsset]?

        @Column(as: [ContactNumber].JSONRepresentation?.self)
        public var contactNumbers: [ContactNumber]?

        @Column(as: CategoryConfigs.JSONRepresentation?.self)
        public var categoryConfigs: CategoryConfigs?
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

    public typealias CategoryConfigs = [OpenMusicEvent.Stage.Category: CategoryConfig]

    public struct CategoryConfig: Codable, Sendable, Equatable {
        public var showStageNameLabels: Bool
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
    public struct Stage: Equatable, Sendable, Identifiable {
        public static let nsid = ATProto.NSID("app.openmusicevent.stage")

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

        @Column(as: [OME.ID<OpenMusicEvent.Participant>].JSONRepresentation?.self)
        public var lineup: [OME.ID<OpenMusicEvent.Participant>]?
    }
}

extension OpenMusicEvent.Stage {
    public enum _CategoryTag {}
    public typealias Category = Tagged<_CategoryTag, String>
}

// MARK: - Schedule  (app.openmusicevent.schedule)

extension OpenMusicEvent {
    @Table("schedules")
    public struct Schedule: Equatable, Sendable, Identifiable {
        public static let nsid = ATProto.NSID("app.openmusicevent.schedule")

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

// MARK: - Performance  (app.openmusicevent.performance)
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
    @Table("performanceParticipants")
    public struct Participants: Equatable, Sendable, Codable {
        public init(
            organizerID: OME.Organizer.ID,
            eventID: OME.ID<OME.Event>,
            performanceID: OME.ID<OME.Performance>,
            participantID: OME.ID<OME.Participant>? = nil,
            anonymousName: String? = nil
        ) {
            self.organizerID = organizerID
            self.eventID = eventID
            self.performanceID = performanceID
            self.participantID = participantID
            self.anonymousName = anonymousName
        }

        public var organizerID: OME.Organizer.ID
        public var eventID: OME.ID<OME.Event>
        public var performanceID: OME.ID<OME.Performance>
        public var participantID: OME.ID<OME.Participant>?
        public var anonymousName: String?
    }
}

extension OpenMusicEvent.Performance.Participants {
    public typealias Draft = Self
}

// MARK: - Participant  (app.openmusicevent.participant)

extension OpenMusicEvent {
    @Table("participants")
    public struct Participant: Equatable, Sendable, Identifiable {
        public static let nsid = ATProto.NSID("app.openmusicevent.participant")

        @Selection public struct ID: Codable, Hashable, Sendable {
            public init(
                organizerID: OME.Organizer.ID,
                eventID: OME.ID<OME.Event>,
                participantID: OME.ID<OME.Participant>
            ) {
                self.organizerID = organizerID
                self.eventID = eventID
                self.participantID = participantID
            }

            public var organizerID: OME.Organizer.ID
            public var eventID: OME.ID<OME.Event>
            public var participantID: OME.ID<OME.Participant>
        }

        public var id: ID

        public var name: String
        public var bio: String?
        @Column(as: [OpenMusicEvent.ImageAsset].JSONRepresentation?.self)
        public var images: [OpenMusicEvent.ImageAsset]?
        public var kind: Kind?

//        public var participantDID: DID?

        @Column(as: [ExternalPlatform.Link].JSONRepresentation?.self)
        public var links: [ExternalPlatform.Link]?
    }
}

extension OpenMusicEvent.Participant {
    public struct Kind: Codable, Sendable, Equatable, ExpressibleByStringLiteral, RawRepresentable, SQLiteType {
        public var type: String
        public var rawValue: String { type }
        public init(stringLiteral value: String) { self.type = value }
        public init(_ type: String) { self.type = type }
        public init(rawValue: String) { self.type = rawValue }
    }
}

// MARK: - Participant.Claim  (app.openmusicevent.participant.claim)

extension OpenMusicEvent.Participant {
    @Table("participantClaims")
    public struct Claim: Equatable, Sendable, Identifiable {
        public static let nsid = ATProto.NSID("app.openmusicevent.participant.claim")

        @Column(primaryKey: true) public var id: OME.ID<Self>
        public var participantID: OpenMusicEvent.Participant.ID
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
extension OpenMusicEvent.EventOrganizer.Draft: Equatable, Sendable {}
extension OpenMusicEvent.Stage.Draft: Codable, Equatable, Sendable {}
extension OpenMusicEvent.Schedule.Draft: Codable, Equatable, Sendable {}
extension OpenMusicEvent.Performance.Draft: Codable, Equatable, Sendable {}
extension OpenMusicEvent.Participant.Draft: Codable, Equatable, Sendable {}
extension OpenMusicEvent.Poster.Draft: Codable, Equatable, Sendable {}
extension OpenMusicEvent.Channel.Draft: Codable, Equatable, Sendable {}
