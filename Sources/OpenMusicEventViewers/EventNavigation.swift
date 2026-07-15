import ComposableArchitecture2
import Foundation

public enum EventTarget: Equatable, Sendable {
    case schedule
    case performance(OMERecord.ID<OMERecord.Performance>)
    case contributors
    case contributor(OMERecord.ID<OMERecord.Contributor>)
    case stages
    case stage(OMERecord.ID<OMERecord.Stage>)
    case communications
    case contactInfo
    case location
    case siteMap
    case posters
    case notifications
    case settings
    case search
    case about
    case workspace
}

public struct NavigationRequested: FeatureEventKey {
    public init() {}
    public typealias Value = NavigationRequest
}

public enum NavigationRequest: Equatable, Sendable {
    case event(OMERecord.Event.ID, EventTarget?)
    case externalURL(URL)
}

extension EventTarget {
    public var eventFeature: EventFeature {
        switch self {
        case .schedule:
            .schedule(.schedule)
        case .performance:
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
        case .workspace:
            .workspace
        case .about:
            .about
        }
    }
}
