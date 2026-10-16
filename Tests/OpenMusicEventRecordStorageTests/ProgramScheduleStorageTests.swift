import OpenMusicEventDatabase
import CustomDump
import Foundation
import ATProtoTypes
import ATProtoSQLite
import SQLiteData
@testable import OpenMusicEventLexicon
import Testing

@Suite
struct ProgramScheduleStorageTests {
    typealias PublicSchedule = OpenMusicEventLexicon.Schedule

    let eventURI = ATProto.URI("at://did:plc:wickedwoods/events.openmusic.event/3mrdbziccpcah")!
    let programURI = ATProto.URI("at://did:plc:wickedwoods/events.openmusic.program/3mrdbziccpcal")!
    let scheduleURI = ATProto.URI("at://did:plc:wickedwoods/events.openmusic.schedule/3mrdbziccpcam")!
    let placeURI = ATProto.URI("at://did:plc:wickedwoods/events.openmusic.eventPlace/3mrdbziccpcaj")!
    let itemURI = ATProto.URI("at://did:plc:wickedwoods/events.openmusic.programItem/3mrdbziccpcai")!
    let createdAt: ATProto.DateTime = "2026-09-22T12:00:00Z"

    @Test
    func `programs and schedules round trip through independent tables`() throws {
        let program = try Program(
            id: programURI,
            event: eventURI,
            title: "Schedule",
            createdAt: createdAt,
            eventPlaces: [placeURI]
        )
        let schedule = try PublicSchedule(
            id: scheduleURI,
            event: eventURI,
            date: #require(LocalDate("2026-09-05")),
            createdAt: createdAt
        )
        let database = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        try database.write { db in
            try Program.insert { program }.execute(db)
            try PublicSchedule.insert { schedule }.execute(db)
        }
        expectNoDifference(
            try database.read { db in try Program.find(programURI).fetchOne(db) },
            program
        )
        expectNoDifference(
            try database.read { db in try PublicSchedule.find(scheduleURI).fetchOne(db) },
            schedule
        )
    }
}
