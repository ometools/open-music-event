import ComposableNotifications
import Foundation
import OpenMusicEventAppEventViewer

public enum AppRoute: Equatable, NotificationRoute, Sendable {
    case event(OMERecord.Event.ID, EventTarget?)

    public init?(notificationRoute: String) {
        guard
            notificationRoute.hasPrefix("/"),
            let url = URL(string: notificationRoute),
            url.host == nil,
            url.scheme == nil
        else { return nil }
        self.init(url: url)
    }

    public init?(url: URL) {
        let segments = url.path.split(separator: "/").map(String.init)
        guard !segments.isEmpty else { return nil }

        if segments.count >= 4,
           segments[0] == "orgs",
           segments[2] == "events" {
            guard
                  let organizerID = OMERecord.Organizer.ID(segments[1].removingPercentEncoding ?? segments[1])
            else { return nil }
            let localEventID = OMERecord.ID<OMERecord.Event>(.init(segments[3]))
            let eventID = OMERecord.Event.ID(
                organizerID: organizerID,
                eventID: localEventID
            )
            let tail = Array(segments.dropFirst(4))

            if tail.isEmpty {
                self = .event(eventID, nil)
            } else if tail == ["schedule"] {
                self = .event(eventID, .schedule)
            } else if tail == ["contributors"] {
                self = .event(eventID, .contributors)
            } else if tail.count == 2, tail[0] == "contributors" {
                let contributorID = tail[1]
                self = .event(eventID, .contributor(.init(.init(contributorID))))
            } else if tail == ["stages"] {
                self = .event(eventID, .stages)
            } else if tail.count == 2, tail[0] == "stages" {
                let stageID = tail[1]
                self = .event(eventID, .stage(.init(.init(stageID))))
            } else if tail.count == 2, tail[0] == "performances" {
                let performanceID = tail[1]
                self = .event(eventID, .performance(.init(.init(performanceID))))
            } else if tail == ["communications"] {
                self = .event(eventID, .communications)
            } else if tail == ["contact-info"] {
                self = .event(eventID, .contactInfo)
            } else if tail == ["location"] {
                self = .event(eventID, .location)
            } else if tail == ["site-map"] {
                self = .event(eventID, .siteMap)
            } else if tail == ["posters"] {
                self = .event(eventID, .posters)
            } else if tail == ["notifications"] {
                self = .event(eventID, .notifications)
            } else if tail == ["settings"] {
                self = .event(eventID, .settings)
            } else if tail == ["search"] {
                self = .event(eventID, .search)
            } else if tail == ["about"] {
                self = .event(eventID, .about)
            } else if tail == ["workspace"] || tail == ["edit"] {
                self = .event(eventID, .workspace)
            } else {
                return nil
            }
        } else {
            return nil
        }
    }

    public var path: String {
        switch self {
        case let .event(eventID, target):
            let organizerID = eventID.organizerID.description.urlPathSegmentEncoded
            let localEventID = eventID.eventID.rawValue.rawValue
            let base = "/orgs/\(organizerID)/events/\(localEventID)"
            guard let target else { return base }

            switch target {
            case .schedule:
                return "\(base)/schedule"
            case .contributors:
                return "\(base)/contributors"
            case let .contributor(contributorID):
                return "\(base)/contributors/\(contributorID.rawValue.rawValue)"
            case .stages:
                return "\(base)/stages"
            case let .stage(stageID):
                return "\(base)/stages/\(stageID.rawValue.rawValue)"
            case let .performance(performanceID):
                return "\(base)/performances/\(performanceID.rawValue.rawValue)"
            case .communications:
                return "\(base)/communications"
            case .contactInfo:
                return "\(base)/contact-info"
            case .location:
                return "\(base)/location"
            case .siteMap:
                return "\(base)/site-map"
            case .posters:
                return "\(base)/posters"
            case .notifications:
                return "\(base)/notifications"
            case .settings:
                return "\(base)/settings"
            case .search:
                return "\(base)/search"
            case .about:
                return "\(base)/about"
            case .workspace:
                return "\(base)/workspace"
            }
        }
    }

    public var navigationRequest: NavigationRequest {
        switch self {
        case let .event(eventID, target):
            .event(eventID, target)
        }
    }

    public var notificationRoute: String {
        path
    }
}

private extension String {
    var urlPathSegmentEncoded: String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
