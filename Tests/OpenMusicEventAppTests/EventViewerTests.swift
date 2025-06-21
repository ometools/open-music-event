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
            let eventViewer = MusicEventViewer.Model(eventID: MusicEvent.testival.id)

            await eventViewer.onAppear()

            assertInlineSnapshot(of: (eventViewer.eventFeatures?.event, eventViewer.eventFeatures), as: .customDump(maxDepth: 2)) {
                """
                (
                  MusicEvent(
                    id: Tagged(rawValue: 1),
                    organizerURL: URL(https://github.com/ometools/test-ome-config/archive/refs/heads/main.zip),
                    name: "Testival",
                    timeZone: TimeZone(…),
                    startTime: nil,
                    endTime: nil,
                    iconImageURL: nil,
                    imageURL: nil,
                    siteMapImageURL: URL(https://firebasestorage.googleapis.com/v0/b/festivl.appspot.com/o/userContent%2FSite%20Map.webp?alt=media&token=48272d3c-ace0-4d5b-96a9-a5142f1c744a),
                    location: MusicEvent.Location(…),
                    contactNumbers: […]
                  ),
                  MusicEventFeatures(
                    _event: FetchOne(…),
                    _selectedFeature: .schedule,
                    _schedule: ScheduleFeature(…),
                    _artists: ArtistsList(…),
                    _location: LocationFeature(…),
                    _contactInfo: ContactInfoFeature(…),
                    _more: MoreTabFeature(…),
                    _shouldShowArtistImages: false
                  )
                )
                """
            }
        }


        @Test
        func loadsMinimalEvent() async throws {
            let eventViewer = MusicEventViewer.Model(eventID: 2)

            await eventViewer.onAppear()

            

            assertInlineSnapshot(of: (eventViewer.eventFeatures?.event, eventViewer.eventFeatures), as: .customDump(maxDepth: 2)) {
                """
                (
                  MusicEvent(
                    id: Tagged(rawValue: 2),
                    organizerURL: URL(https://github.com/ometools/test-ome-config/archive/refs/heads/main.zip),
                    name: "Nightfall Collective",
                    timeZone: TimeZone(…),
                    startTime: Date(2009-02-13T23:31:30.000Z),
                    endTime: Date(2009-02-16T23:31:30.000Z),
                    iconImageURL: nil,
                    imageURL: nil,
                    siteMapImageURL: nil,
                    location: nil,
                    contactNumbers: []
                  ),
                  MusicEventFeatures(
                    _event: FetchOne(…),
                    _selectedFeature: .schedule,
                    _schedule: nil,
                    _artists: ArtistsList(…),
                    _location: nil,
                    _contactInfo: nil,
                    _more: MoreTabFeature(…),
                    _shouldShowArtistImages: false
                  )
                )
                """
            }

        }
    }
}
