//
//  FileTree.swift
//  OpenFestival
//
//  Created by Woodrow Melling on 9/30/24.
//

@preconcurrency import FileTree

import Yams
import IssueReporting
import FileTree
import Foundation
import CoreModels
import Foundation

struct OpenFestivalDecoder {
    public func decode(from url: URL) throws -> EventConfiguration {
        return try EventFileTree().read(from: url)
    }
}

extension OrganizerConfiguration {
    public static var fileTree: some FileTreeReader<OrganizerConfiguration> {
        FileTree {
            File("organizer-info", "yml")
                .convert {
                    Conversions.YamlConversion<CoreModels.Organizer.Draft>()
                }

            Directory.Many {
                EventFileTree()
            }
        }
        .convert(
            AnyConversion(
                apply: { info, events in
                    OrganizerConfiguration(info: info, events: events.map(\.components))
                },
                unapply: { _ in
                    fatalError()
                }
            )
        )
    }
}

// MARK: Event
public struct EventFileTree: FileTreeReader {
    public init() {}

    public var body: some FileTreeReader<EventConfiguration> {
        FileTree {
            File("event-info", "yml")
                .convert(Conversions.YamlConversion<EventConfiguration.EventInfoYaml>())


            File.Optional("stage-lineups", "yml")
                .convert(Conversions.YamlConversion<EventConfiguration.StageLineups>())

            Directory.Optional("schedules") {
                File.Many(withExtension: "yml")
                    .map(SchedulesConversion())
            }

            Directory.Optional("artists") {
                File.Many(withExtension: "md")
                    .map(ArtistConversion())
            }
            
            CommunicationsConfiguration.fileTree

        }
        .convert(EventConversion())
    }


    struct SchedulesConversion: Conversion {
        var body: some Conversion<FileContent<Data>, Schedule.WithUnresolvedTimes> {
            FileContentConversion {
                Conversions.YamlConversion(CoreModels.Schedule.YamlRepresentation.self)
            }

            ScheduleConversion()
        }
    }
struct EventConversion: Conversion {
        typealias Input = (
            EventConfiguration.EventInfoYaml,
            EventConfiguration.StageLineups?,
            [Schedule.WithUnresolvedTimes]?,
            [CoreModels.Artist.Draft]?,
            CommunicationsConfiguration
        )
        typealias Output = EventConfiguration

        func apply(_ input: Input) throws -> EventConfiguration {

            let eventInfo = input.0
            let stageLineups = input.1
            let artists = input.3

            let timeZone = try TimeZoneConversion().apply(eventInfo.timeZone) ?? TimeZone.current

            let resolvedSchedule = try input.2?.map { try $0.resolved(timeZone: timeZone) }

            return EventConfiguration(
                info: CoreModels.MusicEvent.Draft(
                    name: eventInfo.name ?? "",
                    timeZone: timeZone,
                    startTime: eventInfo.startDate?.date,
                    endTime: eventInfo.endDate?.date,
                    iconImageURL: eventInfo.iconImageURL,
                    imageURL: eventInfo.imageURL,
                    siteMapImageURL: eventInfo.siteMapImageURL,
                    location: .init(
                        address: eventInfo.address,
                        directions: nil,
                        coordinates: nil
                    ),
                    contactNumbers: (eventInfo.contactNumbers ?? []).map {
                        .init(
                            phoneNumber: $0.phoneNumber,
                            title: $0.title,
                            description: $0.description
                        )
                    },
                ),
                artists: artists ?? [],
                stages: eventInfo.stages ?? [],
                schedule: resolvedSchedule ?? [],
                stageLineups: stageLineups,
                communications: input.4
            )
        }

        func unapply(_ output: EventConfiguration) throws -> Input {
            throw UnimplementedFailure(description: "EventConversion.unapply")
        }

        struct TimeZoneConversion: Conversion {
            typealias Input = String?
            typealias Output = TimeZone?

            func apply(_ input: String?) throws -> TimeZone? {
                input.flatMap(TimeZone.init(identifier:)) ?? input.flatMap(TimeZone.init(abbreviation:))
            }

            func unapply(_ output: TimeZone?) throws -> String? {
                output.map { $0.identifier }
            }
        }
    }
}

extension Dictionary {
    func mapValuesWithKeys<NewValue>(_ transform: (Key, Value) throws -> NewValue) rethrows -> [Key: NewValue] {
        try Dictionary<Key, NewValue>(uniqueKeysWithValues: self.map { try ($0, transform($0, $1))})
    }
}

extension FileExtension {
    public static let markdown: FileExtension = "md"
}

extension EventConfiguration {
    struct EventInfoYaml: Codable, Equatable {
        var name: String?
        var address: String?
        var timeZone: String?

        var iconImageURL: URL?
        var imageURL: URL?
        var siteMapImageURL: URL?

        var startDate: CalendarDate?
        var endDate: CalendarDate?

        var contactNumbers: [CoreModels.MusicEvent.ContactNumber]?
        var stages: [CoreModels.Stage.Draft]?
    }
}


public struct ArtistConversion: Conversion {
    public init() {}

    public struct ArtistInfoFrontMatter: Codable, Equatable, Sendable {
        public var imageURL: URL?
        public var logoURL: URL?
        public var kind: CoreModels.Artist.Kind?
        public var links: [CoreModels.Artist.Link]
    }

