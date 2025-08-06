//
//  ScheduleDayConversion.swift
//  OpenFestival
//
//  Created by Woodrow Melling on 10/31/24.
//


import FileTree
import Foundation
import FileTree
import IssueReporting
import CoreModels
import Collections
import Dependencies

extension CoreModels.Performance {
    struct YamlRepresentation: Codable, Equatable {
        var title: String?
        var artist: String?
        var artists: [String]?
        var time: ScheduleTime
        var endTime: ScheduleTime?


        var startTime: ScheduleTime {
            time
        }

        var customTitle: String? { title }
    }
}


// INPUT
extension CoreModels.Schedule {
    struct YamlRepresentation: Codable, Equatable {
        internal init(customTitle: String? = nil, date: CalendarDate? = nil, performances: [String : [Performance.YamlRepresentation]]) {
            self.customTitle = customTitle
            self.date = date
            self.performances = performances
        }

        var customTitle: String?
        var date: CalendarDate? // This could be defined in the yaml, or from the title of the file
        var performances: [String: [Performance.YamlRepresentation]]
//
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()

            do {
                let keyedContainer = try decoder.container(keyedBy: CodingKeys.self)
                self.date = try? keyedContainer.decode(CalendarDate.self, forKey: .date)
                self.customTitle = try? keyedContainer.decode(String.self, forKey: .customTitle)
                self.performances = try keyedContainer.decode([String: [Performance.YamlRepresentation]].self, forKey: .performances)
            } catch {
                self.performances = try container.decode([String: [Performance.YamlRepresentation]].self)
                self.customTitle = nil
                self.date = nil
            }
        }

        enum CodingKeys: String, CodingKey {
            case date
            case customTitle
            case performances
        }
    }
}

struct ScheduleConversion: Conversion {

    typealias Input = FileContent<CoreModels.Schedule.YamlRepresentation>
    typealias Output = CoreModels.Schedule.WithUnresolvedTimes

    func apply(_ input: FileContent<Schedule.YamlRepresentation>) throws -> Output {
        let fullSetTimes = try input.data.performances.mapValues { performances in
            try DetermineFullSetTimesConversion().apply(performances)
        }

        return try FileContentToTupleScheduleDayConversion().apply(
            (input, fullSetTimes)
        )
    }

    struct DetermineFullSetTimesConversion: Conversion {
        typealias Input = [Performance.YamlRepresentation]
        typealias Output = [(Performance.YamlRepresentation, endTime: ScheduleTime)]

        func apply(_ partialPerformances: Input) throws(Validation.ScheduleError.StageDayScheduleError) -> Output {
            var schedule: Output = []
            var scheduleStartTime: ScheduleTime?

            for (index, performance) in partialPerformances.enumerated() {
                var startTime = performance.startTime
                var endTime: ScheduleTime

                // End times can be manually set
                if let staticEndTime = performance.endTime {
                    endTime = staticEndTime

                    // If they aren't, find the next performance, and make the endtime butt up against it
                } else if let nextPerformance = partialPerformances[safe: index + 1] {
                    endTime = nextPerformance.startTime

                    // If there aren't any performances after this, we can't determine the endtime
                } else {
                    throw .cannotDetermineEndTimeForPerformance(performance)
                }

                if let scheduleStartTime {
                    if startTime < scheduleStartTime {
                        startTime.hour += 24
                    }

                    if endTime < scheduleStartTime {
                        endTime.hour += 24
                    }
                } else {
                    scheduleStartTime = startTime
                    if endTime < startTime {
                        endTime.hour += 24
                    }
                }
                var performance = performance
                performance.time = startTime

                schedule.append((performance, endTime: endTime))
            }

            for (index, (performance, endTime)) in schedule.enumerated() {
                guard let (nextPerformance, nextEndTime) = schedule[safe: index + 1]
                else { continue }

                guard endTime <= nextPerformance.startTime
                else { throw .overlappingPerformances(performance, nextPerformance) }

                guard performance.startTime < nextEndTime
                else { throw .endTimeBeforeStartTime(performance) }
            }

            return schedule
        }

        func unapply(_ performances: Output) throws -> Input {
            throw UnimplementedFailure(description: "DetermineFullSetTimesConversion.unapply")
//            // remove end times for schedules that butt up against each other.
//            for (index, performance) in schedule.enumerated() {
//                if let nextPerformance = performances[safe: index + 1],
//                   performance.endTime == nextPerformance.startTime {
//                    schedule[index].endTime = nil
//                }
//            }
//
//            return schedule
        }
    }
    func unapply(_ input: Output) throws -> FileContent<CoreModels.Schedule.YamlRepresentation> {
        throw UnimplementedFailure(description: "Cannot unapply ScheduleConversion")
    }

    struct FileContentToTupleScheduleDayConversion: Conversion {
        typealias Input = (FileContent<Schedule.YamlRepresentation>, [String: [(Performance.YamlRepresentation, endTime: ScheduleTime)]])
        typealias Output = Schedule.WithUnresolvedTimes

