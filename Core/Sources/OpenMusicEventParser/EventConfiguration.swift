//
//  File.swift
//
//
//  Created by Woody on 2/10/22.
//

import Foundation
import Tagged
import CoreModels
import Collections

public typealias OpenFestivalIDType = UUID

public struct OrganizerConfiguration: Equatable, Sendable {
    public var info: CoreModels.Organizer.Draft
    public var events: [EventConfiguration]

    public init(info: CoreModels.Organizer.Draft, events: [EventConfiguration]) {
        self.info = info
        self.events = events
    }
}

public struct EventConfiguration: Equatable, Sendable {
    public var info: CoreModels.MusicEvent.Draft
    public var artists: [CoreModels.Artist.Draft]
    public var stages: [CoreModels.Stage.Draft]
    public var schedule: [Schedule.StringlyTyped]
    public var stageLineups: StageLineups?
    public var channels: CommunicationsConfiguration

    public init(
        info: CoreModels.MusicEvent.Draft,
        artists: [CoreModels.Artist.Draft],
        stages: [CoreModels.Stage.Draft],
        schedule: [Schedule.StringlyTyped],
        stageLineups: StageLineups?,
        communications: CommunicationsConfiguration
    ) {
        self.info = info
        self.artists = artists
        self.stages = stages
        self.schedule = schedule
        self.stageLineups = stageLineups
        self.channels = communications
    }
}

extension EventConfiguration {
    public typealias StageLineups = [Stage.Name: StageLineup]
    public struct StageLineup: Equatable, Sendable, Codable {
        public var posterURL: URL?
        public var artists: [Artist.Name]
    }
}

public typealias CommunicationsConfiguration = [EventConfiguration.ChannelConfiguration]

extension EventConfiguration {

    public struct ChannelConfiguration: Equatable, Sendable {
        public init(info: CoreModels.CommunicationChannel.Draft, posts: [CoreModels.CommunicationChannel.Post.Draft]) {
            self.info = info
            self.posts = posts
        }
        
        public var info: CoreModels.CommunicationChannel.Draft
        public var posts: [CoreModels.CommunicationChannel.Post.Draft]
    }
}

struct UnresolvableDateError: Error {
    let message: String
}

extension CoreModels.Schedule {
    public struct WithUnresolvedTimes: Equatable, Sendable {
        public var metadata: Metadata
        public var stageSchedules: [String: [Performance]]

        public func resolved(timeZone: TimeZone) throws -> CoreModels.Schedule.StringlyTyped {
            guard let day = metadata.date else {
                throw UnresolvableDateError(message: "Cannot resolve schedule times without a Date")
            }

            let resolvedStageSchedules = stageSchedules.mapValues { performances in
                performances.map { $0.resolved(day: day, timeZone: timeZone) }
            }

            let allPerformances = resolvedStageSchedules.values.flatMap { $0 }

            guard let earliestStart = allPerformances.min(by: { $0.startTime < $1.startTime })?.startTime,
                  let latestEnd = allPerformances.max(by: { $0.endTime < $1.endTime })?.endTime
            else {
                throw UnresolvableDateError(message: "No performances to resolve")
            }

            return CoreModels.Schedule.StringlyTyped(
                metadata: .init(
                    startTime: earliestStart,
                    endTime: latestEnd,
                    customTitle: metadata.customTitle
                ),
                stageSchedules: resolvedStageSchedules
            )
        }

        public struct Performance: Equatable, Sendable {
            public var title: String
            public var subtitle: String?
            public var artistNames: OrderedSet<String>
            public var startTime: ScheduleTime
            public var endTime: ScheduleTime
            public var stageName: String

            func resolved(day: CalendarDate, timeZone: TimeZone) -> CoreModels.Schedule.StringlyTyped.Performance {
                let startDate = day.resolveTime(startTime, timeZone: timeZone)
                let endDate = day.resolveTime(endTime, timeZone: timeZone)

                return CoreModels.Schedule.StringlyTyped.Performance(
                    title: self.title,
                    subtitle: self.subtitle,
                    artistNames: self.artistNames,
                    startTime: startDate,
                    endTime: endDate,
                    stageName: self.stageName
                )
            }

        }

        public struct Metadata: Equatable, Hashable, Sendable {
            public init(
                date: CalendarDate? = nil,
                customTitle: String? = nil
            ) {
                self.date = date
                self.customTitle = customTitle
            }

            public var date: CalendarDate?
            public var customTitle: String?

            public var startTime: Date? {
                date?.date
            }

            public var endTime: Date? {
                nil
            }
        }
    }

    public struct StringlyTyped: Equatable, Sendable {
        public var metadata: Metadata
        public var stageSchedules: [String : [Performance]]

        public struct Performance: Equatable, Sendable {
            public var title: String
            public var subtitle: String?
            public var artistNames: OrderedSet<String>
            public var startTime: Date
            public var endTime: Date
            public var stageName: String
        }

        public struct Metadata: Equatable, Hashable, Sendable {
            public var startTime: Date
            public var endTime: Date
            public var customTitle: String?
        }
    }
}


//extension Schedule.StringlyTyped {
//    func withTimeZone(_ timeZone: TimeZone) -> Schedule.StringlyTyped {
//        var result = self
//        result.stageSchedules.forEach { key, value in
//            result.stageSchedules[key] = value.map(\.withTimeZone(timeZone))
//        }
//        return result
//    }
//}

import Foundation

extension Date {
    init?(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0,
        second: Int = 0,
        calendar: Calendar = .current
    ){
        var dateComponents = DateComponents()
        dateComponents.year = year
        dateComponents.month = month
        dateComponents.day = day
        dateComponents.hour = hour
        dateComponents.minute = minute
        dateComponents.second = second

        if let date = calendar.date(from: dateComponents) {
            self = date
            return
        }

        return nil
    }
}

extension Optional where Wrapped: RangeReplaceableCollection {
    mutating func appendOrCreate(value: Wrapped.Element) {
        if self != nil {
            self?.append(value)
        } else {
            self = Wrapped([value])
        }
    }
}
