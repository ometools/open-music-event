import FileTree
import Foundation

public struct OpenMusicEventSourceRepositoryFileTree: FileTreeWriter {
    public init() {}

    public var body: some FileTreeWriter<OpenMusicEventSourceRepository> {
        FileTree {
            File.Optional("calendar", "yml")
                .convert(YamlConversion<CalendarDTO>())

            Directory("events") {
                Directory.Many {
                    OpenMusicEventSourceEventFileTree()
                }
            }
        }
        .convert(RepositoryConversion())
    }
}

public struct OpenMusicEventSourceEventFileTree: FileTreeWriter {
    public init() {}

    public var body: some FileTreeWriter<OpenMusicEventSourceEvent> {
        FileTree {
            File("event", "yml")
                .convert(YamlConversion<EventDTO>())

            Directory.Optional("stages") {
                File.Many(withExtension: "yml")
                    .map(FileContentConversion(YamlConversion<StageDTO>()))
            }

            Directory.Optional("contributors") {
                File.Many(withExtension: "md")
                    .map(ContributorMarkdownConversion())
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
    typealias Input = (
        CalendarDTO?,
        [DirectoryContent<OpenMusicEventSourceEvent>]
    )
    typealias Output = OpenMusicEventSourceRepository

    func apply(_ input: Input) throws -> Output {
        OpenMusicEventSourceRepository(
            calendar: input.0,
            events: input.1
        )
    }

    func unapply(_ output: Output) throws -> Input {
        (
            output.calendar,
            output.events
        )
    }
}

private struct EventConversion: Conversion {
    typealias Input = (
        EventDTO,
        [FileContent<StageDTO>]?,
        [FileContent<ContributorDTO>]?,
        [FileContent<PosterDTO>]?,
        [FileContent<ScheduleDTO>]?,
        [FileContent<ChannelDTO>]?
    )
    typealias Output = OpenMusicEventSourceEvent

    func apply(_ input: Input) throws -> Output {
        OpenMusicEventSourceEvent(
            event: input.0,
            stages: input.1,
            contributors: input.2,
            posters: input.3,
            schedules: input.4,
            channels: input.5
        )
    }

    func unapply(_ output: Output) throws -> Input {
        (
            output.event,
            output.stages,
            output.contributors,
            output.posters,
            output.schedules,
            output.channels
        )
    }
}
