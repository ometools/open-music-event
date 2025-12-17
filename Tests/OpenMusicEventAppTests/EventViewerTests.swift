//
//  EventViewerTests.swift
//  open-music-event
//
//  Created by Woodrow Melling on 6/20/25.
//


//
//  EventListTests.swift
//  open-music-event
//
//  Created by Woodrow Melling on 6/20/25.
//

import Testing
@testable import OpenMusicEvent
import SnapshotTestingCustomDump
import InlineSnapshotTesting

extension OpenMusicEventBaseTestSuite {
    @MainActor
    @Suite
    struct EventViewerTests {
        @Test
        func loadsFullEvent() async throws {
            let eventViewer = MusicEventViewer(eventID: MusicEvent.testival.id)

            await eventViewer.task()

            assertInlineSnapshot(of: (eventViewer.eventFeatures?.event, eventViewer.eventFeatures), as: .customDump(maxDepth: 2)) {
                """
                (
                  nil,
                  MusicEventFeatures(
                    _event: nil,
                    _selectedFeature: .schedule,
                    _schedule: nil,
                    _workshopsSchedule: nil,
                    _artists: ArtistsList(…),
                    _location: nil,
                    _contactInfo: nil,
                    _communications: nil,
                    _notifications: nil,
                    _edits: nil,
                    _shouldShowArtistImages: true,
                    _isLoadingOrganizer: false,
                    _errorMessage: nil,
                    _musicEventID: Dependency(…),
                    _database: Dependency(…),
                    _calendar: Dependency(…)
                  )
                )
                """
            }
        }


        @Test
        func loadsMinimalEvent() async throws {
            let eventViewer = MusicEventViewer(eventID:
                                                "2")

            await eventViewer.task()

            

            assertInlineSnapshot(of: (eventViewer.eventFeatures?.event, eventViewer.eventFeatures), as: .customDump(maxDepth: 2)) {
                """
                (
                  nil,
                  MusicEventFeatures(
                    _event: nil,
                    _selectedFeature: .schedule,
                    _schedule: nil,
                    _workshopsSchedule: nil,
                    _artists: ArtistsList(…),
                    _location: nil,
                    _contactInfo: nil,
                    _communications: nil,
                    _notifications: nil,
                    _edits: nil,
                    _shouldShowArtistImages: true,
                    _isLoadingOrganizer: false,
                    _errorMessage: nil,
                    _musicEventID: Dependency(…),
                    _database: Dependency(…),
                    _calendar: Dependency(…)
                  )
                )
                """
            }

        }
    }
}