        func apply(_ input: Input) throws -> Output {
            @Dependency(\.omeLogger) var logger
            
            let customTitle = input.0.data.customTitle
            let dateFromYaml = input.0.data.date
            let dateFromFileName = CalendarDate(input.0.fileName)

            logger.debug("FileContentToTupleScheduleDayConversion: fileName='\(input.0.fileName)', dateFromYaml=\(dateFromYaml?.description ?? "nil"), dateFromFileName=\(dateFromFileName?.description ?? "nil")")

            let scheduleDate: CalendarDate
            if let dateFromYaml, let dateFromFileName, dateFromYaml != dateFromFileName {
                reportIssue("Date from filename (\(dateFromFileName)) does not match date from YAML (\(dateFromYaml)), using date from filename: \(dateFromFileName)")
                scheduleDate = dateFromFileName
                logger.debug("FileContentToTupleScheduleDayConversion: date conflict resolved, using dateFromFileName=\(scheduleDate.description)")
            } else {
                scheduleDate = (dateFromFileName ?? dateFromYaml ?? .today)
                logger.debug("FileContentToTupleScheduleDayConversion: final scheduleDate=\(scheduleDate.description)")
            }
            


            let schedule = try input.1.mapValuesWithKeys { key, value in
                try value.map {
                    let title: String
                    let artistNames = try getArtists(artist: $0.0.artist, artists: $0.0.artists)

                    if let customTitle = $0.0.customTitle {
                        title = customTitle
                    } else if artistNames.isEmpty {
                        reportIssue("Artists is empty")
                        title = ""

                    }  else if artistNames.count == 1 {
                        title = artistNames.first!
                    } else {
                        title = artistNames.joined(separator: ", ")
                    }

                    return Schedule.WithUnresolvedTimes.Performance(
                        title: title,
                        subtitle: nil,
                        artistNames: artistNames,
                        startTime: $0.0.startTime,
                        endTime: $0.endTime,
                        stageName: key
                    )
                }
            }

            return Schedule.WithUnresolvedTimes(
                metadata: .init(
                    date: scheduleDate,
                    customTitle: customTitle
                ),
                stageSchedules: schedule
            )
        }

        func unapply(_ output: Output) throws -> Input {
            throw UnimplementedFailure(description: "FileContentToTupleScheduleDayConversion.unapply not implemented")
        }

        func getArtists(artist: String?, artists: [String]?) throws -> OrderedSet<String> {
            typealias PerformanceError = Validation.ScheduleError.PerformanceError
            switch (artist, artists) {
            case (.none, .none): return []
            case (.some, .some): throw PerformanceError.artistAndArtists
            case (.some(let artistName), .none):
                guard artistName.hasElements
                else { throw PerformanceError.emptyArtist }

                return OrderedSet([artistName])

            case (.none, .some(let artists)):
                guard artists.hasElements
                else { throw PerformanceError.emptyArtists  }

                return OrderedSet(artists)
            }
        }
    }


}
//
//  StageDayScheduleError.swift
//  open-music-event
//
//  Created by Woodrow Melling on 5/29/25.
//

import Foundation

enum Validation: Error {
    case stage(Stage)
    case generic
    case schedule(ScheduleError)
    case artist

    enum Stage: Error {
        case generic
    }

    enum ScheduleError: Error {
//        case daySchedule(DayScheduleError)
    }
}

extension Validation.ScheduleError {
    enum StageDayScheduleError: Equatable, Error {
        case unimplemented
        case performanceError(PerformanceError)
        case cannotDetermineEndTimeForPerformance(Performance.YamlRepresentation)
        case endTimeBeforeStartTime(Performance.YamlRepresentation)
        case overlappingPerformances(Performance.YamlRepresentation, Performance.YamlRepresentation)

        var localizedDescription: String {
            switch self {
            case .unimplemented:
                return "This feature is not yet implemented"
            case .performanceError(let error):
                return error.localizedDescription
            case .cannotDetermineEndTimeForPerformance:
                return "Cannot determine end time for performance"
            case .endTimeBeforeStartTime(let performance):
                guard let endTime = performance.endTime
                else {
                    reportIssue("Having a null performance here shouldn't be possible, and can get resolved in the type system")
                    return ""
                }
                return "End time \(endTime) is before start time \(performance.startTime)"
            case .overlappingPerformances:
                return "Performances are overlapping"
            }
        }


    }

    enum PerformanceError: Error, CustomStringConvertible, Equatable {
        case invalidStartTime(ScheduleTimeDecodingError)
        case invalidEndTime(String)
        case artistAndArtists
        case noArtistsOrTitle
        case emptyArtist
        case emptyArtists
        case unknownError

        var description: String {
            switch self {
            case .invalidStartTime(let time): "Unable to parse start time: \(time)"
            case .invalidEndTime(let time): "Unable to parse end time: \(time)"
            case .artistAndArtists: "Cannot have both artist and artists for a performance"
            case .noArtistsOrTitle: "You must provide at least one artist or a title for each set"
            case .emptyArtist: "artist field must have an artist"
            case .emptyArtists: "artists field must have at least one artist"
            case .unknownError: "Failed to parse performance"
            }
        }
    }
}



