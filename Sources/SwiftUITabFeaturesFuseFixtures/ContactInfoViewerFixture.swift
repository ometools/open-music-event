import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventApp
import OpenMusicEventAppEventViewer
import OpenMusicEventLexicon
import SQLiteData

#if os(Android) || ROBOLECTRIC
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

/// Mounts Contact with rows in both sections so Compose validates their shared list identities.
public struct ContactInfoViewerFixture: View {
    let store: StoreOf<ContactInfoViewer>

    public init() {
        let database = try! withDependencies {
            $0.context = .test
            try OME.prepareDependencies(&$0)
        } operation: {
            @Dependency(\.defaultDatabase) var database
            return database
        }
        let eventID = OMERecord.Event.ID(
            organizerID: OMERecord.Organizer.ID("did:web:contact-fixture.example")!,
            eventID: .init("contact-fixture")
        )
        try! database.write { db in
            try OMERecord.Organizer.insert {
                OMERecord.Organizer.Draft(id: eventID.organizerID)
            }
            .execute(db)
            try OMERecord.Event.insert {
                OMERecord.Event.Draft(
                    id: eventID,
                    name: "Contact Fixture",
                    description: nil,
                    startDate: nil,
                    endDate: nil,
                    status: nil,
                    mode: nil,
                    locations: nil,
                    uris: nil,
                    timeZone: TimeZone(identifier: "UTC")!,
                    images: nil,
                    contactNumbers: [
                        OMERecord.Event.ContactNumber(
                            phoneNumber: "+1 555 0100",
                            title: "On Site Emergency Services",
                            description: nil
                        )
                    ],
                    categoryConfigs: nil,
                    reportingLinks: [
                        OMERecord.Event.ReportingLink(
                            name: "Report Incident",
                            url: URL(string: "https://example.org/report")!,
                            description: nil
                        )
                    ]
                )
            }
            .execute(db)
        }
        self.store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: ContactInfoViewer.State(eventID: eventID)) {
                ContactInfoViewer()
            }
        }
    }

    public var body: some View {
        NavigationStack {
            ContactInfoViewerView(
                store: store,
                showsAuthoringControls: false
            )
        }
    }
}
