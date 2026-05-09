import FileTree
import Foundation

public struct OpenMusicEventSourceRepositoryFileTree: FileTreeReader {
    public init() {}

    public var body: some FileTreeReader<OpenMusicEventSourceRepository> {
        Directory("events") {
            Directory.Many {
                OpenMusicEventSourceEventFileTree()
            }
        }
        .convert(RepositoryConversion())
    }
}

public struct OpenMusicEventSourceEventFileTree: FileTreeReader {
    public init() {}

    public var body: some FileTreeReader<OpenMusicEventSourceEvent> {
        FileTree {
            File("event", "yml")
                .convert(YamlConversion<EventDTO>())

            Directory.Optional("stages") {
                File.Many(withExtension: "yml")
                    .map(FileContentConversion(YamlConversion<StageDTO>()))
            }

            Directory.Optional("participants") {
                File.Many(withExtension: "md")
                    .map(ParticipantMarkdownConversion())
            }

            Directory.Optional("posters") {
                File.Many(withExtension: "yml")
                    .map(FileContentConversion(YamlConversion<PosterDTO>()))
            }

            Directory.Optional("schedules") {
                File.Many(withExtension: "yml")
                    .map(FileContentConversion(YamlConversion<ScheduleDTO>()))
            }

            Directory.Optional("channels") {
                File.Many(withExtension: "yml")
                    .map(FileContentConversion(YamlConversion<ChannelDTO>()))
            }
        }
        .convert(EventConversion())
    }
}

private struct RepositoryConversion: Conversion {
    typealias Input = [DirectoryContent<OpenMusicEventSourceEvent>]
    typealias Output = OpenMusicEventSourceRepository

    func apply(_ input: Input) throws -> Output {
        OpenMusicEventSourceRepository(events: input)
    }

    func unapply(_ output: Output) throws -> Input {
        output.events
    }
}

private struct EventConversion: Conversion {
    typealias Input = (
        EventDTO,
        [FileContent<StageDTO>]?,
        [FileContent<ParticipantDTO>]?,
        [FileContent<PosterDTO>]?,
        [FileContent<ScheduleDTO>]?,
        [FileContent<ChannelDTO>]?
    )
    typealias Output = OpenMusicEventSourceEvent

    func apply(_ input: Input) throws -> Output {
        OpenMusicEventSourceEvent(
            event: input.0,
            stages: input.1,
            participants: input.2,
            posters: input.3,
            schedules: input.4,
            channels: input.5
        )
    }

    func unapply(_ output: Output) throws -> Input {
        (
            output.event,
            output.stages,
            output.participants,
            output.posters,
            output.schedules,
            output.channels
        )
    }
}
