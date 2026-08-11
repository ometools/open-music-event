import ComposableNotifications
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventViewers

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
        guard
            segments.count >= 4,
            segments[0] == "orgs",
            segments[2] == "events",
            let organizerID = OMERecord.Organizer.ID(segments[1].decodedPathSegment)
        else { return nil }

        let localEventID = OMERecord.ID<OMERecord.Event>(.init(segments[3].decodedPathSegment))
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
            self = .event(
                eventID,
                .contributor(.init(.init(tail[1].decodedPathSegment)))
            )
        } else if tail == ["stages"] {
            self = .event(eventID, .stages)
        } else if tail.count == 2, tail[0] == "stages" {
            self = .event(
                eventID,
                .stage(.init(.init(tail[1].decodedPathSegment)))
            )
        } else if tail.count == 2, tail[0] == "performances" {
            self = .event(
                eventID,
                .performance(.init(.init(tail[1].decodedPathSegment)))
            )
        } else if tail == ["communications"] {
            self = .event(eventID, .communications)
        } else if tail.count == 2, tail[0] == "communications" {
            self = .event(
                eventID,
                .channel(.init(.init(tail[1].decodedPathSegment)))
            )
        } else if tail.count == 4,
                  tail[0] == "communications",
                  tail[2] == "posts" {
            self = .event(
                eventID,
                .post(
                    channelID: .init(.init(tail[1].decodedPathSegment)),
                    postID: CommsPost.PostID(tail[3].decodedPathSegment)
                )
            )
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
    }

    public var path: String {
        switch self {
        case let .event(eventID, target):
            let organizerID = eventID.organizerID.description.encodedPathSegment
            let localEventID = eventID.eventID.rawValue.rawValue.encodedPathSegment
            let base = "/orgs/\(organizerID)/events/\(localEventID)"
            guard let target else { return base }

            switch target {
            case .schedule:
                return "\(base)/schedule"
            case .contributors:
                return "\(base)/contributors"
            case let .contributor(contributorID):
                return "\(base)/contributors/\(contributorID.rawValue.rawValue.encodedPathSegment)"
            case .stages:
                return "\(base)/stages"
            case let .stage(stageID):
                return "\(base)/stages/\(stageID.rawValue.rawValue.encodedPathSegment)"
            case let .performance(performanceID):
                return "\(base)/performances/\(performanceID.rawValue.rawValue.encodedPathSegment)"
            case .communications:
                return "\(base)/communications"
            case let .channel(channelID):
                return "\(base)/communications/\(channelID.rawValue.rawValue.encodedPathSegment)"
            case let .post(channelID, postID):
                return "\(base)/communications/\(channelID.rawValue.rawValue.encodedPathSegment)/posts/\(postID.rawValue.encodedPathSegment)"
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
    var decodedPathSegment: String {
        removingPercentEncoding ?? self
    }

    var encodedPathSegment: String {
        let allowed = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        )
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
