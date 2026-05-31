import FileTree
import OpenMusicEventLexicon

public struct OpenMusicEventSourceRepository: Equatable, Sendable {
    public var calendar: CalendarDTO?
    public var events: [DirectoryContent<OpenMusicEventSourceEvent>]

    public init(
        calendar: CalendarDTO? = nil,
        events: [DirectoryContent<OpenMusicEventSourceEvent>]
    ) {
        self.calendar = calendar
        self.events = events
    }

    public init(events: [DirectoryContent<OpenMusicEventSourceEvent>]) {
        self.init(calendar: nil, events: events)
    }
}

public struct OpenMusicEventSourceEvent: Equatable, Sendable {
    public var event: EventDTO
    public var stages: [FileContent<StageDTO>]?
    public var contributors: [FileContent<ContributorDTO>]?
    public var posters: [FileContent<PosterDTO>]?
    public var schedules: [FileContent<ScheduleDTO>]?
    public var channels: [FileContent<ChannelDTO>]?

    public init(
        event: EventDTO,
        stages: [FileContent<StageDTO>]? = nil,
        contributors: [FileContent<ContributorDTO>]? = nil,
        posters: [FileContent<PosterDTO>]? = nil,
        schedules: [FileContent<ScheduleDTO>]? = nil,
        channels: [FileContent<ChannelDTO>]? = nil
    ) {
        self.event = event
        self.stages = stages
        self.contributors = contributors
        self.posters = posters
        self.schedules = schedules
        self.channels = channels
    }

    public init(
        event: OMERecord.Event.Draft,
        stages: [FileContent<StageDTO>]? = nil,
        contributors: [FileContent<ContributorDTO>]? = nil,
        posters: [FileContent<PosterDTO>]? = nil,
        schedules: [FileContent<ScheduleDTO>]? = nil,
        channels: [FileContent<ChannelDTO>]? = nil
    ) {
        self.init(
            event: EventDTO(event),
            stages: stages,
            contributors: contributors,
            posters: posters,
            schedules: schedules,
            channels: channels
        )
    }
}
