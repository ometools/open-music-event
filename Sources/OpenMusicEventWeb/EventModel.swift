import Foundation

public enum EventViewerScheduleKind: String, CaseIterable, Equatable, Sendable {
    case singleStageAtOnce = "singleStageAtOnce"
    case allStagesAtOnceHorizontal = "allStagesAtOnce.horizontal"
    case allStagesAtOnceVertical = "allStagesAtOnce.vertical"
    case list

    public var title: String {
        switch self {
        case .singleStageAtOnce:
            return "Single Stage"
        case .allStagesAtOnceHorizontal:
            return "Many (H)"
        case .allStagesAtOnceVertical:
            return "Many (V)"
        case .list:
            return "List"
        }
    }

    public var webValue: String {
        switch self {
        case .singleStageAtOnce:
            return "single-stage"
        case .allStagesAtOnceHorizontal:
            return "many-horizontal"
        case .allStagesAtOnceVertical:
            return "many-vertical"
        case .list:
            return "list"
        }
    }

    /// The semantic icon role shared by native and browser schedule pickers.
    public var icon: EventViewerIcon {
        switch self {
        case .singleStageAtOnce:
            return .scheduleSingleStage
        case .allStagesAtOnceHorizontal:
            return .scheduleManyHorizontal
        case .allStagesAtOnceVertical:
            return .scheduleManyVertical
        case .list:
            return .list
        }
    }
}

public struct EventModel: Equatable, Sendable {
    public var schedulePerformances: [Performance] = []
    public var scheduleStages: [Performance] = []
    public var stagePerformances: [Performance] = []
    public var scheduleQuery: String = "feature=schedule"
    public var programChoices: [ViewerChoice] = []
    public var dayChoices: [ViewerChoice] = []
    public var mapChoices: [ViewerChoice] = []
    public var posts: [ViewerPost] = []
    public var categoryChoices: [ViewerChoice] = []
    public var name: String
    public var location: String
    public var heroImageURL: String?
    public var dateLine: String?
    public var scheduleLabel: String?
    public var timeZoneIdentifier: String?
    public var summary: String?
    public var status: String?
    public var mode: String?
    public var organizer: String?
    public var contacts: [EventContact]
    public var locations: [EventLocation]
    public var siteMapURL: String?
    public var posters: [EventPoster]
    public var channels: [EventChannel]
    public var alerts: [EventAlert]
    public var performances: [Performance]
    public var contributors: [Contributor]

    public init(
        name: String,
        location: String,
        heroImageURL: String? = nil,
        dateLine: String? = nil,
        scheduleLabel: String? = nil,
        timeZoneIdentifier: String? = nil,
        summary: String? = nil,
        status: String? = nil,
        mode: String? = nil,
        organizer: String? = nil,
        contacts: [EventContact] = [],
        locations: [EventLocation] = [],
        siteMapURL: String? = nil,
        posters: [EventPoster] = [],
        channels: [EventChannel] = [],
        alerts: [EventAlert] = [],
        contributors: [Contributor] = [],
        performances: [Performance]
    ) {
        self.name = name
        self.location = location
        self.heroImageURL = heroImageURL
        self.dateLine = dateLine
        self.scheduleLabel = scheduleLabel
        self.timeZoneIdentifier = timeZoneIdentifier
        self.summary = summary
        self.status = status
        self.mode = mode
        self.organizer = organizer
        self.contacts = contacts
        self.locations = locations
        self.siteMapURL = siteMapURL
        self.posters = posters
        self.channels = channels
        self.alerts = alerts
        self.performances = performances
        self.contributors = contributors
    }
}

public struct Performance: Equatable, Identifiable, Sendable {
    public var stageID: String = ""
    public var scheduleURL: String = "?feature=schedule"
    public var id: String
    public var title: String
    public var stage: String
    public var time: String
    public var endTime: String?
    public var startMinute: Int?
    public var endMinute: Int?
    public var stageColor: String?
    public var stageLogoURL: String?

    public init(
        id: String,
        title: String,
        stage: String,
        time: String,
        endTime: String? = nil,
        startMinute: Int? = nil,
        endMinute: Int? = nil,
        stageColor: String? = nil,
        stageLogoURL: String? = nil
    ) {
        self.id = id
        self.title = title
        self.stage = stage
        self.time = time
        self.endTime = endTime
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.stageColor = stageColor
        self.stageLogoURL = stageLogoURL
    }
}

public struct Contributor: Equatable, Identifiable, Sendable {
    public var links: [EventContact] = []
    public var id: String
    public var name: String
    public var role: String
    public var bio: String
    public var handle: String?
    public var avatarURL: String?
    public var accentColor: String
    public var performanceIDs: [String]

    public init(
        id: String,
        name: String,
        role: String,
        bio: String,
        handle: String? = nil,
        avatarURL: String? = nil,
        accentColor: String,
        performanceIDs: [String] = []
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.bio = bio
        self.handle = handle
        self.avatarURL = avatarURL
        self.accentColor = accentColor
        self.performanceIDs = performanceIDs
    }
}

public struct EventContact: Equatable, Identifiable, Sendable {
    public var id: String
    public var label: String
    public var value: String
    public var detail: String?
    public var href: String?

    public init(
        id: String,
        label: String,
        value: String,
        detail: String? = nil,
        href: String? = nil
    ) {
        self.id = id
        self.label = label
        self.value = value
        self.detail = detail
        self.href = href
    }
}

public struct EventLocation: Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var address: String
    public var detail: String?
    public var latitude: Double?
    public var longitude: Double?

    public init(
        id: String,
        name: String,
        address: String,
        detail: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.detail = detail
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct EventPoster: Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var imageURL: String?
    public var accentColor: String

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        imageURL: String? = nil,
        accentColor: String
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.imageURL = imageURL
        self.accentColor = accentColor
    }
}

public struct EventChannel: Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var kind: String
    public var summary: String
    public var latestUpdate: String?
    public var unreadCount: Int

    public init(
        id: String,
        name: String,
        kind: String,
        summary: String,
        latestUpdate: String? = nil,
        unreadCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.summary = summary
        self.latestUpdate = latestUpdate
        self.unreadCount = unreadCount
    }
}

public struct EventAlert: Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var body: String
    public var level: String
    public var updatedAt: String

    public init(
        id: String,
        title: String,
        body: String,
        level: String,
        updatedAt: String
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.level = level
        self.updatedAt = updatedAt
    }
}


public struct ViewerChoice: Equatable, Sendable {
    public var title: String
    public var url: String
    public var selected: Bool
    public init(title: String, url: String, selected: Bool) {
        self.title = title; self.url = url; self.selected = selected
    }
}
public struct ViewerPost: Equatable, Sendable {
    public var id: String
    public var title: String
    public var text: [ViewerText]
    public var images: [EventPoster]
    public var date: String
    public var pinned: Bool
    public var url: String
    public init(id: String, title: String, text: [ViewerText], images: [EventPoster], date: String, pinned: Bool, url: String) {
        self.id = id; self.title = title; self.text = text; self.images = images
        self.date = date; self.pinned = pinned; self.url = url
    }
}
public struct ViewerText: Equatable, Sendable {
    public var text: String
    public var url: String?
    public init(text: String, url: String? = nil) { self.text = text; self.url = url }
}
