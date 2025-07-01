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
            [CoreModels.Artist.Draft]?
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
                stageLineups: stageLineups
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
    static let markdown: FileExtension = "md"
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


struct ArtistConversion: Conversion {

    public struct ArtistInfoFrontMatter: Codable, Equatable {
        var imageURL: URL?
        var links: [CoreModels.Artist.Link]
    }

    
    var body: some Conversion<FileContent<Data>, CoreModels.Artist.Draft> {
        FileContentConversion {
            Conversions.DataToString()
            MarkdownWithFrontMatterConversion<ArtistInfoFrontMatter>()
        }

        FileToArtistConversion()
    }

    struct FileToArtistConversion: Conversion {
        typealias Input = FileContent<MarkdownWithFrontMatter<ArtistInfoFrontMatter>>
        typealias Output = CoreModels.Artist.Draft

        func apply(_ input: Input) throws -> Output {
            CoreModels.Artist.Draft(
                name: input.fileName,
                bio: input.data.body,
                imageURL: input.data.frontMatter?.imageURL,
                links: (input.data.frontMatter?.links ?? []).map { .init(url: $0.url, label: $0.label )}
            )
        }

        func unapply(_ output: Output) throws -> Input {
            throw UnimplementedFailure(description: "FileToArtistConversion.unapply")
            //            FileContent(
//                fileName: output.name,
//                data: MarkdownWithFrontMatter(
//                    frontMatter: ArtistInfoFrontMatter(
//                        imageURL: output.imageURL,
//                        links: output.links.map { .init(url: $0.url, label: $0.label )}
//                    ).nilIfEmpty,
//                    body: output.bio?.nilIfEmpty
//                )
//            )
        }
    }
}
