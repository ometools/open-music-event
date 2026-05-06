import Foundation
import OpenMusicEventAppEventViewer

public enum AppRoute: Equatable, Sendable {
    case event(OMERecord.Event.ID, EventTarget?)

    public init?(url: URL) {
        let segments = url.path.split(separator: "/").map(String.init)
        guard !segments.isEmpty else { return nil }

        switch segments[0] {
        case "events":
            guard segments.count >= 2 else { return nil }
            let eventID = OMERecord.Event.ID(.init(segments[1]))
            let tail = Array(segments.dropFirst(2))

            if tail.isEmpty {
                self = .event(eventID, nil)
            } else if tail == ["schedule"] {
                self = .event(eventID, .schedule)
            } else if tail.count == 2, tail[0] == "participants" {
                let participantID = tail[1]
                self = .event(eventID, .participant(.init(.init(participantID))))
            } else if tail.count == 2, tail[0] == "stages" {
                let stageID = tail[1]
                self = .event(eventID, .stage(.init(.init(stageID))))
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
            } else if tail == ["search"] {
                self = .event(eventID, .search)
            } else if tail == ["about"] {
                self = .event(eventID, .about)
            } else if tail == ["edit"] {
                self = .event(eventID, .edit)
            } else {
                return nil
            }

        default:
            return nil
        }
    }

    public var path: String {
        switch self {
        case let .event(eventID, target):
            let base = "/events/\(eventID.rawValue.rawValue)"
            guard let target else { return base }

            switch target {
            case .schedule:
                return "\(base)/schedule"
            case let .participant(participantID):
                return "\(base)/participants/\(participantID.rawValue.rawValue)"
            case let .stage(stageID):
                return "\(base)/stages/\(stageID.rawValue.rawValue)"
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
            case .search:
                return "\(base)/search"
            case .about:
                return "\(base)/about"
            case .edit:
                return "\(base)/edit"
            }
        }
    }

    public var navigationRequest: NavigationRequest {
        switch self {
        case let .event(eventID, target):
            .event(eventID, target)
        }
    }
}
