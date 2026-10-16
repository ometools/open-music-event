import Foundation
import GRDB
import OpenMusicEventLexicon
import SQLiteData
import SwiftTimeZoneLookup
import Synchronization

@Table("calendarLocationContexts")
struct CalendarLocationContext: Codable, Sendable {
    @Column(primaryKey: true) var id: String
    var latitude: Double
    var longitude: Double
    var timeZoneIdentifier: String?
    var country: String?

    static let lookup = Mutex(Result { try SwiftTimeZoneLookup() })

    static func key(latitude: Double, longitude: Double) -> String {
        "\(latitude == 0 ? 0 : latitude),\(longitude == 0 ? 0 : longitude)"
    }

    static func ensure(latitude: Double, longitude: Double, in db: Database) throws {
        let id = key(latitude: latitude, longitude: longitude)
        guard try find(id).fetchOne(db) == nil else { return }
        let context = try lookup.withLock { result in
            let value = try result.get().lookup(latitude: Float(latitude), longitude: Float(longitude))
            return Self(id: id, latitude: latitude, longitude: longitude,
                        timeZoneIdentifier: value?.timezone, country: value?.countryName)
        }
        try Self.insert { context }.execute(db)
    }

    static func registerMigration(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("Cache coordinate time zones and countries") { db in
            try #sql("""
                CREATE TABLE \(quote: Self.tableName) (
                  id TEXT PRIMARY KEY NOT NULL, latitude REAL NOT NULL, longitude REAL NOT NULL,
                  timeZoneIdentifier TEXT, country TEXT,
                  UNIQUE(latitude, longitude)
                ) STRICT
                """).execute(db)
            let points = try CalendarEventBrowseProjection
                .where { $0.latitude.isNot(nil) && $0.longitude.isNot(nil) }
                .select { ($0.latitude, $0.longitude) }.distinct().fetchAll(db)
            for (latitude, longitude) in points {
                if let latitude, let longitude {
                    try ensure(latitude: latitude, longitude: longitude, in: db)
                }
            }
        }
    }

    static func enrich(_ event: inout OME.CalendarEvent, in db: Database) throws {
        for index in event.locations.indices {
            guard let latitude = event.locations[index].latitude.flatMap(Double.init),
                  let longitude = event.locations[index].longitude.flatMap(Double.init),
                  let context = try find(key(latitude: latitude, longitude: longitude)).fetchOne(db)
            else { continue }
            if event.timeZoneIdentifier?.isEmpty != false { event.timeZoneIdentifier = context.timeZoneIdentifier }
            if event.locations[index].country?.isEmpty != false { event.locations[index].country = context.country }
            return
        }
    }
}
