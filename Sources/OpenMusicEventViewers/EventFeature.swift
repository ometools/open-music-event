#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif
import SwiftUITabFeatures

public enum EventFeature: Hashable, Sendable, LosslessStringConvertible, TabFeatureValue {
    case schedule(ScheduleDivision)
    case contributors
    case stages
    case communications
    case contactInfo
    case location
    case siteMap
    case posters
    case notifications
    case settings
    case workspace
    case search
    case about
//    case share

    public static let defaultReadOnlyFeatures: [Self] = [
        .schedule(.schedule),
        .communications,
        .contactInfo,
        .siteMap,
        .location,
        .contributors,
        .posters,
        .stages,
        .search,
        .settings,
        .about,
//        .share,
    ]

    public init?(_ description: String) {
        switch description {
        case "schedule":
            self = .schedule(.schedule)
        case let value where value.hasPrefix("schedule:"):
            let rawCategory = String(value.dropFirst("schedule:".count))
            guard !rawCategory.isEmpty else { return nil }
            self = .schedule(ScheduleDivision(category: rawCategory))
        case "contributors":
            self = .contributors
        case "stages":
            self = .stages
        case "communications":
            self = .communications
        case "contactInfo":
            self = .contactInfo
        case "location":
            self = .location
        case "siteMap":
            self = .siteMap
        case "posters":
            self = .posters
        case "notifications":
            self = .notifications
        case "settings":
            self = .settings
        case "workspace", "edit":
            self = .workspace
        case "search":
            self = .search
        case "about":
            self = .about
//        case "share":
//            self = .share
        default:
            return nil
        }
    }

    public var description: String {
        switch self {
        case let .schedule(division):
            if let category = division.category {
                return "schedule:\(category)"
            }
            return "schedule"
        case .contributors:
            return "contributors"
        case .stages:
            return "stages"
        case .communications:
            return "communications"
        case .contactInfo:
            return "contactInfo"
        case .location:
            return "location"
        case .siteMap:
            return "siteMap"
        case .posters:
            return "posters"
        case .notifications:
            return "notifications"
        case .settings:
            return "settings"
        case .workspace:
            return "workspace"
        case .search:
            return "search"
        case .about:
            return "about"
//        case .share:
//            return "share"
        }
    }

    public var customizationID: TabFeatureID {
        switch self {
        case let .schedule(division):
            if division.category == nil {
                return "openMusicEvent.eventViewer.schedule"
            }
            return "openMusicEvent.eventViewer.schedule.\(division.id)"
        case .contributors:
            return "openMusicEvent.eventViewer.contributors"
        case .stages:
            return "openMusicEvent.eventViewer.stages"
        case .communications:
            return "openMusicEvent.eventViewer.communications"
        case .contactInfo:
            return "openMusicEvent.eventViewer.contactInfo"
        case .location:
            return "openMusicEvent.eventViewer.location"
        case .siteMap:
            return "openMusicEvent.eventViewer.siteMap"
        case .posters:
            return "openMusicEvent.eventViewer.posters"
        case .notifications:
            return "openMusicEvent.eventViewer.notifications"
        case .settings:
            return "openMusicEvent.eventViewer.settings"
        case .workspace:
            return "openMusicEvent.eventViewer.workspace"
        case .search:
            return "openMusicEvent.eventViewer.search"
        case .about:
            return "openMusicEvent.eventViewer.about"
//        case .share:
//            return "openMusicEvent.eventViewer.share"
        }
    }

    public var labelTint: Color? {
        switch self {
        case .schedule:
            .green
        case .contributors:
            .pink
        case .stages:
            .indigo
        case .communications:
            .orange
        case .contactInfo:
            .green
        case .location:
            .blue
        case .siteMap:
            .teal
        case .posters:
            .purple
        case .notifications:
            .red
        case .settings:
            .gray
        case .workspace:
            .yellow
        case .search:
            nil
        case .about:
            .gray
//        case .share:
//            .blue
        }
    }

    public var scheduleDivision: ScheduleDivision? {
        guard case let .schedule(division) = self else { return nil }
        return division
    }

    public var systemImage: String {
        switch self {
        case let .schedule(division):
            division.systemImage
        case .contributors:
            "person.3"
        case .stages:
            "square.grid.2x2"
        case .communications:
            "megaphone"
        case .contactInfo:
            "phone"
        case .location:
            "mappin.and.ellipse"
        case .siteMap:
            "map"
        case .posters:
            "photo.on.rectangle"
        case .notifications:
            "bell"
        case .settings:
            "gearshape"
        case .workspace:
            "tray.full"
        case .search:
            "magnifyingglass"
        case .about:
            "info.circle"
//        case .share:
//            "qrcode"
        }
    }

    public var title: String {
        switch self {
        case let .schedule(division):
            division.title
        case .contributors:
            "Contributors"
        case .stages:
            "Stages"
        case .communications:
            "Comms"
        case .contactInfo:
            "Contact"
        case .location:
            "Location"
        case .siteMap:
            "Site Map"
        case .posters:
            "Posters"
        case .notifications:
            "Alerts"
        case .settings:
            "Settings"
        case .workspace:
            "Workspace"
        case .search:
            "Search"
        case .about:
            "About"
//        case .share:
//            "Share"
        }
    }

    public static func readOnlyFeatures(
        scheduleDivisions: [ScheduleDivision]
    ) -> [Self] {
        let divisions = scheduleDivisions.isEmpty ? [.schedule] : scheduleDivisions
        return divisions.map(Self.schedule) + defaultReadOnlyFeatures.filter {
            $0.scheduleDivision == nil
        }
    }
}
