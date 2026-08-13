import ComposableNotifications
import CustomDump
import Foundation
import GRDB
import Hummingbird
import HummingbirdTesting
@testable import OpenMusicEventAppViewServer
import SQLiteData
import Testing

@Suite(.serialized)
struct NotificationPersistenceTests {
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
                databaseURL: databaseURL,
                notificationDestinationProtection: protection
            )
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
            try await store.insertInstallation(
                installation,
                credentialFingerprint: credentialFingerprint
            )
            try await store.replaceDestination(originalDestination, for: installation.id)
            try await store.replaceSubscriptions(
                [NotificationSubscription(sourceID: .init(rawValue: "source-a"))],
                for: installation.id
            )
            try await store.replaceDestination(replacementDestination, for: installation.id)
            try await store.replaceSubscriptions(subscriptions, for: installation.id)
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
            databaseURL: databaseURL,
            notificationDestinationProtection: protection
        )
        let reopenedInstallationID = try await reopenedStore.installationID(
            for: credentialFingerprint
        )
        let reopenedDestination = try await reopenedStore.notificationDestination(
            for: installation.id
        )
        let reopenedSubscriptions = try await reopenedStore.notificationSubscriptions(
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
                databaseURL: databaseURL,
                notificationDestinationProtection: protection
            )
            try await store.insertInstallation(
                installation,
                credentialFingerprint: .init(rawValue: "credential-fingerprint")
            )
            try await store.replaceDestination(destination, for: installation.id)
            try await store.replaceSubscriptions(
                [NotificationSubscription(sourceID: source.id)],
                for: installation.id
            )

            let insertedCount = try await store.enqueueNotificationDeliveries(
                for: source,
                at: receivedAt
            )
            let duplicateCount = try await store.enqueueNotificationDeliveries(
                for: source,
                at: receivedAt
            )
            expectNoDifference(insertedCount, 1)
            expectNoDifference(duplicateCount, 0)
            let delivery = try #require(
                try await store.nextNotificationDelivery(at: receivedAt)
            )
            let signal = try delivery.message.signal()
            expectNoDifference(signal, .sourceAvailable(source))
            expectNoDifference(delivery.destination, destination)
            expectNoDifference(delivery.failedAttempts, 0)
            try await store.markNotificationDeliveryFailed(
                id: delivery.id,
                attemptedAt: receivedAt,
                retryAt: retryAt
            )
            let deliveryBeforeRetry = try await store.nextNotificationDelivery(at: receivedAt)
            #expect(deliveryBeforeRetry == nil)
        }

        let reopenedStore = try OpenMusicEventAppViewStore(
            databaseURL: databaseURL,
            notificationDestinationProtection: protection
        )
        let retriedDelivery = try #require(
            try await reopenedStore.nextNotificationDelivery(at: retryAt)
        )
        let retriedSignal = try retriedDelivery.message.signal()
        expectNoDifference(retriedSignal, .sourceAvailable(source))
        expectNoDifference(retriedDelivery.destination, destination)
        expectNoDifference(retriedDelivery.failedAttempts, 1)
        try await reopenedStore.markNotificationDeliverySucceeded(
            id: retriedDelivery.id,
            at: retryAt
        )
        let deliveryAfterSuccess = try await reopenedStore.nextNotificationDelivery(at: retryAt)
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
    func `outbox migration preserves an existing notification installation`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databaseURL = directory.appending(path: "appview.sqlite")
        let protection = try NotificationDestinationProtection(
            keyData: Data(repeating: 0x2A, count: 32)
        )
        let installation = NotificationInstallation(
            id: .init(rawValue: "pre-outbox-installation")
        )
        let credentialFingerprint = NotificationInstallation.CredentialFingerprint(
            rawValue: "pre-outbox-credential-fingerprint"
        )
        do {
            let store = try OpenMusicEventAppViewStore(
                databaseURL: databaseURL,
                notificationDestinationProtection: protection
            )
            try await store.insertInstallation(
                installation,
                credentialFingerprint: credentialFingerprint
            )
        }

        let rawDatabase = try DatabasePool(path: databaseURL.path(percentEncoded: false))
        try await rawDatabase.write { database in
            try database.execute(sql: "DROP TABLE pushOutbox")
            try database.execute(
                sql: "DELETE FROM grdb_migrations WHERE identifier = ?",
                arguments: ["Create push notification outbox"]
            )
        }

        let migratedStore = try OpenMusicEventAppViewStore(
            databaseURL: databaseURL,
            notificationDestinationProtection: protection
        )
        let migratedInstallationID = try await migratedStore.installationID(
            for: credentialFingerprint
        )
        expectNoDifference(migratedInstallationID, installation.id)
        let outboxExists = try await rawDatabase.read { database in
            try database.tableExists("pushOutbox")
        }
        expectNoDifference(outboxExists, true)
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
            databaseURL: databaseURL,
            notificationDestinationProtection: protection
        )
        try await store.insertInstallation(
            installation,
            credentialFingerprint: .init(rawValue: "credential-fingerprint")
        )
        try await store.replaceDestination(
            .apns(
                Push.APNS(
                    applicationID: .init(rawValue: "app.openmusicevent"),
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
            try await store.notificationDestination(for: installation.id)
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
    func `environment names the deployment APNs credential without embedding it`() throws {
        let privateKeyPath = "/run/credentials/open-music-event-appview/apns-private-key"
        let configuration = try AppViewConfiguration.fromEnvironment(
            environment: [
                "OME_APNS_APPLICATION_ID": "app.openmusicevent",
                "OME_APNS_ENVIRONMENT": "development",
                "OME_APNS_KEY_ID": "ABCDEFGHIJ",
                "OME_APNS_PRIVATE_KEY_PATH": privateKeyPath,
                "OME_APNS_TEAM_ID": "YJRWV8Z7KT",
            ]
        )

        expectNoDifference(
            configuration.apnsNotificationProvider,
            AppViewAPNSNotificationProviderConfiguration(
                applicationID: .init(rawValue: "app.openmusicevent"),
                environment: .development,
                topic: "app.openmusicevent",
                teamID: "YJRWV8Z7KT",
                keyID: "ABCDEFGHIJ",
                privateKeyURL: URL(fileURLWithPath: privateKeyPath)
            )
        )
    }

    @Test
    func `partial APNs environment fails before the server starts`() {
        #expect(
            throws: AppViewConfigurationError.apnsConfigurationValueMissing(
                "OME_APNS_ENVIRONMENT"
            )
        ) {
            try AppViewConfiguration.fromEnvironment(
                environment: ["OME_APNS_APPLICATION_ID": "app.openmusicevent"]
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
}
