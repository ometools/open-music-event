//
//  File.swift
//
//
//  Created by Woodrow Melling on 6/12/24.
//

import Foundation
import Testing

@testable import OpenMusicEventParser
import Dependencies
import FileTree
import DependenciesTestSupport
import CustomDump
import SnapshotTestingCustomDump
import InlineSnapshotTesting
import CoreModels

fileprivate let day = CalendarDate(year: 2024, month: 6, day: 12)
fileprivate let calendar = { @Sendable in
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
}()

@Suite(.dependency(\.calendar, calendar))
struct DayScheduleConversionTests {
    
         @Test
         func multiStage() async throws {
             let dto = FileContent(fileName: "2024-06-12", fileType: "yaml", data: CoreModels.Schedule.YamlRepresentation(
                 customTitle: nil,
                 date: CalendarDate(year: 2024, month: 6, day: 12),
                 performances: [
                     "Bass Haven": [
                         Performance.YamlRepresentation(
                             artist: "Sunspear",
                             time: "4:30 PM"
                         ),
                         Performance.YamlRepresentation(
                             artist: "Phantom Groove",
                             time: "6:30 PM"
                         ),
                         Performance.YamlRepresentation(
                             artist: "Caribou State",
                             time: "8:00 PM",
                             endTime: "9:30 PM"
                         )
                     ],
                     "Main Stage": [
                         Performance.YamlRepresentation(
                             artist: "Oaktrail",
                             time: "8:00 PM"
                         ),
                         Performance.YamlRepresentation(
                             artist: "Rhythmbox",
                             time: "10:00 PM",
                             endTime: "11:30 PM"
                         )
                     ]
                 ]
             ))
    
             try assertInlineSnapshot(of: ScheduleConversion().apply(dto), as: .customDump) {
                 """
                 (extension in OpenMusicEventParser):Schedule.WithUnresolvedTimes(
                   metadata: (extension in OpenMusicEventParser):Schedule.WithUnresolvedTimes.Metadata(
                     date: 6/12/2024,
                     customTitle: nil
                   ),
                   stageSchedules: [
                     "Bass Haven": [
                       [0]: (extension in OpenMusicEventParser):Schedule.WithUnresolvedTimes.Performance(
                         title: "Sunspear",
                         subtitle: nil,
                         artistNames: Set([
                           "Sunspear"
                         ]),
                         startTime: ScheduleTime(
                           hour: 16,
                           minute: 30
                         ),
                         endTime: ScheduleTime(
                           hour: 18,
                           minute: 30
                         ),
                         stageName: "Bass Haven"
                       ),
                       [1]: (extension in OpenMusicEventParser):Schedule.WithUnresolvedTimes.Performance(
                         title: "Phantom Groove",
                         subtitle: nil,
                         artistNames: Set([
                           "Phantom Groove"
                         ]),
                         startTime: ScheduleTime(
                           hour: 18,
                           minute: 30
                         ),
                         endTime: ScheduleTime(
                           hour: 20,
                           minute: 0
                         ),
                         stageName: "Bass Haven"
                       ),
                       [2]: (extension in OpenMusicEventParser):Schedule.WithUnresolvedTimes.Performance(
                         title: "Caribou State",
                         subtitle: nil,
                         artistNames: Set([
                           "Caribou State"
                         ]),
                         startTime: ScheduleTime(
                           hour: 20,
                           minute: 0
                         ),
                         endTime: ScheduleTime(
                           hour: 21,
                           minute: 30
                         ),
                         stageName: "Bass Haven"
                       )
                     ],
                     "Main Stage": [
                       [0]: (extension in OpenMusicEventParser):Schedule.WithUnresolvedTimes.Performance(
                         title: "Oaktrail",
                         subtitle: nil,
                         artistNames: Set([
                           "Oaktrail"
                         ]),
                         startTime: ScheduleTime(
                           hour: 20,
                           minute: 0
                         ),
                         endTime: ScheduleTime(
                           hour: 22,
                           minute: 0
                         ),
                         stageName: "Main Stage"
                       ),
                       [1]: (extension in OpenMusicEventParser):Schedule.WithUnresolvedTimes.Performance(
                         title: "Rhythmbox",
                         subtitle: nil,
                         artistNames: Set([
                           "Rhythmbox"
                         ]),
                         startTime: ScheduleTime(
                           hour: 22,
                           minute: 0
                         ),
                         endTime: ScheduleTime(
                           hour: 23,
                           minute: 30
                         ),
                         stageName: "Main Stage"
                       )
                     ]
                   ]
                 )
                 """
             }
         }

