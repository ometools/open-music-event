import ComposableNotifications
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventRouting
import OpenMusicEventViewers

public typealias BrandedEventRouteClaim = OpenMusicEventRouting.BrandedEventRouteClaim

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
        self.init(url: url, brandedClaims: [])
    }

    public init?(
        url: URL,
        brandedClaims: [BrandedEventRouteClaim]
    ) {
        let segments = url.path.split(separator: "/").map(String.init)
        if segments.count >= 4,
           segments[0] == "orgs",
           segments[2] == "events",
           let organizerID = OMERecord.Organizer.ID(segments[1].decodedPathSegment) {
            self.init(
                eventID: OMERecord.Event.ID(
                    organizerID: organizerID,
                    eventID: OMERecord.ID<OMERecord.Event>(
                        .init(segments[3].decodedPathSegment)
                    )
                ),
                tail: Array(segments.dropFirst(4))
            )
            return
        }

        guard
            url.scheme?.lowercased() == "https",
            url.port == nil || url.port == 443,
            let host = url.host?.lowercased(),
            segments.count >= 2,
            segments[0] == "events",
            let claim = brandedClaims.first(where: {
                $0.host.lowercased() == host
                    && $0.eventClaim == segments[1].decodedPathSegment
            })
        else { return nil }

        self.init(
            eventID: claim.eventID,
            tail: Array(segments.dropFirst(2))
        )
    }

    private init?(eventID: OMERecord.Event.ID, tail: [String]) {
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
            let base = openMusicEventEventPathRouter.path(for: eventID)
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
                return openMusicEventEventPathRouter.communicationChannelPath(
                    eventID: eventID,
                    channelID: channelID
                )
            case let .post(channelID, postID):
                return openMusicEventEventPathRouter.communicationPostPath(
                    eventID: eventID,
                    channelID: channelID,
                    postID: postID.rawValue
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
