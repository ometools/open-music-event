import ComposableNotifications
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventRouting
import OpenMusicEventViewers

public enum AppRoute: Equatable, NotificationRoute, Sendable {
    case event(Event.ID, EventTarget?)

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
        if let route = openMusicEventEventPathRouter.parse(url.path(percentEncoded: true)) {
            self.init(
                eventID: route.eventID,
                tail: route.tail
            )
            return
        }

        return nil
    }

    private init?(eventID: Event.ID, tail: [String]) {
        if tail.isEmpty {
            self = .event(eventID, nil)
        } else if tail == ["schedule"] {
            self = .event(eventID, .schedule)
        } else if tail == ["contributors"] {
            self = .event(eventID, .contributors)
        } else if tail.count == 2, tail[0] == "contributors",
                  let contributorID = Contributor.ID(tail[1].decodedPathSegment) {
            self = .event(
                eventID,
                .contributor(contributorID)
            )
        } else if tail == ["stages"] {
            self = .event(eventID, .stages)
        } else if tail.count == 2, tail[0] == "stages",
                  let stageID = EventPlace.ID(tail[1].decodedPathSegment) {
            self = .event(
                eventID,
                .stage(stageID)
            )
        } else if tail.count == 2, tail[0] == "performances",
                  let performanceID = ProgramItem.ID(tail[1].decodedPathSegment) {
            self = .event(
                eventID,
                .performance(performanceID)
            )
        } else if tail == ["communications"] {
            self = .event(eventID, .communications)
        } else if tail.count == 2, tail[0] == "communications",
                  let channelID = Social.Category.ID(tail[1].decodedPathSegment) {
            self = .event(
                eventID,
                .channel(channelID)
            )
        } else if tail.count == 4,
                  tail[0] == "communications",
                  tail[2] == "posts",
                  let channelID = Social.Category.ID(tail[1].decodedPathSegment),
                  let postID = Social.Post.ID(tail[3].decodedPathSegment) {
            self = .event(
                eventID,
                .post(
                    channelID: channelID,
                    postID: postID
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
            let base = openMusicEventEventPathRouter.path(for: eventID)
            guard let target else { return base }

            switch target {
            case .schedule:
                return "\(base)/schedule"
            case .contributors:
                return "\(base)/contributors"
            case let .contributor(contributorID):
                return "\(base)/contributors/\(contributorID.description.encodedPathSegment)"
            case .stages:
                return "\(base)/stages"
            case let .stage(stageID):
                return "\(base)/stages/\(stageID.description.encodedPathSegment)"
            case let .performance(performanceID):
                return "\(base)/performances/\(performanceID.description.encodedPathSegment)"
            case .communications:
                return "\(base)/communications"
            case let .channel(channelID):
                return openMusicEventEventPathRouter.communicationChannelPath(
                    eventID: eventID,
                    channelID: channelID
                )
            case let .post(channelID, postID):
                return openMusicEventEventPathRouter.communicationPostPath(
                    eventID: eventID,
                    channelID: channelID,
                    postID: postID
                )
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
