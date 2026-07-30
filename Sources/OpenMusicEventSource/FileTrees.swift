import FileTree
import Foundation
import OpenMusicEventLexicon

public struct OpenMusicEventSourceRepositoryFileTree: FileTreeWriter {
    public init() {}

    public var body: some FileTreeWriter<OpenMusicEventSourceRepository> {
        FileTree {
            File.Optional("calendar", "yml")
                .convert(YamlConversion<CalendarDTO>())

            Directory.Optional("collaborators") {
                File.Many(withExtension: "yml")
                    .map(FileContentConversion(YamlConversion<OME.Relationship>()))
            }

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

            Directory.Optional("communications") {
                Directory.Many {
                    FileTree {
                        File("channel-info", "yaml")
                            .convert(YamlConversion<LegacyCommunicationChannelDTO>())

                        File.Many(withExtension: "md")
                            .map(CommunicationPostMarkdownConversion())
                    }
                    .convert(LegacyCommunicationConversion())
                }
            }
        }
        .convert(EventConversion())
    }
}

struct LegacyCommunicationDTO: Equatable, Sendable {
    var channel: LegacyCommunicationChannelDTO
    var posts: [FileContent<CommunicationPostDTO>]
}

struct LegacyCommunicationChannelDTO: Codable, Equatable, Sendable {
    var id: OMERecord.Channel.ID?
    var name: String
    var description: String
    var iconImageURL: URL?
    var headerImageURL: URL?
    var sortIndex: Int?
    var defaultNotificationState: OMERecord.Channel.NotificationState?
    var notificationsRequired: Bool?

    var recordDraft: ChannelDTO {
        OMERecord.Channel.Draft(
            id: id,
            name: name,
            description: description,
            iconImageURL: iconImageURL,
            headerImageURL: headerImageURL,
            sortIndex: sortIndex,
            defaultNotificationState: defaultNotificationState ?? .unsubscribed,
            notificationsRequired: notificationsRequired ?? false
        )
    }
}

private struct LegacyCommunicationConversion: Conversion {
    typealias Input = (
        LegacyCommunicationChannelDTO,
        [FileContent<CommunicationPostDTO>]
    )
    typealias Output = LegacyCommunicationDTO

    func apply(_ input: Input) throws -> Output {
        LegacyCommunicationDTO(
            channel: input.0,
            posts: input.1
        )
    }

    func unapply(_ output: Output) throws -> Input {
        (
            output.channel,
            output.posts
        )
    }
}

private struct RepositoryConversion: Conversion {
    typealias Input = (
        CalendarDTO?,
        [FileContent<OME.Relationship>]?,
        [DirectoryContent<OpenMusicEventSourceEvent>]
    )
    typealias Output = OpenMusicEventSourceRepository

    func apply(_ input: Input) throws -> Output {
        OpenMusicEventSourceRepository(
            calendar: input.0,
            collaborators: input.1,
            events: input.2
        )
    }

    func unapply(_ output: Output) throws -> Input {
        (
            output.calendar,
            output.collaborators,
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
        [FileContent<ChannelDTO>]?,
        [DirectoryContent<LegacyCommunicationDTO>]?
    )
    typealias Output = OpenMusicEventSourceEvent

    func apply(_ input: Input) throws -> Output {
        OpenMusicEventSourceEvent(
            event: input.0,
            stages: input.1,
            contributors: input.2,
            posters: input.3,
            schedules: input.4,
            channels: try Self.mergedChannels(
                modernChannels: input.5,
                legacyCommunications: input.6
            ),
            communicationPosts: Self.communicationPosts(
                legacyCommunications: input.6
            )
        )
    }

    func unapply(_ output: Output) throws -> Input {
        (
            output.event,
            output.stages,
            output.contributors,
            output.posters,
            output.schedules,
            output.channels,
            nil
        )
    }

    private static func mergedChannels(
        modernChannels: [FileContent<ChannelDTO>]?,
        legacyCommunications: [DirectoryContent<LegacyCommunicationDTO>]?
    ) throws -> [FileContent<ChannelDTO>]? {
        var channels = modernChannels ?? []
        var channelFileNames = Set(channels.map(\.fileName))

        for communication in legacyCommunications ?? [] where channelFileNames.insert(communication.directoryName).inserted {
            channels.append(
                try FileContent(
                    fileName: communication.directoryName,
                    fileType: "yml",
                    data: communication.components.channel.recordDraft
                )
            )
        }

        return channels.isEmpty ? nil : channels
    }

    private static func communicationPosts(
        legacyCommunications: [DirectoryContent<LegacyCommunicationDTO>]?
    ) -> [DirectoryContent<[FileContent<CommunicationPostDTO>]>]? {
        let posts = (legacyCommunications ?? [])
            .filter { !$0.components.posts.isEmpty }
            .map {
                DirectoryContent(
                    directoryName: $0.directoryName,
                    components: $0.components.posts
                )
            }

        return posts.isEmpty ? nil : posts
    }
}
