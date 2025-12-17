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
// import Sharing

extension OpenMusicEventBaseTestSuite {
    @MainActor
    @Suite()
    struct OrganizationLoadingAndSelectionTests {
        @Test
        func testOrgListLoadsNavtoOrgDetailSelectAnEvent() async throws {
            // TODO: Replace @Shared(.eventID) with proper state management
            // @Shared(.eventID) var eventID
            // $eventID.withLock { $0 = nil }
//            var eventID: MusicEvent.ID? = nil
//
//            let store = OMEAppEntryPoint.Model()
//            await store.onFirstAppear()
//            await store.organizerList.onAppear()
//
////            try #require(store.musicEventViewer == nil)
////            try #require(store. == nil)
//
//            // Ensure all the organizers are loaded
//            assertInlineSnapshot(of: store.organizerList.organizations, as: .customDump) {
//                """
//                []
//                """
//            }

            // Select the "Test Tools" Organization
//            store.organizerList.didTapOrganization(.init(url: <#T##URL#>, organization: <#T##OrganizerListView.Model.Organization#>))(id: Organizer.omeTools.id)
//
//            // Ensure we've navigated there
//            guard case let .organizerDetail(orgDetailStore) = store.organizerList.destination else {
//                Issue.record()
//                return
//            }
//
//            await orgDetailStore.onAppear()
//
//            assertInlineSnapshot(of: (orgDetailStore.events, orgDetailStore.organizer), as: .customDump) {
//                """
//                (
//                  [
//                    [0]: MusicEvent(
//                      id: Tagged(rawValue: 2),
//                      organizerURL: URL(https://github.com/ometools/test-ome-config/archive/refs/heads/main.zip),
//                      name: "Nightfall Collective",
//                      timeZone: TimeZone(
//                        identifier: "America/Vancouver",
//                        abbreviation: "PDT",
//                        secondsFromGMT: -25200,
//                        isDaylightSavingTime: true
//                      ),
//                      startTime: Date(2009-02-13T23:31:30.000Z),
//                      endTime: Date(2009-02-16T23:31:30.000Z),
//                      iconImageURL: nil,
//                      imageURL: nil,
//                      siteMapImageURL: nil,
//                      location: nil,
//                      contactNumbers: []
//                    ),
//                    [1]: MusicEvent(
//                      id: Tagged(rawValue: 3),
//                      organizerURL: URL(https://github.com/ometools/test-ome-config/archive/refs/heads/main.zip),
//                      name: "Beats & Botanicals",
//                      timeZone: TimeZone(
//                        identifier: "America/Los_Angeles",
//                        abbreviation: "PDT",
//                        secondsFromGMT: -25200,
//                        isDaylightSavingTime: true
//                      ),
//                      startTime: Date(2009-02-13T23:31:30.000Z),
//                      endTime: Date(2009-02-14T23:31:30.000Z),
//                      iconImageURL: nil,
//                      imageURL: nil,
//                      siteMapImageURL: nil,
//                      location: nil,
//                      contactNumbers: []
//                    ),
//                    [2]: MusicEvent(
//                      id: Tagged(rawValue: 1),
//                      organizerURL: URL(https://github.com/ometools/test-ome-config/archive/refs/heads/main.zip),
//                      name: "Testival",
//                      timeZone: TimeZone(
//                        identifier: "America/Los_Angeles",
//                        abbreviation: "PDT",
//                        secondsFromGMT: -25200,
//                        isDaylightSavingTime: true
//                      ),
//                      startTime: nil,
//                      endTime: nil,
//                      iconImageURL: nil,
//                      imageURL: nil,
//                      siteMapImageURL: URL(https://firebasestorage.googleapis.com/v0/b/festivl.appspot.com/o/userContent%2FSite%20Map.webp?alt=media&token=48272d3c-ace0-4d5b-96a9-a5142f1c744a),
//                      location: MusicEvent.Location(
//                        address: "3901 Kootenay Hwy, Fairmont Hot Springs, BC V0B 1L1, Canada",
//                        directions: "Get back on San Vincente, take it to the 10, then switch over to the 405 north, and let it dump you onto Mullholland where you belong!",
//                        coordinates: MusicEvent.Location.Coordinates(
//                          latitude: 50.366265,
//                          longitude: -115.871286
//                        )
//                      ),
//                      contactNumbers: [
//                        [0]: MusicEvent.ContactNumber(
//                          phoneNumber: "5555551234",
//                          title: "Emergency Services",
//                          description: "This will connect you directly with our switchboard, and alert the appropriate services."
//                        ),
//                        [1]: MusicEvent.ContactNumber(
//                          phoneNumber: "5555554321",
//                          title: "General Information Line",
//                          description: "For general information, questions or concerns, or to report any sanitation issues within the WW grounds, please contact this number."
//                        )
//                      ]
//                    )
//                  ],
//                  Organizer(
//                    url: URL(https://github.com/ometools/test-ome-config/archive/refs/heads/main.zip),
//                    name: "Open Music Event",
//                    imageURL: nil,
//                    iconImageURL: URL(https://firebasestorage.googleapis.com/v0/b/festivl.appspot.com/o/userContent%2Flogo_small.png?alt=media&token=7766fa90-6591-4e25-92b4-2ff354cb970d)
//                  )
//                )
//                """
//            }
//
//
//            orgDetailStore.didTapEvent(id: 0)
//            // TODO: Replace $eventID.load() with proper state loading
//            // try await store.$eventID.load()
//
//            #expect(store.eventID == 0)
//            #expect(store.musicEventViewer?.id == 0)
        }
    }
    
}
