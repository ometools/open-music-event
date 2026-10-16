import Foundation
import OpenMusicEventTimeZones
import SQLiteData
import Testing

@Table("timeZoneRecords")
private struct TimeZoneRecord: Equatable, Sendable, Identifiable {
    @Column(primaryKey: true) var id: Int
    var timeZone: TimeZone
}

@Suite
struct OpenMusicEventTimeZonesTests {
    @Test
    func queryBindingUsesIdentifier() throws {
        let timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))

        #expect(timeZone.queryBinding == "America/Los_Angeles".queryBinding)
    }

    @Test
    func typeAffinityIsText() {
        #expect(TimeZone.typeAffinity == .text)
    }

    @Test
    func decodeRoundTripsFromDatabase() throws {
        let denver = try #require(TimeZone(identifier: "America/Denver"))
        let database = try SQLiteData.defaultDatabase()
        try database.write { db in
            try #sql("""
                CREATE TABLE "timeZoneRecords" (
                  "id" INTEGER PRIMARY KEY NOT NULL,
                  "timeZone" TEXT NOT NULL
                ) STRICT
                """)
                .execute(db)

            try TimeZoneRecord.insert {
                TimeZoneRecord(id: 1, timeZone: denver)
            }
            .execute(db)
        }

        let record = try database.read { db in
            try TimeZoneRecord.where { $0.id.eq(1) }.fetchOne(db)
        }

        #expect(record?.timeZone.identifier == "America/Denver")
    }
}
