import Clocks
import ATProto
import ATProtoTypes
import ComposableArchitecture2
import CustomDump
import Dependencies
import Foundation
import OpenMusicEventLexicon
import SQLiteData
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif
import Testing

@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer
@testable import OpenMusicEventEditors

@MainActor
@Suite
struct ContactInfoTests {
    @Test
    func reportingLinksAreAvailableInContactAndCommunications() async throws {
        let database = try makeContactInfoDatabase()
        let eventID = try contactInfoEventID()
        let reportingLinks = [
            reportingLink(
                name: "Safety Concern",
                url: "https://example.org/safety",
                description: "Contact the event safety team."
            ),
            reportingLink(
                name: "Accessibility Help",
                url: "https://example.org/accessibility"
            ),
        ]
        try await insertContactInfoEvent(
            eventID,
            links: reportingLinks,
            into: database
        )

        let contactStore = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: ContactInfoViewer.State(eventID: eventID)) {
                ContactInfoViewer()
            }
        }
        let communicationsStore = withDependencies {
            $0.context = .test
            $0.defaultEventID = eventID
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: SocialCategoryList.State(eventID: eventID)) {
                SocialCategoryList()
            }
        }

        // Reporting links make both attendee surfaces available from the same event data.
        #expect(contactStore.hasContent)
        #expect(communicationsStore.hasContent)
        expectNoDifference(contactStore.event?.reportingLinks, reportingLinks)
        expectNoDifference(communicationsStore.event?.reportingLinks, reportingLinks)
    }

    @Test
    func contactEditButtonRequestsTheContactEditor() async throws {
        let database = try makeContactInfoDatabase()
        try await TestExhaustivity.$current.withValue(.off) {
            let eventID = try contactInfoEventID()
            let store = withDependencies {
                $0.context = .test
                $0.defaultDatabase = database
            } operation: {
                TestStore(initialState: ContactInfoViewer.State(eventID: eventID)) {
                    ContactInfoViewer()
                }
            }

            let editTask = store.send(.editButtonTapped)
            await store.receive(
                key: EventEditingRequested.self,
                value: .equals(.editContactInfo(eventID)),
                timeout: .seconds(1)
            )
            await editTask?.value
        }
    }

    @Test
    func contactEditorSavesReportingLinksWithoutChangingOtherEventLinks() async throws {
        let database = try makeContactInfoDatabase()
        let eventID = try contactInfoEventID()
        let website = OME.Link(
            url: try #require(URL(string: "https://example.org")),
            title: "Website", role: .known(.website(.init()))
        )
        let contact = OME.Link(
            url: try #require(URL(string: "tel:+15550100")),
            title: "Event Support", description: "Call during event hours.",
            role: .known(.contact(.init(use: .known(.nonEmergency))))
        )
        let originalReportingLinks = [
            reportingLink(name: "Safety Concern", url: "https://example.org/safety"),
            reportingLink(name: "Accessibility Help", url: "https://example.org/accessibility"),
        ]
        try await insertContactInfoEvent(
            eventID,
            links: [website, contact] + originalReportingLinks,
            into: database
        )

        @Bindable var store = makeContactInfoEditorStore(database: database, eventID: eventID)

        #expect(store.hasLoadedDraft)
        expectNoDifference(store.reportingLinks.map(\.title), ["Safety Concern", "Accessibility Help"])
        $store.contactLinks[0].destinationString.wrappedValue = "sms:+15550100"
        $store.contactLinks[0].useChoice.wrappedValue = "emergency"
        let removedLinkID = store.reportingLinks[1].id
        await store.send(.removeReportingLinkButtonTapped(removedLinkID))?.value
        await store.send(.addReportingLinkButtonTapped)?.value
        $store.reportingLinks[0].title.wrappedValue = "  Event Safety  "
        $store.reportingLinks[0].description.wrappedValue = "  Help from the safety team.  "
        $store.reportingLinks[1].title.wrappedValue = "  Lost and Found  "
        $store.reportingLinks[1].destinationString.wrappedValue = "  https://example.org/lost  "

        // Another editor changes the event name while this contact form is open.
        try await database.write { db in
            var latest = try #require(try Event.find(eventID).fetchOne(db))
            latest.name = "Renamed Contact Event"
            try Event.upsert { latest }.execute(db)
        }
        await store.send(.saveButtonTapped)?.value

        let savedEvent = try await fetchContactInfoEvent(eventID, from: database)
        expectNoDifference(savedEvent.name, "Renamed Contact Event")
        var updatedContact = contact
        updatedContact.url = try #require(URL(string: "sms:+15550100"))
        updatedContact.role = .known(.contact(.init(use: .known(.emergency))))
        expectNoDifference(savedEvent.contactLinks, [updatedContact])
        expectNoDifference(
            savedEvent.links,
            [
                website,
                updatedContact,
                reportingLink(
                    name: "Event Safety",
                    url: "https://example.org/safety",
                    description: "Help from the safety team."
                ),
                reportingLink(name: "Lost and Found", url: "https://example.org/lost"),
            ]
        )
    }

    @Test
    func contactEditorRejectsIncompleteReportingLinksWithoutWriting() async throws {
        let database = try makeContactInfoDatabase()
        let eventID = try contactInfoEventID()
        try await insertContactInfoEvent(eventID, into: database)

        @Bindable var store = makeContactInfoEditorStore(database: database, eventID: eventID)
        await store.send(.addReportingLinkButtonTapped)?.value
        $store.reportingLinks[0].destinationString.wrappedValue = "https://example.org/report"

        await store.send(.saveButtonTapped)?.value

        #expect(store.errorMessage == "Enter a reporting link name.")
        #expect(try await fetchContactInfoEvent(eventID, from: database).links == nil)

        $store.reportingLinks[0].title.wrappedValue = "Report an Incident"
        $store.reportingLinks[0].destinationString.wrappedValue = "ftp://example.org/report"

        await store.send(.saveButtonTapped)?.value

        #expect(store.errorMessage == "Enter a valid phone number, email, or URL.")
        #expect(try await fetchContactInfoEvent(eventID, from: database).links == nil)
    }
}

