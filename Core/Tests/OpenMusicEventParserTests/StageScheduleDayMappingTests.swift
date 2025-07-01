//
//  File.swift
//
//
//  Created by Woodrow Melling on 6/3/24.
//
import XCTest
import Foundation
@testable import OpenMusicEventParser
import Testing
import Parsing
import CustomDump
import InlineSnapshotTesting
import CoreModels

typealias ScheduleError = Validation.ScheduleError.StageDayScheduleError

struct StageScheduleDayMappingTests {
    let conversion = ScheduleConversion.DetermineFullSetTimesConversion()

    // MARK: - Success Cases
    @Test("Simple schedule before midnight converts successfully")
    func simpleBeforeMidnight() throws {
        let dtos = [
            Performance.YamlRepresentation(
                artist: "Sunspear",
                time: "4:30 PM"
            ),
            Performance.YamlRepresentation(
                artist: "Phantom Groove",
                time: "6:30 PM"
            ),
            Performance.YamlRepresentation(
                artist: "Oaktrail",
                time: "8:00 PM"
            ),
            Performance.YamlRepresentation(
                artist: "Rhythmbox",
                time: "10 PM",
                endTime: "11:30 PM"
            )
        ]

        let result = try conversion.apply(dtos)
        assertInlineSnapshot(of: result, as: .customDump) {
            """
            [
              [0]: (
                (extension in OpenMusicEventParser):Performance.YamlRepresentation(
                  title: nil,
                  artist: "Sunspear",
                  artists: nil,
                  time: ScheduleTime(
                    hour: 16,
                    minute: 30
                  ),
                  endTime: nil
                ),
                endTime: ScheduleTime(
                  hour: 18,
                  minute: 30
                )
              ),
              [1]: (
                (extension in OpenMusicEventParser):Performance.YamlRepresentation(
                  title: nil,
                  artist: "Phantom Groove",
                  artists: nil,
                  time: ScheduleTime(
                    hour: 18,
                    minute: 30
                  ),
                  endTime: nil
                ),
                endTime: ScheduleTime(
                  hour: 20,
                  minute: 0
                )
              ),
              [2]: (
                (extension in OpenMusicEventParser):Performance.YamlRepresentation(
                  title: nil,
                  artist: "Oaktrail",
                  artists: nil,
                  time: ScheduleTime(
                    hour: 20,
                    minute: 0
                  ),
                  endTime: nil
                ),
                endTime: ScheduleTime(
                  hour: 22,
                  minute: 0
                )
              ),
              [3]: (
                (extension in OpenMusicEventParser):Performance.YamlRepresentation(
                  title: nil,
                  artist: "Rhythmbox",
                  artists: nil,
                  time: ScheduleTime(
                    hour: 22,
                    minute: 0
                  ),
                  endTime: ScheduleTime(
                    hour: 23,
                    minute: 30
                  )
                ),
                endTime: ScheduleTime(
                  hour: 23,
                  minute: 30
                )
              )
            ]
            """
        }
    }

    @Test("Schedule through midnight converts successfully")
    func throughMidnight() throws {
        let dtos = [
            Performance.YamlRepresentation(
                artist: "Sunspear",
                time: "10:30 PM"
            ),
            Performance.YamlRepresentation(
                artist: "Phantom Groove",
                time: "12:30 AM"
            ),
            Performance.YamlRepresentation(
                artist: "Oaktrail",
                time: "2:00 AM"
            ),
            Performance.YamlRepresentation(
                artist: "Rhythmbox",
                time: "4 AM",
                endTime: "5:30 AM"
            )
        ]

        let result = try conversion.apply(dtos)
        assertInlineSnapshot(of: result, as: .customDump) {
            """
            [
              [0]: (
                (extension in OpenMusicEventParser):Performance.YamlRepresentation(
                  title: nil,
                  artist: "Sunspear",
                  artists: nil,
                  time: ScheduleTime(
                    hour: 22,
                    minute: 30
                  ),
                  endTime: nil
                ),
                endTime: ScheduleTime(
                  hour: 24,
                  minute: 30
                )
              ),
              [1]: (
                (extension in OpenMusicEventParser):Performance.YamlRepresentation(
                  title: nil,
                  artist: "Phantom Groove",
                  artists: nil,
                  time: ScheduleTime(
                    hour: 24,
                    minute: 30
                  ),
                  endTime: nil
                ),
                endTime: ScheduleTime(
                  hour: 26,
                  minute: 0
                )
              ),
              [2]: (
                (extension in OpenMusicEventParser):Performance.YamlRepresentation(
                  title: nil,
                  artist: "Oaktrail",
                  artists: nil,
                  time: ScheduleTime(
                    hour: 26,
                    minute: 0
                  ),
                  endTime: nil
                ),
                endTime: ScheduleTime(
                  hour: 28,
                  minute: 0
                )
              ),
              [3]: (
                (extension in OpenMusicEventParser):Performance.YamlRepresentation(
                  title: nil,
                  artist: "Rhythmbox",
                  artists: nil,
                  time: ScheduleTime(
                    hour: 28,
                    minute: 0
                  ),
                  endTime: ScheduleTime(
                    hour: 5,
                    minute: 30
                  )
                ),
                endTime: ScheduleTime(
                  hour: 29,
                  minute: 30
                )
              )
            ]
            """
        }
    }

