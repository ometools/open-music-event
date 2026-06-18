import OpenMusicEventViewers

extension EventTarget {
    public var eventFeature: EventViewer.EventFeature {
        switch self {
        case .schedule:
            .schedule(.schedule)
        case .contributors, .contributor:
            .contributors
        case .stages, .stage:
            .stages
        case .search:
            .search
        case .communications:
            .communications
        case .contactInfo:
            .contactInfo
        case .location:
            .location
        case .siteMap:
            .siteMap
        case .posters:
            .posters
        case .notifications:
            .notifications
        case .settings:
            .settings
        case .edit:
            .edit
        case .about:
            .about
        }
    }
}
