import ComposableArchitecture2
import Foundation

public enum EventTarget: Equatable, Sendable {
    case schedule
    case people
    case participant(OMERecord.ID<OMERecord.Participant>)
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
    case edit

    public var eventFeature: EventViewer.EventFeature {
        switch self {
        case .schedule:
            .schedule(.schedule)
        case .people, .participant:
            .people
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

public struct NavigationRequested: FeatureEventKey {
    public init() {}
    public typealias Value = NavigationRequest
}

public enum NavigationRequest: Equatable, Sendable {
    case event(OMERecord.Event.ID, EventTarget?)
    case externalURL(URL)
}
