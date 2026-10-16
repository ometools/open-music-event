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
        let eventID = Event.ID(
            "at://did:plc:contactfixture/events.openmusic.event/3mrdbziccpcah"
        )!
        let event = try! Event(
            id: eventID,
            name: "Contact Fixture",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: TimeZone(identifier: "UTC")!,
            links: [
                OME.Link(
                    url: URL(string: "tel:+15550100")!,
                    title: "On Site Emergency Services",
                    role: .known(.contact(.init(use: .known(.emergency))))
                ),
                OME.Link(
                    url: URL(string: "https://example.org/report")!,
                    title: "Report Incident",
                    role: .known(.reporting(.init()))
                )
            ]
        )
        try! database.write { db in
            try Event.insert { event }.execute(db)
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
