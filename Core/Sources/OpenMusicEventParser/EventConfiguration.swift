//
//  File.swift
//
//
//  Created by Woody on 2/10/22.
//

import Foundation
import Tagged
import Collections
import CoreModels

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

    public init(
        info: CoreModels.MusicEvent.Draft,
        artists: [CoreModels.Artist.Draft],
        stages: [CoreModels.Stage.Draft],
        schedule: [Schedule.StringlyTyped],
        stageLineups: StageLineups?
    ) {
        self.info = info
        self.artists = artists
        self.stages = stages
        self.schedule = schedule
        self.stageLineups = stageLineups
    }
}

extension EventConfiguration {
    public typealias StageLineups = [Stage.Name: StageLineup]
    public struct StageLineup: Equatable, Sendable, Codable {
        public var posterURL: URL?
        public var artists: [Artist.Name]
    }
}

import StructuredQueriesCore

extension CoreModels.Schedule {
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