    @Test("Back to back performances convert successfully")
    func backToBackPerformances() throws {
        let dtos = [
            Performance.YamlRepresentation(
                artist: "Sunspear",
                time: "4:30 PM",
                endTime: "5:30 PM"
            ),
            Performance.YamlRepresentation(
                artist: "Phantom Groove",
                time: "5:30 PM",
                endTime: "6:30 PM"
            )
        ]

        let result = try conversion.apply(dtos)

        assertInlineSnapshot(of: result, as: .customDump) {
            """
            [
              [0]: (
                (extension in OpenMusicEventParser):Performance.YamlRepresentation(
                  title: nil,
                  artist: "Sunspear",
                  artists: nil,
                  time: ScheduleTime(
                    hour: 16,
                    minute: 30
                  ),
                  endTime: ScheduleTime(
                    hour: 17,
                    minute: 30
                  )
                ),
                endTime: ScheduleTime(
                  hour: 17,
                  minute: 30
                )
              ),
              [1]: (
                (extension in OpenMusicEventParser):Performance.YamlRepresentation(
                  title: nil,
                  artist: "Phantom Groove",
                  artists: nil,
                  time: ScheduleTime(
                    hour: 17,
                    minute: 30
                  ),
                  endTime: ScheduleTime(
                    hour: 18,
                    minute: 30
                  )
                ),
                endTime: ScheduleTime(
                  hour: 18,
                  minute: 30
                )
              )
            ]
            """
        }
    }

    @Test("Empty schedule converts successfully")
    func emptySchedule() throws {
        let result = try conversion.apply([])
        assertInlineSnapshot(of: result, as: .customDump) {
            """
            []
            """
        }
    }

    // MARK: - Error Cases

    @Test("Overlapping performances throw error")
    func overlappingPerformances() throws {
        let dtos = [
            Performance.YamlRepresentation(
                artist: "Rhythmbox",
                time: "4 AM",
                endTime: "5:30 AM"
            ),
            Performance.YamlRepresentation(
                artist: "Rhythmbox",
                time: "5:00 AM",
                endTime: "6:30 AM"
            )
        ]

        do {
            _ = try conversion.apply(dtos)
        } catch {
            assertInlineSnapshot(of: error, as: .customDump) {
                """
                Validation.ScheduleError.StageDayScheduleError.overlappingPerformances(
                  (extension in OpenMusicEventParser):Performance.YamlRepresentation(
                    title: nil,
                    artist: "Rhythmbox",
                    artists: nil,
                    time: ScheduleTime(
                      hour: 4,
                      minute: 0
                    ),
                    endTime: ScheduleTime(
                      hour: 5,
                      minute: 30
                    )
                  ),
                  (extension in OpenMusicEventParser):Performance.YamlRepresentation(
                    title: nil,
                    artist: "Rhythmbox",
                    artists: nil,
                    time: ScheduleTime(
                      hour: 5,
                      minute: 0
                    ),
                    endTime: ScheduleTime(
                      hour: 6,
                      minute: 30
                    )
                  )
                )
                """
            }
        }
    }

    @Test("Overlapping performances at midnight throw error")
    func overlappingAtMidnight() throws {
        let dtos = [
            Performance.YamlRepresentation(
                artist: "Rhythmbox",
                time: "11:30 PM",
                endTime: "12:30 AM"
            ),
            Performance.YamlRepresentation(
                artist: "Rhythmbox",
                time: "11:45 PM",
                endTime: "1:30 AM"
            )
        ]

        do {
            _ = try conversion.apply(dtos)
        } catch {
            assertInlineSnapshot(of: error, as: .customDump) {
                """
                Validation.ScheduleError.StageDayScheduleError.overlappingPerformances(
                  (extension in OpenMusicEventParser):Performance.YamlRepresentation(
                    title: nil,
                    artist: "Rhythmbox",
                    artists: nil,
                    time: ScheduleTime(
                      hour: 23,
                      minute: 30
                    ),
                    endTime: ScheduleTime(
                      hour: 0,
                      minute: 30
                    )
                  ),
                  (extension in OpenMusicEventParser):Performance.YamlRepresentation(
                    title: nil,
                    artist: "Rhythmbox",
                    artists: nil,
                    time: ScheduleTime(
                      hour: 23,
                      minute: 45
                    ),
                    endTime: ScheduleTime(
                      hour: 1,
                      minute: 30
                    )
                  )
                )
                """
            }
        }
    }

    @Test("Missing end time throws error")
    func missingEndTime() throws {
        let dtos = [
            Performance.YamlRepresentation(
                artist: "Sunspear",
                time: "4:30 PM"
            ),
            Performance.YamlRepresentation(
                artist: "Phantom Groove",
                time: "6:30 PM"
            ),
            Performance.YamlRepresentation(
                artist: "Oaktrail",
                time: "8:00 PM"
            )
        ]

        do {
            _ = try conversion.apply(dtos)
        } catch {
            assertInlineSnapshot(of: error, as: .customDump) {
                """
                Validation.ScheduleError.StageDayScheduleError.cannotDetermineEndTimeForPerformance(
                  (extension in OpenMusicEventParser):Performance.YamlRepresentation(
                    title: nil,
                    artist: "Oaktrail",
                    artists: nil,
                    time: ScheduleTime(
                      hour: 20,
                      minute: 0
                    ),
                    endTime: nil
                  )
                )
                """
            }
        }

    }
}