    @Test
    func testSingleStage() async throws {
        let dto = FileContent(fileName: "2024-06-12", fileType: "yaml", data: CoreModels.Schedule.YamlRepresentation(
            customTitle: nil,
            date: day,
            performances: [
                "Bass Haven": [
                    Performance.YamlRepresentation(
                        artist: "Sunspear",
                        time: "6:30 PM"
                    ),
                    Performance.YamlRepresentation(
                        artist: "Phantom Groove",
                        time: "10:30 PM"
                    ),
                    Performance.YamlRepresentation(
                        artist: "Oaktrail",
                        time: "12:30 AM"
                    ),
                    Performance.YamlRepresentation(
                        artist: "Rhythmbox",
                        time: "4:00 AM",
                        endTime: "7:30 AM"
                    )
                ]
            ]
        ))

        try assertInlineSnapshot(of: ScheduleConversion().apply(dto), as: .customDump) {
            """
            (extension in OpenMusicEventParser):Schedule.WithUnresolvedTimes(
              metadata: (extension in OpenMusicEventParser):Schedule.WithUnresolvedTimes.Metadata(
                date: 6/12/2024,
                customTitle: nil
              ),
              stageSchedules: [
                "Bass Haven": [
                  [0]: (extension in OpenMusicEventParser):Schedule.WithUnresolvedTimes.Performance(
                    title: "Sunspear",
                    subtitle: nil,
                    artistNames: Set([
                      "Sunspear"
                    ]),
                    startTime: ScheduleTime(
                      hour: 18,
                      minute: 30
                    ),
                    endTime: ScheduleTime(
                      hour: 22,
                      minute: 30
                    ),
                    stageName: "Bass Haven"
                  ),
                  [1]: (extension in OpenMusicEventParser):Schedule.WithUnresolvedTimes.Performance(
                    title: "Phantom Groove",
                    subtitle: nil,
                    artistNames: Set([
                      "Phantom Groove"
                    ]),
                    startTime: ScheduleTime(
                      hour: 22,
                      minute: 30
                    ),
                    endTime: ScheduleTime(
                      hour: 24,
                      minute: 30
                    ),
                    stageName: "Bass Haven"
                  ),
                  [2]: (extension in OpenMusicEventParser):Schedule.WithUnresolvedTimes.Performance(
                    title: "Oaktrail",
                    subtitle: nil,
                    artistNames: Set([
                      "Oaktrail"
                    ]),
                    startTime: ScheduleTime(
                      hour: 24,
                      minute: 30
                    ),
                    endTime: ScheduleTime(
                      hour: 28,
                      minute: 0
                    ),
                    stageName: "Bass Haven"
                  ),
                  [3]: (extension in OpenMusicEventParser):Schedule.WithUnresolvedTimes.Performance(
                    title: "Rhythmbox",
                    subtitle: nil,
                    artistNames: Set([
                      "Rhythmbox"
                    ]),
                    startTime: ScheduleTime(
                      hour: 28,
                      minute: 0
                    ),
                    endTime: ScheduleTime(
                      hour: 31,
                      minute: 30
                    ),
                    stageName: "Bass Haven"
                  )
                ]
              ]
            )
            """
        }
    }
}
