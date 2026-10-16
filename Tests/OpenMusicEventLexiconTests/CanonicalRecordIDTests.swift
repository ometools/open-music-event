import ATProtoTypes
import Foundation
import OpenMusicEventLexicon
import Testing

@Suite
struct CanonicalRecordIDTests {
    let eventID = ATProto.URI("at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah")!

    @Test
    func generatedScheduleIDHasTheEventRepositoryAndValidTID() throws {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let id = try CanonicalRecordID.next(
            collection: Schedule.lexiconID,
            in: eventID.authority,
            at: date,
            clockID: 17
        )
        #expect(id.authority == eventID.authority)
        #expect(id.collection?.rawValue == Schedule.lexiconID.rawValue)
        #expect(id.rkey?.rawValue.count == 13)
        try LexiconCoding.validateRecordURI(id, type: Schedule.self)
    }

    @Test
    func nextIDAdvancesPastClockSmearAndRepeatedMicroseconds() throws {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let first = try CanonicalRecordID.next(
            collection: Schedule.lexiconID, in: eventID.authority, at: date, clockID: 17
        )
        let second = try CanonicalRecordID.next(
            collection: Schedule.lexiconID, in: eventID.authority, at: date, after: first.rkey, clockID: 17
        )
        let third = try CanonicalRecordID.next(
            collection: Schedule.lexiconID, in: eventID.authority,
            at: date.addingTimeInterval(-10), after: second.rkey, clockID: 0
        )
        #expect(first.description < second.description)
        #expect(second.description < third.description)
        try LexiconCoding.validateRecordURI(third, type: Schedule.self)
    }
}
