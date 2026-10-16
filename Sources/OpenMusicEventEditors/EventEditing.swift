import ComposableArchitecture2
import OpenMusicEventLexicon
import OpenMusicEventViewers

public struct EventEditingRequested: FeatureEventKey {
    public init() {}
    public typealias Value = EventEditingIntent
}

public enum EventEditingIntent: Equatable, Sendable {
    case addPerformance(
        eventID: Event.ID,
        scheduleID: Schedule.ID?,
        programID: Program.ID?,
        stageID: EventPlace.ID?
    )
    case addPosters(Event.ID)
    case addSchedule(Event.ID)
    case copyStagesFromEvent(Event.ID)
    case createContributor(Event.ID)
    case createPlace(Event.ID)
    case deletePerformance(eventID: Event.ID, performanceID: ProgramItem.ID)
    case editContactInfo(Event.ID)
    case editContributor(eventID: Event.ID, contributorID: Contributor.ID)
    case eventWorkspace(Event.ID)
    case editLocation(Event.ID)
    case editPerformance(eventID: Event.ID, performanceID: ProgramItem.ID)
    case editPlace(eventID: Event.ID, placeID: EventPlace.ID)
    case eventSettings(Event.ID)
}

extension EventFeature {
    public static let editorFeatures: [Self] = [
        .workspace,
    ]

    public var isEditorFeature: Bool {
        switch self {
        case .workspace:
            true
        case .schedule,
             .contributors,
             .stages,
             .communications,
             .contactInfo,
             .location,
             .siteMap,
             .posters,
             .notifications,
             .settings,
             .search,
//             .share,
             .about:
            false
        }
    }
}
