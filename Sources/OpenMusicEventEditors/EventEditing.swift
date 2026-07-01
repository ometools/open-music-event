import ComposableArchitecture2
import OpenMusicEventViewers

public struct EventEditingRequested: FeatureEventKey {
    public init() {}
    public typealias Value = EventEditingIntent
}

public enum EventEditingIntent: Equatable, Sendable {
    case addPerformance(eventID: OMERecord.Event.ID, scheduleID: OMERecord.ID<OMERecord.Schedule>?)
    case addPosters(OMERecord.Event.ID)
    case deletePerformance(eventID: OMERecord.Event.ID, performanceID: OMERecord.ID<OMERecord.Performance>)
    case deletePoster(OMERecord.Poster.ID)
    case editEvent(OMERecord.Event.ID)
    case editEventInfo(OMERecord.Event.ID)
    case editPerformance(eventID: OMERecord.Event.ID, performanceID: OMERecord.ID<OMERecord.Performance>)
    case editPoster(OMERecord.Poster.ID)
    case eventSettings(OMERecord.Event.ID)
}

extension EventFeature {
    public static let editorFeatures: [Self] = [
        .settings,
        .edit,
    ]

    public var isEditorFeature: Bool {
        switch self {
        case .settings, .edit:
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
             .search,
             .about:
            false
        }
    }
}
