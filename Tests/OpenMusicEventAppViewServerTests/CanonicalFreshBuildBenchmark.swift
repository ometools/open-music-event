import GRDB
import Foundation
@testable import OpenMusicEventAppViewServer

extension CommunityCalendarDomainPersistenceTests {
    func freshBuild(records: [Row], database: DatabaseQueue) throws {
        try database.write { db in
            for record in records {
                try db.execute(sql: """
                    INSERT INTO appViewIndexedRecords (uri, collection, cid, value, sequence, isDeleted)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """, arguments: StatementArguments(record.databaseValues))
            }
        }
        let store = try OpenMusicEventAppViewStore(rebuilding: database)
        _ = try store.rebuildCanonicalCalendar(now: .now) { print($0) }
    }
}
