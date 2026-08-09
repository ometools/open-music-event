import Clocks
import ComposableArchitecture2
import CustomDump
import Dependencies
import Foundation
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
        let eventID = contactInfoEventID()
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
            reportingLinks: reportingLinks,
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
            Store(initialState: CommunicationsViewer.State(eventID: eventID)) {
                CommunicationsViewer()
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
        await TestExhaustivity.$current.withValue(.off) {
            let eventID = contactInfoEventID()
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
    func contactEditorLoadsEditsAndSavesReportingLinksInOrderWithContactNumbers() async throws {
        let database = try makeContactInfoDatabase()
        let eventID = contactInfoEventID()
        let originalContactNumbers = [
            OMERecord.Event.ContactNumber(
                phoneNumber: "+1 555 0100",
                title: "Event Support",
                description: "Call during event hours."
            )
        ]
        let originalReportingLinks = [
            reportingLink(name: "Safety Concern", url: "https://example.org/safety"),
            reportingLink(name: "Accessibility Help", url: "https://example.org/accessibility"),
        ]
        try await insertContactInfoEvent(
            eventID,
            contactNumbers: originalContactNumbers,
            reportingLinks: originalReportingLinks,
            into: database
        )

        @Bindable var store = makeContactInfoEditorStore(database: database, eventID: eventID)

        #expect(store.hasLoadedDraft)
        expectNoDifference(store.reportingLinks.map(\.name), ["Safety Concern", "Accessibility Help"])
        let removedLinkID = store.reportingLinks[1].id
        await store.send(.removeReportingLinkButtonTapped(removedLinkID))?.value
        await store.send(.addReportingLinkButtonTapped)?.value
        $store.reportingLinks[0].name.wrappedValue = "  Event Safety  "
        $store.reportingLinks[0].description.wrappedValue = "  Help from the safety team.  "
        $store.reportingLinks[1].name.wrappedValue = "  Lost and Found  "
        $store.reportingLinks[1].urlString.wrappedValue = "  https://example.org/lost  "

        await store.send(.saveButtonTapped)?.value

        let savedEvent = try await fetchContactInfoEvent(eventID, from: database)
        expectNoDifference(savedEvent.contactNumbers, originalContactNumbers)
        expectNoDifference(
            savedEvent.reportingLinks,
            [
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
        let eventID = contactInfoEventID()
        try await insertContactInfoEvent(eventID, into: database)

        @Bindable var store = makeContactInfoEditorStore(database: database, eventID: eventID)
        await store.send(.addReportingLinkButtonTapped)?.value
        $store.reportingLinks[0].urlString.wrappedValue = "https://example.org/report"

        await store.send(.saveButtonTapped)?.value

        #expect(store.errorMessage == "Enter a reporting link name.")
        #expect(try await fetchContactInfoEvent(eventID, from: database).reportingLinks == nil)

        $store.reportingLinks[0].name.wrappedValue = "Report an Incident"
        $store.reportingLinks[0].urlString.wrappedValue = "ftp://example.org/report"

        await store.send(.saveButtonTapped)?.value

        #expect(store.errorMessage == "Enter a valid http or https URL.")
        #expect(try await fetchContactInfoEvent(eventID, from: database).reportingLinks == nil)
    }
}

func contactInfoEventID() -> OMERecord.Event.ID {
    OMERecord.Event.ID(
        organizerID: OMERecord.Organizer.ID("did:web:contact.example")!,
        eventID: .init("event-1")
    )
}

func reportingLink(
    name: String,
    url: String,
    description: String? = nil
) -> OMERecord.Event.ReportingLink {
    OMERecord.Event.ReportingLink(
        name: name,
        url: URL(string: url)!,
        description: description
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
    eventID: OMERecord.Event.ID
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
    _ eventID: OMERecord.Event.ID,
    contactNumbers: [OMERecord.Event.ContactNumber]? = nil,
    reportingLinks: [OMERecord.Event.ReportingLink]? = nil,
    into database: any DatabaseWriter
) async throws {
    try await database.write { db in
        try OMERecord.Organizer.insert {
            OMERecord.Organizer.Draft(id: eventID.organizerID)
        }
        .execute(db)
        try OMERecord.Event.insert {
            OMERecord.Event.Draft(
                id: eventID,
                name: "Contact Event",
                description: nil,
                startDate: nil,
                endDate: nil,
                status: nil,
                mode: nil,
                locations: nil,
                uris: nil,
                timeZone: TimeZone(identifier: "UTC")!,
                images: nil,
                contactNumbers: contactNumbers,
                categoryConfigs: nil,
                reportingLinks: reportingLinks
            )
        }
        .execute(db)
    }
}

func fetchContactInfoEvent(
    _ eventID: OMERecord.Event.ID,
    from database: any DatabaseWriter
) async throws -> OMERecord.Event {
    try await database.read { db in
        try #require(
            try OMERecord.Event.where { $0.id.eq(eventID) }.fetchOne(db)
        )
    }
}
