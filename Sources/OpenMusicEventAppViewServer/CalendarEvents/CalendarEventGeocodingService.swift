import ATProto
import Dependencies
import Foundation
import GRDB
import OpenMusicEventLexicon
import ServiceLifecycle
import SQLiteData

@Table("calendarGeocodes")
struct CalendarGeocode: Codable, Equatable, Sendable {
    enum Cached: Equatable, Sendable {
        case coordinates(latitude: Double, longitude: Double)
        case noResult
    }

    @Column(primaryKey: true) var normalizedAddress: String
    var address: String
    var latitude: Double?
    var longitude: Double?
    var status: String
    var updatedAt: Date

    static func registerMigration(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("Create durable calendar geocode cache") { database in
            try #sql(
                """
                CREATE TABLE \(quote: Self.tableName) (
                  "normalizedAddress" TEXT PRIMARY KEY NOT NULL,
                  "address" TEXT NOT NULL,
                  "latitude" REAL,
                  "longitude" REAL,
                  "status" TEXT NOT NULL,
                  "updatedAt" TEXT NOT NULL
                ) STRICT
                """
            )
            .execute(database)
            try #sql(
                """
                CREATE TABLE \(quote: CalendarGeocodeJob.tableName) (
                  "normalizedAddress" TEXT PRIMARY KEY NOT NULL,
                  "address" TEXT NOT NULL,
                  "attempts" INTEGER NOT NULL,
                  "nextAttemptAt" TEXT NOT NULL
                ) STRICT
                """
            )
            .execute(database)
        }
    }

    static func cached(address: String, in database: Database) throws -> Cached? {
        guard let row = try find(normalize(address)).fetchOne(database) else { return nil }
        if row.status == "noResult" { return .noResult }
        guard let latitude = row.latitude, let longitude = row.longitude else { return nil }
        return .coordinates(latitude: latitude, longitude: longitude)
    }

    static func enqueue(address: String, in database: Database) throws {
        let normalizedAddress = normalize(address)
        guard try find(normalizedAddress).fetchOne(database) == nil,
              try CalendarGeocodeJob.find(normalizedAddress).fetchOne(database) == nil
        else { return }
        try CalendarGeocodeJob.insert {
            CalendarGeocodeJob(
                normalizedAddress: normalizedAddress,
                address: address,
                attempts: 0,
                nextAttemptAt: .distantPast
            )
        }
        .execute(database)
    }

    static func normalize(_ address: String) -> String {
        address
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .init(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

@Table("calendarGeocodeJobs")
struct CalendarGeocodeJob: Codable, Equatable, Sendable {
    @Column(primaryKey: true) var normalizedAddress: String
    var address: String
    var attempts: Int
    var nextAttemptAt: Date
}

public struct CalendarEventGeocodingService: Service {
    public init(
        store: OpenMusicEventAppViewStore,
        client: CalendarEventGeocodingClient
    ) {
        self.store = store
        self.client = client
    }

    public var store: OpenMusicEventAppViewStore
    public var client: CalendarEventGeocodingClient

    public func run() async throws {
        @Dependency(\.continuousClock) var clock
        @Dependency(\.date.now) var now
        while !Task.isCancelled {
            guard let job = try store.nextGeocodeJob(now: now) else {
                try await clock.sleep(for: .seconds(1))
                continue
            }
            do {
                switch try await client.coordinatesForAddress(job.address) {
                case let .coordinates(latitude, longitude):
                    try store.completeGeocode(
                        job: job,
                        latitude: latitude,
                        longitude: longitude,
                        now: now
                    )
                case .noResult:
                    try store.completeGeocode(job: job, now: now)
                case .unavailable:
                    try await clock.sleep(for: .seconds(30))
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try store.retryGeocode(job: job, now: now)
            }
        }
    }
}

extension OpenMusicEventAppViewStore {
    func cacheGeocodingOverrides(
        _ overrides: [String: CalendarEventGeocodingClient.Coordinates],
        now: Date = .now
    ) throws -> Bool {
        guard !overrides.isEmpty else { return false }
        return try database.write { database in
            var changed = false
            for (address, coordinates) in overrides {
                let normalizedAddress = CalendarGeocode.normalize(address)
                let existing = try CalendarGeocode.find(normalizedAddress)
                    .fetchOne(database)
                if existing?.address != address
                    || existing?.latitude != coordinates.latitude
                    || existing?.longitude != coordinates.longitude
                    || existing?.status != "resolved"
                {
                    changed = true
                    try CalendarGeocode.upsert {
                        CalendarGeocode(
                            normalizedAddress: normalizedAddress,
                            address: address,
                            latitude: coordinates.latitude,
                            longitude: coordinates.longitude,
                            status: "resolved",
                            updatedAt: now
                        )
                    }
                    .execute(database)
                }
                try CalendarGeocodeJob.find(normalizedAddress).delete().execute(database)
            }
            return changed
        }
    }

    func nextGeocodeJob(now: Date) throws -> CalendarGeocodeJob? {
        try database.read { database in
            try CalendarGeocodeJob
                .where { $0.nextAttemptAt.lte(now) }
                .order { $0.nextAttemptAt }
                .fetchOne(database)
        }
    }

    func completeGeocode(
        job: CalendarGeocodeJob,
        latitude: Double? = nil,
        longitude: Double? = nil,
        now: Date
    ) throws {
        try database.write { database in
            try CalendarGeocode.upsert {
                CalendarGeocode(
                    normalizedAddress: job.normalizedAddress,
                    address: job.address,
                    latitude: latitude,
                    longitude: longitude,
                    status: latitude == nil ? "noResult" : "resolved",
                    updatedAt: now
                )
            }
            .execute(database)
            try CalendarGeocodeJob.find(job.normalizedAddress).delete().execute(database)
            for row in try CalendarEventBrowseProjection.all.fetchAll(database) {
                var event = try JSONDecoder().decode(OME.CalendarEvent.self, from: row.event)
                guard let locationIndex = event.locations.firstIndex(where: {
                    $0.geocodingAddress.map(CalendarGeocode.normalize) == job.normalizedAddress
                }) else { continue }
                if let latitude, let longitude {
                    event.locations[locationIndex].latitude = String(latitude)
                    event.locations[locationIndex].longitude = String(longitude)
                }
                let existingSearchText = try CalendarEventBrowseSearch
                    .where { $0.uri.eq(row.uri) }
                    .select(\.searchText)
                    .fetchOne(database) ?? ""
                try CalendarEventBrowseProjection.upsert(
                    event,
                    searchText: existingSearchText,
                    sourceID: row.sourceID,
                    in: database
                )
            }
        }
    }

    func retryGeocode(job: CalendarGeocodeJob, now: Date) throws {
        var job = job
        job.attempts += 1
        let delay = min(3_600, 1 << min(job.attempts, 11))
        job.nextAttemptAt = now.addingTimeInterval(TimeInterval(delay))
        try database.write { database in
            try CalendarGeocodeJob.upsert { job }.execute(database)
        }
    }
}