func contactInfoEventID() throws -> Event.ID {
    try #require(Event.ID(
        "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"
    ))
}

func reportingLink(
    name: String,
    url: String,
    description: String? = nil
) -> OME.Link {
    OME.Link(
        url: URL(string: url)!, title: name, description: description,
        role: .known(.reporting(.init()))
    )
}

func makeContactInfoDatabase() throws -> any DatabaseWriter {
    try withDependencies {
        $0.context = .test
        try OME.prepareDependencies(&$0)
    } operation: {
        @Dependency(\.defaultDatabase) var database
        return database
    }
}

@MainActor
func makeContactInfoEditorStore(
    database: any DatabaseWriter,
    eventID: Event.ID
) -> StoreOf<EditContactInfo> {
    withDependencies {
        $0.context = .test
        $0.continuousClock = ImmediateClock()
        $0.defaultDatabase = database
    } operation: {
        Store(initialState: EditContactInfo.State(eventID: eventID)) {
            EditContactInfo()
        }
    }
}

func insertContactInfoEvent(
    _ eventID: Event.ID,
    links: [OME.Link] = [],
    into database: any DatabaseWriter
) async throws {
    try await database.write { db in
        let event = try Event(
            id: eventID, name: "Contact Event", createdAt: "2026-09-01T12:00:00Z",
            timeZone: .gmt, links: links.isEmpty ? nil : links
        )
        try Event.insert { event }.execute(db)
    }
}

func fetchContactInfoEvent(
    _ eventID: Event.ID,
    from database: any DatabaseWriter
) async throws -> Event {
    try await database.read { db in
        try #require(
            try Event.where { $0.id.eq(eventID) }.fetchOne(db)
        )
    }
}
