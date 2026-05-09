import FileTree

public struct OpenMusicEventSourceRepository: Equatable, Sendable {
    public var events: [DirectoryContent<OpenMusicEventSourceEvent>]

    public init(events: [DirectoryContent<OpenMusicEventSourceEvent>]) {
        self.events = events
    }
}

public struct OpenMusicEventSourceEvent: Equatable, Sendable {
    public var event: EventDTO
    public var stages: [FileContent<StageDTO>]?
    public var participants: [FileContent<ParticipantDTO>]?
    public var posters: [FileContent<PosterDTO>]?
    public var schedules: [FileContent<ScheduleDTO>]?
    public var channels: [FileContent<ChannelDTO>]?

    public init(
        event: EventDTO,
        stages: [FileContent<StageDTO>]? = nil,
        participants: [FileContent<ParticipantDTO>]? = nil,
        posters: [FileContent<PosterDTO>]? = nil,
        schedules: [FileContent<ScheduleDTO>]? = nil,
        channels: [FileContent<ChannelDTO>]? = nil
    ) {
        self.event = event
        self.stages = stages
        self.participants = participants
        self.posters = posters
        self.schedules = schedules
        self.channels = channels
    }
}
