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
//        public typealias ID = Tagged<Self, ATProto.Record.Key>

        @Column(primaryKey: true)
        public var id: OME.ID<Self>


        // community.lexicon.calendar.event superset
        public var name: String
        public var description: String?
        public var startsAt: Date?
        public var endsAt: Date?
        public var status: Status

        public var mode: Open<Mode>

        @Column(as: [Location].JSONRepresentation?.self)
        public var locations: [Location]?

        @Column(as: [EventURI].JSONRepresentation?.self)
        public var uris: [EventURI]?

        // ome-specific
        public var timeZone: TimeZone
        public var imageURL: URL?
        public var iconImageURL: URL?
        public var siteMapImageURL: URL?

        @Column(as: [ContactNumber].JSONRepresentation?.self)
        public var contactNumbers: [ContactNumber]?

        @Column(as: CategoryConfigs.JSONRepresentation?.self)
        public var categoryConfigs: CategoryConfigs?
    }
}


extension OpenMusicEvent.Event {
    public enum Status: String, Codable, Sendable, Equatable, SQLiteType {
        case planned, scheduled, rescheduled, cancelled, postponed
    }

    public enum Mode: String, Codable, Sendable, Equatable, SQLiteType {
        case inPerson = "community.lexicon.calendar.event#inperson"
        case virtual  = "community.lexicon.calendar.event#virtual"
        case hybrid   = "community.lexicon.calendar.event#hybrid"
    }

    public struct Location: Codable, Sendable, Equatable {
        public var address: String?
        public var directions: String?
        public var coordinates: Coordinates?
        public var appleMapsLink: URL?
        public var googleMapsLink: URL?

        public struct Coordinates: Codable, Sendable, Equatable {
            public var latitude: Double
            public var longitude: Double
        }
    }

    public struct EventURI: Codable, Sendable, Equatable {
        public var uri: URL
        public var name: String?
    }

    public struct ContactNumber: Codable, Sendable, Equatable {
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

        @Selection public struct ID: Hashable, Sendable {
            public var eventID: OME.Event.ID
            public var organizerID: OME.Organizer.ID
        }

        public var id: ID

        public init(eventID: OME.Event.ID, organizerID: OME.Organizer.ID) {
            self.id = ID(eventID: eventID, organizerID: organizerID)
        }
    }
}

// MARK: - Stage  (app.openmusicevent.stage)
//
extension OpenMusicEvent {
    @Table("stages")
    public struct Stage: Equatable, Sendable, Identifiable {
        public static let nsid = ATProto.NSID("app.openmusicevent.stage")

        @Column(primaryKey: true) public var id: OME.ID<Self>

        public var name: String
        public var color: OMEColor
        public var category: Category?
        public var sortIndex: Int?
        public var iconImageURL: URL?
        public var systemIconName: String?
        public var iconShortCode: String?
        public var imageURL: URL?
        public var posterImageURL: URL?

        @Column(as: [OpenMusicEvent.Participant.ID].JSONRepresentation?.self)
        public var lineup: [OpenMusicEvent.Participant.ID]?
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


        @Column(primaryKey: true) public var id: OME.ID<Self>
        public var eventID: OME.Event.ID

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

        @Column(primaryKey: true) public var id: OME.ID<Self>
        public var eventID: OME.Event.ID
        public var stageID: OME.Stage.ID
        public var scheduleID: OME.Schedule.ID?

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
        public var performanceID: OpenMusicEvent.Performance.ID
        public var participantID: OpenMusicEvent.Participant.ID?
        public var anonymousName: String?
    }
}

// MARK: - Participant  (app.openmusicevent.participant)

extension OpenMusicEvent {
    @Table("participants")
    public struct Participant: Equatable, Sendable, Identifiable {
        public static let nsid = ATProto.NSID("app.openmusicevent.participant")

        @Column(primaryKey: true) public var id: OME.ID<Self>

        public var name: String
        public var bio: String?
        public var imageURL: URL?
        public var logoURL: URL?
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

        @Column(primaryKey: true) public var id: OME.ID<Self>

        public var eventID: OME.Event.ID

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

        @Column(primaryKey: true) public var id: OME.ID<Self>
        public var eventID: OME.Event.ID

        public var title: String?
        public var imageURL: URL
    }
}
