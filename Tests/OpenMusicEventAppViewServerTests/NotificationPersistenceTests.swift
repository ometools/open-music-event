import ComposableNotifications
import ComposableNotificationsServer
import CustomDump
import Dependencies
import Foundation
import GRDB
import Hummingbird
import HummingbirdTesting
import HTTPTypes
@testable import OpenMusicEventAppViewServer
import SQLiteData
import Testing

private func notificationDatabase(
    store: OpenMusicEventAppViewStore,
    protection: NotificationDestinationProtection,
    legacyAPNSEnvironments: [Push.ApplicationID: Push.APNS.Environment] = [:]
) -> NotificationDatabase {
    withDependencies {
        $0.defaultDatabase = store.database
        $0.notificationDestinationProtectionClient = protection.client(
            legacyAPNSEnvironments: legacyAPNSEnvironments
        )
    } operation: {
        NotificationDatabase()
    }
}

private actor NotificationProviderStartProbe {
    private var didStart = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func start() {
        didStart = true
        let waiters = waiters
        self.waiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

@Suite(.serialized)
struct NotificationPersistenceTests {
    @Test
    func `legacy APNS ciphertext opens with the configured development fallback`() async throws {
        let applicationID = Push.ApplicationID(rawValue: "com.Festivl.WickedWoods")
        let installationID = NotificationInstallation.ID(rawValue: "legacy-installation")
        let protection = try NotificationDestinationProtection(
            keyData: Data(repeating: 0x2A, count: 32)
        )
        let legacy = PersistedNotificationDestination(
            applicationID: applicationID,
            provider: .apns,
            apnsEnvironment: nil,
            value: "legacy-device-token"
        )
        let protected = ProtectedNotificationDestination(
            applicationID: applicationID,
            apnsEnvironment: nil,
            provider: .apns,
            ciphertext: try protection.seal(legacy, for: installationID),
            fingerprint: "legacy-fingerprint",
            keyVersion: protection.keyVersion
        )

        let destination: Push.Destination = try protection.client(
            legacyAPNSEnvironments: [applicationID: .development]
        ).reveal(protected, installationID)

        expectNoDifference(
            destination,
            .apns(
                Push.APNS(
                    applicationID: applicationID,
                    environment: .development,
                    deviceToken: .init(rawValue: "legacy-device-token")
                )
            )
        )
    }

    @Test
    func `destination encryption key does not implicitly expose registration`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let app = try OpenMusicEventAppViewServer.application(
            configuration: AppViewConfiguration(
                port: 0,
                databaseURL: directory.appending(path: "appview.sqlite"),
                notificationDestinationProtection: try NotificationDestinationProtection(
                    keyData: Data(repeating: 0x2A, count: 32)
                )
            )
        )

        try await app.test(.router) { client in
            try await client.execute(
                uri: NotificationRegistrationEndpoint.installationsPath,
                method: .post
            ) { response in
                #expect(response.status == .serviceUnavailable)
            }
        }
    }

    @Test
    func `configured AppView installs persistent registration routes`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databaseURL = directory.appending(path: "appview.sqlite")
        let protection = try NotificationDestinationProtection(
            keyData: Data(repeating: 0x2A, count: 32)
        )
        let app = try OpenMusicEventAppViewServer.application(
            configuration: AppViewConfiguration(
                port: 0,
                databaseURL: databaseURL,
                notificationDestinationProtection: protection,
                notificationRegistration: AppViewNotificationRegistrationConfiguration(
                    authorization: .anonymous,
                    allowedApplicationIDs: [.init(rawValue: "app.openmusicevent")]
                )
            )
        )
        let destination = "provider-issued-device-token"
        let pushDestination = Push.Destination.apns(
            Push.APNS(
                applicationID: .init(rawValue: "app.openmusicevent"),
                environment: .development,
                deviceToken: .init(rawValue: destination)
            ),
        )

        try await app.test(.router) { client in
            let credential = try await client.execute(
                uri: NotificationRegistrationEndpoint.installationsPath,
                method: .post
            ) { response in
                #expect(response.status == .created)
                #expect(response.headers[.cacheControl] == "no-store")
                return try JSONDecoder().decode(
                    NotificationInstallationCredentialPayload.self,
                    from: Data(response.body.readableBytesView)
                ).credential
            }
            try await client.execute(
                uri: NotificationRegistrationEndpoint.destinationPath,
                method: .put,
                headers: [
                    .authorization: "Notification \(credential.rawValue)",
                    .contentType: "application/json",
                ],
                body: ByteBuffer(
                    data: try JSONEncoder().encode(
                        NotificationDestinationPayload(pushDestination)
                    )
                )
            ) { response in
                #expect(response.status == .noContent)
            }
        }

        let rawDatabase = try DatabasePool(path: databaseURL.path(percentEncoded: false))
        let persisted = try await rawDatabase.read { database in
            let installationCount = try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM pushInstallations"
            )
            let registrationCount = try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM pushRegistrations"
            )
            let registration = try Row.fetchOne(
                database,
                sql: "SELECT applicationID, destination FROM pushRegistrations"
            )
            let applicationID: String? = registration?["applicationID"]
            let ciphertext: Data? = registration?["destination"]
            return (
                installationCount,
                registrationCount,
                applicationID,
                ciphertext
            )
        }
        expectNoDifference(persisted.0, 1)
        expectNoDifference(persisted.1, 1)
        expectNoDifference(persisted.2, "app.openmusicevent")
        let ciphertext = try #require(persisted.3)
        #expect(ciphertext.range(of: Data(destination.utf8)) == nil)
    }

    @Test
    func `notification persistence coexists with projections across an AppView restart`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databaseURL = directory.appending(path: "appview.sqlite")
        let protection = try NotificationDestinationProtection(
            keyData: Data(repeating: 0x2A, count: 32),
            keyVersion: 7
        )
        let installation = NotificationInstallation(
            id: .init(rawValue: "installation-1")
        )
        let credentialFingerprint = NotificationInstallation.CredentialFingerprint(
            rawValue: "credential-fingerprint"
        )
        let originalDestination = Push.Destination.apns(
            Push.APNS(
                applicationID: .init(rawValue: "app.openmusicevent"),
                environment: .development,
                deviceToken: .init(rawValue: "old-device-token")
            )
        )
        let destination = "replacement-token-that-must-not-be-stored-in-plaintext"
        let replacementDestination = Push.Destination.fcm(
            Push.FCM(
                applicationID: .init(rawValue: "fm.woody.wickedwoods"),
                registrationToken: .init(rawValue: destination)
            )
        )
        let subscriptions: Set<NotificationSubscription> = [
            NotificationSubscription(sourceID: .init(rawValue: "source-b")),
            NotificationSubscription(sourceID: .init(rawValue: "source-c")),
        ]
        let projectionEvent = Data(#"{"name":"Projection sentinel"}"#.utf8)

        do {
            let store = try OpenMusicEventAppViewStore(
                databaseURL: databaseURL
            )
            let notifications = notificationDatabase(store: store, protection: protection)
            let rawDatabase = try DatabasePool(path: databaseURL.path(percentEncoded: false))
            try await rawDatabase.write { database in
                try database.execute(
                    sql: """
                        INSERT INTO communityCalendarEventProjections (
                          uri, cid, startsAt, createdAt, sequence, event
                        ) VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        "at://did:plc:test/community.lexicon.calendar.event/sentinel",
                        "bafy-sentinel",
                        "2026-08-08T18:00:00Z",
                        "2026-08-08T17:00:00Z",
                        1,
                        projectionEvent,
                    ]
                )
            }
            try await notifications.insertInstallation(
                installation,
                credentialFingerprint: credentialFingerprint
            )
            try await notifications.replaceDestination(originalDestination, for: installation.id)
            try await notifications.replaceSubscriptions(
                [NotificationSubscription(sourceID: .init(rawValue: "source-a"))],
                for: installation.id
            )
            try await notifications.replaceDestination(replacementDestination, for: installation.id)
            try await notifications.replaceSubscriptions(subscriptions, for: installation.id)
        }

        let rawDatabase = try DatabasePool(path: databaseURL.path(percentEncoded: false))
        let persisted = try await rawDatabase.read { database in
            let ciphertext = try Data.fetchOne(
                database,
                sql: "SELECT destination FROM pushRegistrations WHERE installationID = ?",
                arguments: [installation.id.rawValue]
            )
            let projection = try Data.fetchOne(
                database,
                sql: """
                    SELECT event FROM communityCalendarEventProjections
                    WHERE uri = ?
                    """,
                arguments: [
                    "at://did:plc:test/community.lexicon.calendar.event/sentinel"
                ]
            )
            return (ciphertext, projection)
        }
        let ciphertext = try #require(persisted.0)
        #expect(ciphertext.range(of: Data(destination.utf8)) == nil)
        expectNoDifference(persisted.1, projectionEvent)

        let reopenedStore = try OpenMusicEventAppViewStore(
            databaseURL: databaseURL
        )
        let reopenedNotifications = notificationDatabase(
            store: reopenedStore,
            protection: protection
        )
        let reopenedInstallationID = try await reopenedNotifications.installationID(
            for: credentialFingerprint
        )
        let reopenedDestination = try await reopenedNotifications.destination(
            for: installation.id
        )
        let reopenedSubscriptions = try await reopenedNotifications.subscriptions(
            for: installation.id
        )
        expectNoDifference(reopenedInstallationID, installation.id)
        expectNoDifference(reopenedDestination, replacementDestination)
        expectNoDifference(reopenedSubscriptions, subscriptions)

        let projectionAfterRestart = try await rawDatabase.read { database in
            try Data.fetchOne(
                database,
                sql: """
                    SELECT event FROM communityCalendarEventProjections
                    WHERE uri = ?
                    """,
                arguments: [
                    "at://did:plc:test/community.lexicon.calendar.event/sentinel"
                ]
            )
        }
        expectNoDifference(projectionAfterRestart, projectionEvent)
    }

    @Test
    func `source delivery remains queued across restart until the provider accepts it`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databaseURL = directory.appending(path: "appview.sqlite")
        let protection = try NotificationDestinationProtection(
            keyData: Data(repeating: 0x2A, count: 32)
        )
        let installation = NotificationInstallation(
            id: .init(rawValue: "installation-1")
        )
        let destination = Push.Destination.apns(
            Push.APNS(
                applicationID: .init(rawValue: "app.openmusicevent"),
                environment: .development,
                deviceToken: .init(rawValue: "provider-issued-device-token")
            )
        )
        let source = NotificationSource(
            id: .init(
                rawValue: "at://did:plc:wickedwoods/app.openmusicevent.event/2026"
            ),
            version: .init(rawValue: "bafy-source-version")
        )
        let receivedAt = Date(timeIntervalSince1970: 1_786_291_200)
        let retryAt = receivedAt.addingTimeInterval(1)

        do {
            let store = try OpenMusicEventAppViewStore(
                databaseURL: databaseURL
            )
            let notifications = notificationDatabase(store: store, protection: protection)
            try await notifications.insertInstallation(
                installation,
                credentialFingerprint: .init(rawValue: "credential-fingerprint")
            )
            try await notifications.replaceDestination(destination, for: installation.id)
            try await notifications.replaceSubscriptions(
                [NotificationSubscription(sourceID: source.id)],
                for: installation.id
            )

            let insertedCount = try await notifications.enqueue(
                source: source,
                at: receivedAt
            )
            let duplicateCount = try await notifications.enqueue(
                source: source,
                at: receivedAt
            )
            expectNoDifference(insertedCount, 1)
            expectNoDifference(duplicateCount, 0)
            let delivery = try #require(
                try await notifications.nextDelivery(at: receivedAt)
            )
            let signal = try delivery.message.signal()
            expectNoDifference(signal, .sourceAvailable(source))
            expectNoDifference(delivery.destination, destination)
            expectNoDifference(delivery.failedAttempts, 0)
            let shouldRetry = try await notifications.recordProviderResult(
                .retryableFailure(
                    NotificationProviderResponse(status: 503, code: "UNAVAILABLE"),
                    retryAfter: 1
                ),
                for: delivery,
                attemptedAt: receivedAt,
                retryPolicy: .exponential
            )
            #expect(shouldRetry)
            let deliveryBeforeRetry = try await notifications.nextDelivery(at: receivedAt)
            #expect(deliveryBeforeRetry == nil)
        }

        let reopenedStore = try OpenMusicEventAppViewStore(
            databaseURL: databaseURL
        )
        let reopenedNotifications = notificationDatabase(
            store: reopenedStore,
            protection: protection
        )
        let retriedDelivery = try #require(
            try await reopenedNotifications.nextDelivery(at: retryAt)
        )
        let retriedSignal = try retriedDelivery.message.signal()
        expectNoDifference(retriedSignal, .sourceAvailable(source))
        expectNoDifference(retriedDelivery.destination, destination)
        expectNoDifference(retriedDelivery.failedAttempts, 1)
        let shouldRetry = try await reopenedNotifications.recordProviderResult(
            .accepted(NotificationProviderResponse(status: 200)),
            for: retriedDelivery,
            attemptedAt: retryAt,
            retryPolicy: .exponential
        )
        #expect(!shouldRetry)
        let deliveryAfterSuccess = try await reopenedNotifications.nextDelivery(at: retryAt)
        #expect(deliveryAfterSuccess == nil)

        let rawDatabase = try DatabasePool(path: databaseURL.path(percentEncoded: false))
        let ledger = try rawDatabase.read { database in
            try Row.fetchOne(
                database,
                sql: """
                    SELECT failedAttempts, lastAttemptAt, deliveredAt
                    FROM pushOutbox
                    """
            )
        }
        let ledgerRow = try #require(ledger)
        let failedAttempts: Int = ledgerRow["failedAttempts"]
        let lastAttemptAt: Date = ledgerRow["lastAttemptAt"]
        let deliveredAt: Date = ledgerRow["deliveredAt"]
        expectNoDifference(failedAttempts, 1)
        expectNoDifference(lastAttemptAt, retryAt)
        expectNoDifference(deliveredAt, retryAt)
    }

    @Test
    func `terminal delivery migration removes ambiguous APNS registration without losing installation or subscriptions`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databaseURL = directory.appending(path: "appview.sqlite")
        let rawDatabase = try DatabasePool(path: databaseURL.path(percentEncoded: false))
        var legacyMigrator = DatabaseMigrator()
        NotificationDatabase.registerMigrations(into: &legacyMigrator)
        try legacyMigrator.migrate(
            rawDatabase,
            upTo: "Create push notification outbox"
        )

        // A shipped AppView database has an installation and subscription, but its legacy APNs
        // registration predates the required environment column.
        try await rawDatabase.write { database in
            try database.execute(
                sql: "INSERT INTO pushInstallations (id, credentialFingerprint) VALUES (?, ?)",
                arguments: ["installation-1", "credential-fingerprint"]
            )
            try database.execute(
                sql: """
                    INSERT INTO pushRegistrations (
                      installationID,
                      applicationID,
                      provider,
                      destination,
                      destinationFingerprint,
                      destinationKeyVersion
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    "installation-1",
                    "com.Festivl.WickedWoods",
                    "apns",
                    Data("legacy-token-ciphertext".utf8),
                    "legacy-fingerprint",
                    1,
                ]
            )
            try database.execute(
                sql: "INSERT INTO pushSubscriptions (installationID, sourceID) VALUES (?, ?)",
                arguments: ["installation-1", "wicked-woods-2025-general"]
            )
            try database.execute(
                sql: """
                    INSERT INTO pushOutbox (
                      installationID,
                      sourceID,
                      sourceVersion,
                      reason,
                      message,
                      createdAt,
                      failedAttempts,
                      nextAttemptAt
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    "installation-1",
                    "wicked-woods-2025-general",
                    "legacy-version",
                    "source_available",
                    Data(
                        #"{"kind":"source_available","source":"wicked-woods-2025-general","version":"legacy-version"}"#.utf8
                    ),
                    Date(timeIntervalSince1970: 1_786_291_200),
                    0,
                    Date(timeIntervalSince1970: 1_786_291_200),
                ]
            )
        }

        // Opening the real AppView store applies the shared notification migration in place.
        _ = try OpenMusicEventAppViewStore(database: rawDatabase)

        let migrated = try await rawDatabase.read { database in
            let outbox = try Row.fetchOne(
                database,
                sql: "SELECT discardedAt, discardReason FROM pushOutbox"
            )
            return (
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM pushInstallations"),
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM pushRegistrations"),
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM pushSubscriptions"),
                outbox?["discardedAt"] as String?,
                outbox?["discardReason"] as String?
            )
        }
        expectNoDifference(migrated.0, 1)
        expectNoDifference(migrated.1, 0)
        expectNoDifference(migrated.2, 1)
        #expect(migrated.3 != nil)
        expectNoDifference(
            migrated.4,
            NotificationDeliveryDiscardReason.invalidRegistration.rawValue
        )
    }

    @Test
    func `destination ciphertext is bound to its application metadata`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databaseURL = directory.appending(path: "appview.sqlite")
        let protection = try NotificationDestinationProtection(
            keyData: Data(repeating: 0x2A, count: 32)
        )
        let installation = NotificationInstallation(id: .init(rawValue: "installation-1"))
        let store = try OpenMusicEventAppViewStore(
            databaseURL: databaseURL
        )
        let notifications = notificationDatabase(store: store, protection: protection)
        try await notifications.insertInstallation(
            installation,
            credentialFingerprint: .init(rawValue: "credential-fingerprint")
        )
        try await notifications.replaceDestination(
            .apns(
                Push.APNS(
                    applicationID: .init(rawValue: "app.openmusicevent"),
                    environment: .development,
                    deviceToken: .init(rawValue: "provider-issued-device-token")
                )
            ),
            for: installation.id
        )

        // Changing addressing metadata invalidates the AES-GCM authenticated data.
        let rawDatabase = try DatabasePool(path: databaseURL.path(percentEncoded: false))
        try await rawDatabase.write { database in
            try database.execute(
                sql: "UPDATE pushRegistrations SET applicationID = ? WHERE installationID = ?",
                arguments: ["fm.woody.wickedwoods", installation.id.rawValue]
            )
        }
        await #expect(throws: (any Error).self) {
            try await notifications.destination(for: installation.id)
        }
    }

    @Test
    func `anonymous registration rejects an application outside the server allowlist`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let app = try OpenMusicEventAppViewServer.application(
            configuration: AppViewConfiguration(
                port: 0,
                databaseURL: directory.appending(path: "appview.sqlite"),
                notificationDestinationProtection: try NotificationDestinationProtection(
                    keyData: Data(repeating: 0x2A, count: 32)
                ),
                notificationRegistration: AppViewNotificationRegistrationConfiguration(
                    authorization: .anonymous,
                    allowedApplicationIDs: [.init(rawValue: "app.openmusicevent")]
                )
            )
        )

        try await app.test(.router) { client in
            let credential = try await client.execute(
                uri: NotificationRegistrationEndpoint.installationsPath,
                method: .post
            ) { response in
                try JSONDecoder().decode(
                    NotificationInstallationCredentialPayload.self,
                    from: Data(response.body.readableBytesView)
                ).credential
            }
            try await client.execute(
                uri: NotificationRegistrationEndpoint.destinationPath,
                method: .put,
                headers: [
                    .authorization: "Notification \(credential.rawValue)",
                    .contentType: "application/json",
                ],
                body: ByteBuffer(
                    data: try JSONEncoder().encode(
                        NotificationDestinationPayload(
                            .fcm(
                                Push.FCM(
                                    applicationID: .init(rawValue: "unknown.application"),
                                    registrationToken: .init(rawValue: "registration-token")
                                )
                            )
                        )
                    )
                )
            ) { response in
                #expect(response.status == .forbidden)
            }
        }
    }

    @Test
    func `registration rejects a provider with no application delivery route`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databaseURL = directory.appending(path: "appview.sqlite")
        let applicationID = Push.ApplicationID(rawValue: "app.openmusicevent")
        let app = try OpenMusicEventAppViewServer.application(
            configuration: AppViewConfiguration(
                port: 0,
                databaseURL: databaseURL,
                notificationProviders: AppViewNotificationProviderConfiguration(
                    apns: .init(
                        applications: [
                            applicationID: .init(
                                environment: .development,
                                topic: applicationID.rawValue
                            )
                        ],
                        teamID: "YJRWV8Z7KT",
                        keyID: "ABCDEFGHIJ",
                        privateKeyURL: directory.appending(path: "unused-apns-key.p8")
                    )
                ),
                notificationDestinationProtection: try NotificationDestinationProtection(
                    keyData: Data(repeating: 0x2A, count: 32)
                ),
                notificationRegistration: AppViewNotificationRegistrationConfiguration(
                    authorization: .anonymous,
                    allowedApplicationIDs: [applicationID]
                )
            )
        )

        try await app.test(.router) { client in
            let credential = try await client.execute(
                uri: NotificationRegistrationEndpoint.installationsPath,
                method: .post
            ) { response in
                try JSONDecoder().decode(
                    NotificationInstallationCredentialPayload.self,
                    from: Data(response.body.readableBytesView)
                ).credential
            }
            try await client.execute(
                uri: NotificationRegistrationEndpoint.destinationPath,
                method: .put,
                headers: [
                    .authorization: "Notification \(credential.rawValue)",
                    .contentType: "application/json",
                ],
                body: ByteBuffer(
                    data: try JSONEncoder().encode(
                        NotificationDestinationPayload(
                            .fcm(
                                Push.FCM(
                                    applicationID: applicationID,
                                    registrationToken: .init(rawValue: "registration-token")
                                )
                            )
                        )
                    )
                )
            ) { response in
                #expect(response.status == .forbidden)
            }
        }

        let rawDatabase = try DatabasePool(path: databaseURL.path(percentEncoded: false))
        let registrationCount = try await rawDatabase.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM pushRegistrations")
        }
        expectNoDifference(registrationCount, 0)
    }

    @Test
    func `legacy and production APNS registrations coexist with trusted environment routing`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databaseURL = directory.appending(path: "appview.sqlite")
        let applicationID = Push.ApplicationID(rawValue: "com.Festivl.WickedWoods")
        let app = try OpenMusicEventAppViewServer.application(
            configuration: AppViewConfiguration(
                port: 0,
                databaseURL: databaseURL,
                notificationProviders: AppViewNotificationProviderConfiguration(
                    apns: .init(
                        applications: [
                            applicationID: .init(
                                environment: .development,
                                allowedEnvironments: [.development, .production],
                                topic: applicationID.rawValue
                            )
                        ],
                        teamID: "YJRWV8Z7KT",
                        keyID: "ABCDEFGHIJ",
                        privateKeyURL: directory.appending(path: "unused-apns-key.p8")
                    ),
                    fcm: .init(
                        applications: [
                            applicationID: .init(
                                projectID: "ome-push-notifications",
                                emergencyChannelID: "emergency-alerts"
                            )
                        ],
                        serviceAccountURL: directory.appending(path: "unused-fcm-account.json")
                    )
                ),
                notificationDestinationProtection: try NotificationDestinationProtection(
                    keyData: Data(repeating: 0x2A, count: 32)
                ),
                notificationRegistration: AppViewNotificationRegistrationConfiguration(
                    authorization: .anonymous,
                    allowedApplicationIDs: [applicationID]
                )
            )
        )

        try await app.test(.router) { client in
            let credential = try await client.execute(
                uri: NotificationRegistrationEndpoint.installationsPath,
                method: .post
            ) { response in
                try JSONDecoder().decode(
                    NotificationInstallationCredentialPayload.self,
                    from: Data(response.body.readableBytesView)
                ).credential
            }
            let headers: HTTPFields = [
                .authorization: "Notification \(credential.rawValue)",
                .contentType: "application/json",
            ]

            try await client.execute(
                uri: NotificationRegistrationEndpoint.destinationPath,
                method: .put,
                headers: headers,
                body: ByteBuffer(
                    data: try JSONEncoder().encode(
                        NotificationDestinationPayload(
                            applicationID: applicationID.rawValue,
                            provider: .apns,
                            value: "legacy-development-token"
                        )
                    )
                )
            ) { response in
                #expect(response.status == .noContent)
            }
            try await client.execute(
                uri: NotificationRegistrationEndpoint.subscriptionsPath,
                method: .put,
                headers: headers,
                body: ByteBuffer(
                    data: try JSONEncoder().encode(
                        NotificationSubscriptionsPayload(sourceIDs: ["/events/2025/channels/news"])
                    )
                )
            ) { response in
                #expect(response.status == .noContent)
            }
            try await client.execute(
                uri: NotificationRegistrationEndpoint.destinationPath,
                method: .put,
                headers: headers,
                body: ByteBuffer(
                    data: try JSONEncoder().encode(
                        NotificationDestinationPayload(
                            .apns(
                                Push.APNS(
                                    applicationID: applicationID,
                                    environment: .production,
                                    deviceToken: .init(rawValue: "testflight-token")
                                )
                            )
                        )
                    )
                )
            ) { response in
                #expect(response.status == .noContent)
            }
            try await client.execute(
                uri: NotificationRegistrationEndpoint.destinationPath,
                method: .put,
                headers: headers,
                body: ByteBuffer(
                    data: try JSONEncoder().encode(
                        NotificationDestinationPayload(
                            applicationID: applicationID.rawValue,
                            apnsEnvironment: .production,
                            provider: .fcm,
                            value: "fcm-token"
                        )
                    )
                )
            ) { response in
                #expect(response.status == .badRequest)
            }
        }

        let rawDatabase = try DatabasePool(path: databaseURL.path(percentEncoded: false))
        let persisted = try await rawDatabase.read { database in
            let environment = try String.fetchOne(
                database,
                sql: "SELECT apnsEnvironment FROM pushRegistrations"
            )
            let subscriptionCount = try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM pushSubscriptions"
            )
            return (environment, subscriptionCount)
        }
        expectNoDifference(persisted.0, "production")
        expectNoDifference(persisted.1, 1)
    }

    @Test
    func `anonymous registration rejects an oversized provider destination`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databaseURL = directory.appending(path: "appview.sqlite")
        let app = try OpenMusicEventAppViewServer.application(
            configuration: AppViewConfiguration(
                port: 0,
                databaseURL: databaseURL,
                notificationDestinationProtection: try NotificationDestinationProtection(
                    keyData: Data(repeating: 0x2A, count: 32)
                ),
                notificationRegistration: AppViewNotificationRegistrationConfiguration(
                    authorization: .anonymous,
                    allowedApplicationIDs: [.init(rawValue: "app.openmusicevent")]
                )
            )
        )

        try await app.test(.router) { client in
            let credential = try await client.execute(
                uri: NotificationRegistrationEndpoint.installationsPath,
                method: .post
            ) { response in
                try JSONDecoder().decode(
                    NotificationInstallationCredentialPayload.self,
                    from: Data(response.body.readableBytesView)
                ).credential
            }
            try await client.execute(
                uri: NotificationRegistrationEndpoint.destinationPath,
                method: .put,
                headers: [
                    .authorization: "Notification \(credential.rawValue)",
                    .contentType: "application/json",
                ],
                body: ByteBuffer(
                    data: try JSONEncoder().encode(
                        NotificationDestinationPayload(
                            .apns(
                                Push.APNS(
                                    applicationID: .init(rawValue: "app.openmusicevent"),
                                    environment: .development,
                                    deviceToken: .init(
                                        rawValue: String(repeating: "x", count: 4_097)
                                    )
                                )
                            )
                        )
                    )
                )
            ) { response in
                #expect(response.status == .badRequest)
            }
        }

        let rawDatabase = try DatabasePool(path: databaseURL.path(percentEncoded: false))
        let registrationCount = try await rawDatabase.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM pushRegistrations")
        }
        expectNoDifference(registrationCount, 0)
    }

    @Test
    func `environment combines deployment credentials with per-application provider routing`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let providerConfigurationURL = directory.appending(path: "notification-providers.json")
        try Data(
            """
            {
              "apns": [
                {
                  "applicationID": "app.openmusicevent",
                  "environment": "development",
                  "topic": "app.openmusicevent"
                },
                {
                  "applicationID": "com.Festivl.WickedWoods",
                  "environment": "development",
                  "allowedEnvironments": ["development", "production"],
                  "topic": "com.Festivl.WickedWoods"
                }
              ],
              "fcm": [
                {
                  "applicationID": "com.Festivl.WickedWoods",
                  "projectID": "ome-push-notifications",
                  "emergencyChannelID": "emergency-alerts"
                }
              ]
            }
            """.utf8
        ).write(to: providerConfigurationURL)
        let privateKeyPath = "/run/credentials/open-music-event-appview/apns-private-key"
        let serviceAccountPath = "/run/credentials/open-music-event-appview/fcm-service-account"
        let configuration = try AppViewConfiguration.fromEnvironment(
            environment: [
                "OME_APNS_KEY_ID": "ABCDEFGHIJ",
                "OME_APNS_PRIVATE_KEY_PATH": privateKeyPath,
                "OME_APNS_TEAM_ID": "YJRWV8Z7KT",
                "OME_FCM_SERVICE_ACCOUNT_PATH": serviceAccountPath,
                "OME_NOTIFICATION_PROVIDER_CONFIGURATION_PATH": providerConfigurationURL.path,
            ]
        )

        expectNoDifference(
            configuration.notificationProviders,
            AppViewNotificationProviderConfiguration(
                apns: .init(
                    applications: [
                        .init(rawValue: "app.openmusicevent"): .init(
                            environment: .development,
                            topic: "app.openmusicevent"
                        ),
                        .init(rawValue: "com.Festivl.WickedWoods"): .init(
                            environment: .development,
                            allowedEnvironments: [.development, .production],
                            topic: "com.Festivl.WickedWoods"
                        ),
                    ],
                    teamID: "YJRWV8Z7KT",
                    keyID: "ABCDEFGHIJ",
                    privateKeyURL: URL(fileURLWithPath: privateKeyPath)
                ),
                fcm: .init(
                    applications: [
                        .init(rawValue: "com.Festivl.WickedWoods"): .init(
                            projectID: "ome-push-notifications",
                            emergencyChannelID: "emergency-alerts"
                        )
                    ],
                    serviceAccountURL: URL(fileURLWithPath: serviceAccountPath)
                )
            )
        )
    }

    @Test
    func `partial APNs credentials fail before the server starts`() throws {
        let configurationURL = FileManager.default.temporaryDirectory
            .appending(path: "notification-providers-\(UUID().uuidString).json")
        try Data(
            """
            {
              "apns": [
                {
                  "applicationID": "app.openmusicevent",
                  "environment": "development",
                  "topic": "app.openmusicevent"
                }
              ],
              "fcm": []
            }
            """.utf8
        ).write(to: configurationURL)
        defer { try? FileManager.default.removeItem(at: configurationURL) }

        #expect(
            throws: AppViewConfigurationError.notificationProviderConfigurationValueMissing(
                "OME_APNS_TEAM_ID"
            )
        ) {
            try AppViewConfiguration.fromEnvironment(
                environment: [
                    "OME_APNS_KEY_ID": "ABCDEFGHIJ",
                    "OME_APNS_PRIVATE_KEY_PATH": "/run/credentials/apns-private-key",
                    "OME_NOTIFICATION_PROVIDER_CONFIGURATION_PATH": configurationURL.path,
                ]
            )
        }
    }

    @Test
    func `blank notification provider routing fails before the server starts`() throws {
        let configurationURL = FileManager.default.temporaryDirectory
            .appending(path: "notification-providers-\(UUID().uuidString).json")
        try Data(
            """
            {
              "apns": [],
              "fcm": [
                {
                  "applicationID": "com.Festivl.WickedWoods",
                  "projectID": "ome-push-notifications",
                  "emergencyChannelID": "   "
                }
              ]
            }
            """.utf8
        ).write(to: configurationURL)
        defer { try? FileManager.default.removeItem(at: configurationURL) }

        #expect(
            throws: AppViewConfigurationError.notificationProviderConfigurationInvalid(
                configurationURL.path
            )
        ) {
            try AppViewConfiguration.fromEnvironment(
                environment: [
                    "OME_FCM_SERVICE_ACCOUNT_PATH": "/run/credentials/fcm-service-account",
                    "OME_NOTIFICATION_PROVIDER_CONFIGURATION_PATH": configurationURL.path,
                ]
            )
        }
    }

    @Test
    func `registration allowlist cannot name an application with no provider route`() throws {
        let configurationURL = FileManager.default.temporaryDirectory
            .appending(path: "notification-providers-\(UUID().uuidString).json")
        try Data(
            """
            {
              "apns": [],
              "fcm": [
                {
                  "applicationID": "com.Festivl.WickedWoods",
                  "projectID": "ome-push-notifications",
                  "emergencyChannelID": "emergency-alerts"
                }
              ]
            }
            """.utf8
        ).write(to: configurationURL)
        defer { try? FileManager.default.removeItem(at: configurationURL) }

        #expect(
            throws: AppViewConfigurationError.notificationProviderApplicationMissing(
                .init(rawValue: "app.openmusicevent")
            )
        ) {
            try AppViewConfiguration.fromEnvironment(
                environment: [
                    "OME_FCM_SERVICE_ACCOUNT_PATH": "/run/credentials/fcm-service-account",
                    "OME_NOTIFICATION_APPLICATION_IDS":
                        "app.openmusicevent,com.Festivl.WickedWoods",
                    "OME_NOTIFICATION_DESTINATION_KEY": Data(repeating: 0x2A, count: 32)
                        .base64EncodedString(),
                    "OME_NOTIFICATION_PROVIDER_CONFIGURATION_PATH": configurationURL.path,
                    "OME_NOTIFICATION_REGISTRATION_AUTHORIZATION": "anonymous",
                ]
            )
        }
    }

    @Test
    func `environment configures destination protection without embedding the key`() throws {
        let databasePath = "/tmp/open-music-event-appview-test.sqlite"
        let configuration = try AppViewConfiguration.fromEnvironment(
            environment: [
                "OME_APPVIEW_DATABASE_PATH": databasePath,
                "OME_NOTIFICATION_DESTINATION_KEY": Data(repeating: 0x2A, count: 32)
                    .base64EncodedString(),
                "OME_NOTIFICATION_DESTINATION_KEY_VERSION": "7",
                "OME_NOTIFICATION_REGISTRATION_AUTHORIZATION": "anonymous",
                "OME_NOTIFICATION_APPLICATION_IDS": "app.openmusicevent, fm.woody.wickedwoods",
            ]
        )

        expectNoDifference(configuration.databaseURL?.path, databasePath)
        expectNoDifference(configuration.notificationDestinationProtection?.keyVersion, 7)
        expectNoDifference(
            configuration.notificationRegistration?.allowedApplicationIDs,
            [
                Push.ApplicationID(rawValue: "app.openmusicevent"),
                Push.ApplicationID(rawValue: "fm.woody.wickedwoods"),
            ]
        )
    }

    @Test
    func `destination key alone does not enable anonymous registration`() throws {
        let configuration = try AppViewConfiguration.fromEnvironment(
            environment: [
                "OME_NOTIFICATION_DESTINATION_KEY": Data(repeating: 0x2A, count: 32)
                    .base64EncodedString()
            ]
        )

        #expect(configuration.notificationDestinationProtection != nil)
        #expect(configuration.notificationRegistration == nil)
    }

    @Test
    func `anonymous registration requires an application allowlist`() {
        #expect(throws: AppViewConfigurationError.notificationApplicationIDsMissing) {
            try AppViewConfiguration.fromEnvironment(
                environment: [
                    "OME_NOTIFICATION_DESTINATION_KEY": Data(repeating: 0x2A, count: 32)
                        .base64EncodedString(),
                    "OME_NOTIFICATION_REGISTRATION_AUTHORIZATION": "anonymous",
                ]
            )
        }
    }

    @Test
    func `environment rejects a destination key version without a key`() {
        #expect(
            throws: AppViewConfigurationError.notificationDestinationKeyMissing
        ) {
            try AppViewConfiguration.fromEnvironment(
                environment: ["OME_NOTIFICATION_DESTINATION_KEY_VERSION": "7"]
            )
        }
    }

    @Test
    func `environment rejects a destination key with the wrong length`() {
        #expect(
            throws: NotificationDestinationProtection.Error.invalidKeyLength(3)
        ) {
            try AppViewConfiguration.fromEnvironment(
                environment: [
                    "OME_NOTIFICATION_DESTINATION_KEY": Data([0x01, 0x02, 0x03])
                        .base64EncodedString()
                ]
            )
        }
    }

    @Test
    func `destination protection redacts its key from diagnostics`() throws {
        let keyData = Data("0123456789abcdef0123456789abcdef".utf8)
        let protection = try NotificationDestinationProtection(keyData: keyData)

        #expect(String(describing: protection).contains("<redacted>"))
        #expect(!String(reflecting: protection).contains(keyData.base64EncodedString()))
    }

    @Test
    func `notification outbox service ends normally when its delivery is cancelled`() async throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        let protection = try NotificationDestinationProtection(
            keyData: Data(repeating: 0x2A, count: 32)
        )
        let notifications = notificationDatabase(store: store, protection: protection)
        let installation = NotificationInstallation(id: .init(rawValue: "installation-1"))
        let source = NotificationSource(
            id: .init(rawValue: "at://did:plc:wickedwoods/app.openmusicevent.event/2026"),
            version: .init(rawValue: "bafy-source-version")
        )
        let now = Date()
        try await notifications.insertInstallation(
            installation,
            credentialFingerprint: .init(rawValue: "credential-fingerprint")
        )
        try await notifications.replaceDestination(
            .fcm(
                Push.FCM(
                    applicationID: .init(rawValue: "fm.woody.wickedwoods"),
                    registrationToken: .init(rawValue: "provider-token")
                )
            ),
            for: installation.id
        )
        try await notifications.replaceSubscriptions(
            [NotificationSubscription(sourceID: source.id)],
            for: installation.id
        )
        try await notifications.enqueue(source: source, at: now)

        let provider = NotificationProviderStartProbe()
        let service = NotificationOutboxService(
            database: database,
            destinationProtection: protection,
            legacyAPNSEnvironments: [:],
            provider: NotificationProviderClient { _, _ in
                await provider.start()
                try await ContinuousClock().sleep(for: .seconds(60))
                return .accepted(NotificationProviderResponse(status: 200))
            }
        )
        let serviceTask = Task {
            try await withDependencies {
                $0.continuousClock = ContinuousClock()
                $0.date.now = now
            } operation: {
                try await service.run()
            }
        }

        await provider.waitUntilStarted()
        serviceTask.cancel()
        try await serviceTask.value

        let failedAttempts = try await database.read { database in
            try Int.fetchOne(database, sql: "SELECT failedAttempts FROM pushOutbox")
        }
        expectNoDifference(failedAttempts, 0)
    }

    @Test
    func `notification outbox service surfaces delivery database failure`() async throws {
        let database = try DatabaseQueue()
        _ = try OpenMusicEventAppViewStore(database: database)
        let protection = try NotificationDestinationProtection(
            keyData: Data(repeating: 0x2A, count: 32)
        )
        let service = NotificationOutboxService(
            database: database,
            destinationProtection: protection,
            legacyAPNSEnvironments: [:],
            provider: NotificationProviderClient { _, _ in
                .accepted(NotificationProviderResponse(status: 200))
            }
        )
        try await database.write { database in
            try database.execute(sql: "DROP TABLE pushOutbox")
        }

        await #expect(throws: DatabaseError.self) {
            try await withDependencies {
                $0.continuousClock = ContinuousClock()
                $0.date.now = Date(timeIntervalSince1970: 1_786_291_200)
            } operation: {
                try await service.run()
            }
        }
    }
}