    public var body: some Conversion<FileContent<Data>, CoreModels.Artist.Draft> {
        FileContentConversion {
            Conversions.DataToString()
            MarkdownWithFrontMatterConversion<ArtistInfoFrontMatter>()
        }

        FileToArtistConversion()
    }

    public struct FileToArtistConversion: Conversion {
        public typealias Input = FileContent<MarkdownWithFrontMatter<ArtistInfoFrontMatter>>
        public typealias Output = CoreModels.Artist.Draft

        public func apply(_ input: Input) throws -> Output {
            CoreModels.Artist.Draft(
                name: input.fileName,
                bio: input.data.body,
                imageURL: input.data.frontMatter?.imageURL,
                logoURL: input.data.frontMatter?.logoURL,
                kind: input.data.frontMatter?.kind,
                links: (input.data.frontMatter?.links ?? []).map { .init(url: $0.url, type: $0.linkType )}
            )
        }

        public func unapply(_ output: Output) throws -> Input {
            FileContent(
                fileName: output.name,
                fileType: "md",
                data: MarkdownWithFrontMatter(
                    frontMatter: ArtistInfoFrontMatter(
                        imageURL: output.imageURL,
                        logoURL: output.logoURL,
                        kind: output.kind,
                        links: output.links
                    ),
                    body: output.bio?.nilIfEmpty
                )
            )
        }
    }
}

extension CommunicationsConfiguration {
    nonisolated(unsafe) static let fileTree: some FileTreeReader<CommunicationsConfiguration> = Directory.Optional("communications") {
        Directory.Many {
            ChannelConfiguration.fileTree
        }
    }
    .convert(CommunicationsConversion())
}


typealias ChannelConfiguration = EventConfiguration.ChannelConfiguration

extension FileTree: @unchecked Sendable {}

extension ChannelConfiguration {
    nonisolated(unsafe) static let fileTree: some FileTreeReader<EventConfiguration.ChannelConfiguration> = FileTree {
        File("channel-info", "yaml")
            .convert(Conversions.YamlConversion<CommunicationChannel.Yaml>())
            .convert(
                AnyConversion(
                    apply: { $0.toDraft() },
                    unapply: { $0.toYaml() }
                )
            )

        File.Many(withExtension: "md")
            .map(PostConversion())
    }
    .convert {
        AnyConversion { info, posts in
            return EventConfiguration.ChannelConfiguration(
                info: info,
                posts: posts
            )
        } unapply: { _ in
            fatalError("EventConfiguration.ChannelConfiguration")
        }
    }

}

struct CommunicationsConversion: Conversion {
    // Directory.Many produces [(channelInfo, [posts])] where channelInfo is from channel-info.yaml and posts are from .md files
//        typealias Input = [(CoreModels.CommunicationChannel.Draft, [FileContent<CoreModels.CommunicationChannel.Post.Draft>])]?
    typealias Input = [DirectoryContent<ChannelConfiguration>]?
    typealias Output = CommunicationsConfiguration

    func apply(_ input: Input) throws -> Output {
        guard let channelsWithPosts = input else {
            return []
        }

        return channelsWithPosts.map { channel in
            let channelInfo = channel.components.info
            // Set the channelID for all posts based on the channel info
            let updatedPosts = channel.components.posts.map { post in
                var updatedPost = post
                updatedPost.channelID = channelInfo.id
                return updatedPost
            }

            return EventConfiguration.ChannelConfiguration(
                info: channelInfo,
                posts: updatedPosts
            )
        }
    }

    func unapply(_ output: Output) throws -> Input {
        fatalError("")
        //        return output.isEmpty ? nil : output
//            output.map { channelConfig in
//                (channelConfig.info, channelConfig.posts)
//            }
    }
}


public struct PostConversion: Conversion {
    public init() {}

    public struct PostFrontMatter: Codable, Equatable, Sendable {
        public var headerImageURL: URL?
        public var timestamp: Date?
        public var isPinned: Bool?
    }

    public var body: some Conversion<FileContent<Data>, CoreModels.CommunicationChannel.Post.Draft> {
        FileContentConversion {
            Conversions.DataToString()
            MarkdownWithFrontMatterConversion<PostFrontMatter>()
        }

        FileToPostConversion()
    }

    public struct FileToPostConversion: Conversion {
        public typealias Input = FileContent<MarkdownWithFrontMatter<PostFrontMatter>>
        public typealias Output = CoreModels.CommunicationChannel.Post.Draft

        public func apply(_ input: Input) throws -> Output {
            CoreModels.CommunicationChannel.Post.Draft(
                channelID: nil,
                title: input.fileName,
                contents: input.data.body ?? "",
                headerImageURL: input.data.frontMatter?.headerImageURL,
                timestamp: input.data.frontMatter?.timestamp ?? Date(),
                isPinned: input.data.frontMatter?.isPinned ?? false
            )
        }

        public func unapply(_ output: Output) throws -> Input {
            FileContent(
                fileName: output.title,
                fileType: "md",
                data: MarkdownWithFrontMatter(
                    frontMatter: PostFrontMatter(
                        headerImageURL: output.headerImageURL,
                        timestamp: output.timestamp,
                        isPinned: output.isPinned
                    ),
                    body: output.contents.nilIfEmpty
                )
            )
        }
    }
}
