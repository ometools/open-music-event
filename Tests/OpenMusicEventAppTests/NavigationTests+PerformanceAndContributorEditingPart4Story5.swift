import Bluesky
import ATProto
import Clocks
import ComposableArchitecture2
import ComposableNotifications
import CustomDump
import Dependencies
import DependenciesTestSupport
import DebugSnapshots
import Foundation
import IssueReporting
import Observation
import OpenMusicEventDatabase
import OpenMusicEventAuthentication
import OpenMusicEventImages
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceEditing
import OpenMusicEventWhiteLabel
import Sharing
import SQLiteData
import SourceEditing
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif
import Testing
import ATProto

@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer
@testable import OpenMusicEventEditors

extension NavigationTests {
    @Test
    func eventViewerContactInfoEditorSavesMultipleReportingLinksToDefaultDatabase() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
        }

        var state = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.defaultDatabase = database
        } operation: {
            EventViewer.State(eventID: eventID)
        }
        state.handleEditingIntent(.editContactInfo(eventID))

        @Bindable var store = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: state) {
                EventViewer()
            }
        }

        let destinationStore = try #require(store.scope(\.destination))
        let contactInfoStore: StoreOf<EditContactInfo>
        switch EventViewer.Destination.switch(store: destinationStore) {
        case let .contactInfoForm(store):
            contactInfoStore = store
        default:
            Issue.record("Expected contact info form destination")
            return
        }

        await waitUntil {
            contactInfoStore.hasLoadedDraft
        }
        @Bindable var editableContactInfoStore = contactInfoStore
        await editableContactInfoStore.send(.addReportingLinkButtonTapped)?.value
        await editableContactInfoStore.send(.addReportingLinkButtonTapped)?.value
        $editableContactInfoStore.reportingLinks[0].title.wrappedValue = "Report an Incident"
        $editableContactInfoStore.reportingLinks[0].destinationString.wrappedValue = "https://example.org/report"
        $editableContactInfoStore.reportingLinks[0].description.wrappedValue = "Event support form."
        $editableContactInfoStore.reportingLinks[1].title.wrappedValue = "Accessibility Help"
        $editableContactInfoStore.reportingLinks[1].destinationString.wrappedValue = "https://example.org/accessibility"

        await editableContactInfoStore.send(.saveButtonTapped)?.value

        let expectedReportingLinks = [
            OME.Link(
                url: try #require(URL(string: "https://example.org/report")),
                title: "Report an Incident",
                description: "Event support form.",
                role: .known(.reporting(.init()))
            ),
            OME.Link(
                url: try #require(URL(string: "https://example.org/accessibility")),
                title: "Accessibility Help",
                role: .known(.reporting(.init()))
            ),
        ]
        let savedReportingLinks = try await database.read { db in
            try #require(
                try Event
                    .where { $0.id.eq(eventID) }
                    .fetchOne(db)?
                    .reportingLinks
            )
        }

        expectNoDifference(savedReportingLinks, expectedReportingLinks)
    }

}
