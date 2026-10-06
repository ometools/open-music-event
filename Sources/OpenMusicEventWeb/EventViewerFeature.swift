public enum EventViewerIcon: String, CaseIterable, Equatable, Sendable {
    case schedule
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

    /// The native OME/iOS symbol used as the source for the platform asset.
    public var nativeSystemImage: String {
        switch self {
        case .schedule:
            return "calendar"
        case .contributors:
            return "person.3"
        case .stages:
            return "square.grid.2x2"
        case .communications:
            return "megaphone"
        case .contactInfo:
            return "phone"
        case .location:
            return "mappin.and.ellipse"
        case .siteMap:
            return "map"
        case .posters:
            return "photo.on.rectangle"
        case .notifications:
            return "bell"
        case .settings:
            return "gearshape"
        case .workspace:
            return "tray.full"
        case .search:
            return "magnifyingglass"
        case .about:
            return "info.circle"
        case .contributor:
            return "person"
        case .performance:
            return "music.mic"
        case .scheduleSingleStage:
            return "calendar.day.timeline.leading"
        case .scheduleManyHorizontal:
            return "rectangle.split.1x2"
        case .scheduleManyVertical:
            return "rectangle.split.3x1"
        case .list:
            return "list.bullet"
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
            return "Stages"
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

    /// The semantic icon role shared by native and browser renderers.
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

    public var isPrimary: Bool {
        switch self {
        case .schedule, .contributors, .stages, .search:
            return true
        default:
            return false
        }
    }

    public static var primary: [Self] {
        [.schedule, .contributors, .stages, .search]
    }

    public static var event: [Self] {
        [.communications, .contactInfo, .location, .siteMap, .posters, .notifications]
    }

    public static var account: [Self] {
        [.settings, .workspace, .about]
    }
}
