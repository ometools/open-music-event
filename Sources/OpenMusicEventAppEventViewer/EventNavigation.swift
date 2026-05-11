import ComposableArchitecture2
import Foundation

public enum EventTarget: Equatable, Sendable {
    case schedule
    case people
    case participant(OMERecord.ID<OMERecord.Participant>)
    case stage(OMERecord.ID<OMERecord.Stage>)
    case communications
    case contactInfo
    case location
    case siteMap
    case posters
    case notifications
    case search
    case about
    case edit

    public var eventFeature: EventViewer.EventFeature {
        switch self {
        case .schedule:
            .schedule
        case .people, .participant:
            .people
        case .stage, .search:
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
        case .about, .edit:
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
