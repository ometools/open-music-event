public enum EventViewerIcon: String, CaseIterable, Equatable, Sendable {
    case schedule
    case heart
    case thumbsUp = "thumbs-up"
    case personDoingYoga = "person-doing-yoga"
    case speechBubbles = "speech-bubbles"
    case gridOfSquares = "grid-of-squares"
    case contributors
    case stages
    case communications
    case contactInfo = "contact-info"
    case location
    case siteMap = "site-map"
    case posters
    case notifications
    case settings
    case workspace
    case search
    case about
    case contributor
    case performance
    case scheduleSingleStage = "schedule-single-stage"
    case scheduleManyHorizontal = "schedule-many-horizontal"
    case scheduleManyVertical = "schedule-many-vertical"
    case list
    case more

    public init(programSemanticName: String?) {
        switch programSemanticName {
        case "heart": self = .heart
        case "thumbsUp": self = .thumbsUp
        case "personDoingYoga": self = .personDoingYoga
        case "speechBubbles": self = .speechBubbles
        case "gridOfSquares": self = .gridOfSquares
        default: self = .schedule
        }
    }
}

public enum EventViewerFeature: String, CaseIterable, Equatable, Sendable {
    case schedule
    case contributors
    case stages
    case communications
    case contactInfo
    case location
    case siteMap
    case posters
    case notifications
    case settings
    case workspace
    case search
    case about

    public var webValue: String {
        switch self {
        case .contactInfo:
            return "contact-info"
        case .siteMap:
            return "site-map"
        default:
            return rawValue
        }
    }

    public var title: String {
        switch self {
        case .schedule:
            return "Schedule"
        case .contributors:
            return "Contributors"
        case .stages:
            return "Places"
        case .communications:
            return "Comms"
        case .contactInfo:
            return "Contact"
        case .location:
            return "Location"
        case .siteMap:
            return "Site Map"
        case .posters:
            return "Posters"
        case .notifications:
            return "Alerts"
        case .settings:
            return "Settings"
        case .workspace:
            return "Workspace"
        case .search:
            return "Search"
        case .about:
            return "About"
        }
    }

    public var icon: EventViewerIcon {
        switch self {
        case .schedule:
            return .schedule
        case .contributors:
            return .contributors
        case .stages:
            return .stages
        case .communications:
            return .communications
        case .contactInfo:
            return .contactInfo
        case .location:
            return .location
        case .siteMap:
            return .siteMap
        case .posters:
            return .posters
        case .notifications:
            return .notifications
        case .settings:
            return .settings
        case .workspace:
            return .workspace
        case .search:
            return .search
        case .about:
            return .about
        }
    }

    public static var browse: [Self] {
        [.contributors, .stages, .search]
    }

    public static var event: [Self] {
        [.contactInfo, .location, .siteMap, .posters]
    }

    public static var more: [Self] {
        [.contributors, .stages, .contactInfo, .location, .siteMap, .posters, .about]
    }
}
