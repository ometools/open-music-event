import ATProto
import CustomDump
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData
import Testing

struct EventRSVPTests {
    @Test
    func `an RSVP is stored for the event URI and the attendee using the app`() async throws {
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)

        let eventURI = try #require(
            ATProto.URI("at://did:plc:festival/app.openmusicevent.event/summer-2026")
        )
        let accountDID = try #require(DID("did:plc:attendee"))
        let account = EventRSVP.Consumer(accountDID: accountDID)
        let loggedOut = EventRSVP.Consumer.loggedOut

        try await database.write { db in
            // A logged-out attendee can make a local choice without creating an account.
            try EventRSVP.save(
                eventURI: eventURI,
                eventCID: "bafyreievent-v1",
                consumer: loggedOut,
                status: .interested,
                createdAt: Date(timeIntervalSince1970: 10),
                in: db
            )

            // A signed-in attendee on the same device has an independent choice.
            try EventRSVP.save(
                eventURI: eventURI,
                eventCID: "bafyreievent-v1",
                consumer: account,
                status: .going,
                createdAt: Date(timeIntervalSince1970: 20),
                in: db
            )

            // Rehydrating the same URI with a new CID updates only that attendee's record.
            try EventRSVP.save(
                eventURI: eventURI,
                eventCID: "bafyreievent-v2",
                consumer: account,
                status: .notGoing,
                createdAt: Date(timeIntervalSince1970: 30),
                in: db
            )
        }

        let records = try await database.read { db in
            try EventRSVP.order { $0.createdAt }.fetchAll(db)
        }

        expectNoDifference(
            records,
            [
                EventRSVP(
                    eventURI: eventURI,
                    eventCID: "bafyreievent-v1",
                    consumer: loggedOut,
                    status: .interested,
                    createdAt: Date(timeIntervalSince1970: 10)
                ),
                EventRSVP(
                    eventURI: eventURI,
                    eventCID: "bafyreievent-v2",
                    consumer: account,
                    status: .notGoing,
                    createdAt: Date(timeIntervalSince1970: 30)
                ),
            ]
        )
    }
}
