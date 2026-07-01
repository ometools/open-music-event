import SwiftUI
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
    case edit
    case search
    case about

    public static let defaultReadOnlyFeatures: [Self] = [
        .schedule(.schedule),
        .communications,
        .contactInfo,
        .siteMap,
        .location,
        .contributors,
        .posters,
        .notifications,
        .stages,
        .search,
        .about,
    ]

    public init?(_ description: String) {
        switch description {
        case "schedule":
            self = .schedule(.schedule)
        case let value where value.hasPrefix("schedule:"):
            let rawCategory = String(value.dropFirst("schedule:".count))
            guard !rawCategory.isEmpty else { return nil }
            self = .schedule(
                ScheduleDivision(category: OMERecord.Stage.Category(rawCategory))
            )
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
        case "edit":
            self = .edit
        case "search":
            self = .search
        case "about":
            self = .about
        default:
            return nil
        }
    }

    public var description: String {
        switch self {
        case let .schedule(division):
            if let category = division.category {
                return "schedule:\(category.rawValue)"
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
        case .edit:
            return "edit"
        case .search:
            return "search"
        case .about:
            return "about"
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
        case .edit:
            return "openMusicEvent.eventViewer.edit"
        case .search:
            return "openMusicEvent.eventViewer.search"
        case .about:
            return "openMusicEvent.eventViewer.about"
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
        case .edit:
            .yellow
        case .search:
            nil
        case .about:
            .gray
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
        case .edit:
            "pencil"
        case .search:
            "magnifyingglass"
        case .about:
            "info.circle"
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
        case .edit:
            "Edit"
        case .search:
            "Search"
        case .about:
            "About"
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
