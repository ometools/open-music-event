import ComposableArchitecture2
import Foundation

public enum EventTarget: Equatable, Sendable {
    case schedule
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
    case edit
}

public struct NavigationRequested: FeatureEventKey {
    public init() {}
    public typealias Value = NavigationRequest
}

public enum NavigationRequest: Equatable, Sendable {
    case event(OMERecord.Event.ID, EventTarget?)
    case externalURL(URL)
}
