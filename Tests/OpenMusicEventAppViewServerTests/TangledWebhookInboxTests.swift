import ATProto
import ComposableNotifications
import ComposableNotificationsHTTP
import ComposableNotificationsServer
import CustomDump
import Dependencies
import Foundation
import GRDB
import Hummingbird
import HummingbirdTesting
import HTTPClient
import HTTPTypes
import OpenMusicEventLexicon
import OpenMusicEventSourceClone
@testable import OpenMusicEventAppViewServer
import Testing

@Suite(.serialized)
struct TangledWebhookInboxTests {
    @Test
    func `legacy artifact configuration cannot override the watched Tangled repository`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let configurationURL = directory.appending(path: "tangled-webhooks.json")
        try Data(
            """
            {
              "watches": [
                {
                  "id": "woody.fm/wicked-woods-ome-stg#refs/heads/main",
                  "hookID": 42,
                  "repositoryOwnerDID": "did:plc:cqqtuv75m7e5s4uj6nw4czyu",
                  "repositoryKey": "wicked-woods-ome-stg",
                  "ref": "refs/heads/main",
                  "canonicalSource": {
                    "organizerID": "did:plc:5df2u7ief6m6tn77jznicxob",
                    "repositoryRecordKey": "ome-workspace"
                  },
                  "artifactRepository": {
                    "owner": "wickedwoods.ca",
                    "repository": "ome-workspace"
                  }
                }
              ]
            }
            """.utf8
        )
        .write(to: configurationURL)
        let keyURL = directory.appending(path: "webhook-secret-key")
        try Data(Self.protectionKey.base64EncodedString().utf8).write(to: keyURL)

        let configuration = try AppViewConfiguration.fromEnvironment(
            environment: [
                "OME_TANGLED_WEBHOOK_CONFIGURATION_PATH": configurationURL.path(percentEncoded: false),
                "OME_WEBHOOK_SECRET_KEY_PATH": keyURL.path(percentEncoded: false),
                "OME_SOURCE_ARTIFACT_S3_BUCKET": "openmusicevent-staging-resources",
                "OME_SOURCE_ARTIFACT_S3_REGION": "us-west-2",
                "OME_SOURCE_ARTIFACT_PUBLIC_ORIGIN":
                    "https://stg-resources.openmusicevent.app",
                "AWS_ACCESS_KEY_ID": "fixture-access-key",
                "AWS_SECRET_ACCESS_KEY": "fixture-secret-key",
            ]
        )

        let watches = try #require(configuration.tangledWebhook).watches
        expectNoDifference(
            watches,
            [
                TangledWebhookWatch(
                    repository: .init(
                        host: "tangled.org",
                        owner: "woody.fm",
                        repository: "wicked-woods-ome-stg"
                    ),
                    hookID: 42,
                    repositoryOwnerDID: try #require(
                        DID("did:plc:cqqtuv75m7e5s4uj6nw4czyu")
                    ),
                    ref: "refs/heads/main",
                    canonicalSource: CanonicalTangledSource(
                        organizerID: try #require(
                            OME.Organizer.ID("did:plc:5df2u7ief6m6tn77jznicxob")
                        ),
                        repositoryRecordKey: .init(rawValue: "ome-workspace")
                    )
                )
            ]
        )

        let watch = try #require(watches.first)
        let artifactConfiguration = try #require(configuration.sourceArtifacts)
        expectNoDifference(
            artifactConfiguration.reference(for: watch.repository),
            "https://stg-resources.openmusicevent.app/woody.fm/wicked-woods-ome-stg"
        )
        expectNoDifference(
            artifactConfiguration.objectKey(
                for: watch.repository,
                revision: "2222222222222222222222222222222222222222"
            ),
            "woody.fm/wicked-woods-ome-stg/archive/"
                + "2222222222222222222222222222222222222222.tar.gz"
        )
    }

    @Test
    func `one canonical source has only one authoritative physical watch`() throws {
        let firstWatch = TangledWebhookWatch(
            repository: .init(
                host: "tangled.org",
                owner: "staging-owner",
                repository: "wicked-woods-staging"
            ),
            hookID: 42,
            repositoryOwnerDID: try #require(DID("did:plc:staging-owner")),
            ref: "refs/heads/main",
            canonicalSource: CanonicalTangledSource(
                organizerID: try #require(OME.Organizer.ID("did:plc:wickedwoods")),
                repositoryRecordKey: .init(rawValue: "ome-workspace")
            )
        )

        let duplicateCanonicalSource = TangledWebhookWatch(
            repository: .init(
                host: "tangled.org",
                owner: "third-owner",
                repository: "another-wicked-woods-fork"
            ),
            hookID: 44,
            repositoryOwnerDID: try #require(DID("did:plc:third-owner")),
            ref: "refs/heads/main",
            canonicalSource: firstWatch.canonicalSource
        )
        expectNoDifference(
            #expect(throws: TangledWebhookConfigurationError.self) {
                try TangledWebhookConfiguration(
                    watches: [firstWatch, duplicateCanonicalSource]
                )
            },
            .duplicateCanonicalSource(
                "at://did:plc:wickedwoods/sh.tangled.repo/ome-workspace"
            )
        )
    }

    @Test
    func `configured webhook intake requires AppView persistence`() throws {
        #expect(throws: OpenMusicEventAppViewServerError.tangledWebhookRequiresDatabase) {
            _ = try OpenMusicEventAppViewServer.application(
                configuration: AppViewConfiguration(
                    port: 0,
                    tangledWebhook: Self.webhookConfiguration()
                )
            )
        }
    }

    @Test
    func `public watch configuration resolves its encrypted database secret`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let configurationURL = directory.appending(path: "tangled-webhooks.json")
        try Data(
            """
            {
              "watches": [{
                "id": "\(Self.watchID.rawValue)",
                "hookID": \(Self.hookID),
                "repositoryOwnerDID": "\(Self.repositoryDID)",
                "ref": "refs/heads/main",
                "canonicalSource": {
                  "organizerID": "\(Self.canonicalOrganizerID)",
                  "repositoryRecordKey": "\(Self.canonicalRepositoryRecordKey)"
                }
              }]
            }
            """.utf8
        )
        .write(to: configurationURL)

        let keyURL = directory.appending(path: "webhook-secret-key")
        try Data(Self.protectionKey.base64EncodedString().utf8).write(to: keyURL)
        let configuration = try AppViewConfiguration.fromEnvironment(
            environment: [
                "OME_APPVIEW_DATABASE_PATH": directory
                    .appending(path: "appview.sqlite")
                    .path(percentEncoded: false),
                "OME_TANGLED_WEBHOOK_CONFIGURATION_PATH": configurationURL
                    .path(percentEncoded: false),
                "OME_WEBHOOK_SECRET_KEY_PATH": keyURL.path(percentEncoded: false),
                "OME_SOURCE_ARTIFACT_S3_BUCKET": "resources.openmusicevent.app",
                "OME_SOURCE_ARTIFACT_S3_REGION": "us-west-2",
                "OME_SOURCE_ARTIFACT_PUBLIC_ORIGIN": "https://resources.openmusicevent.app",
                "AWS_ACCESS_KEY_ID": "fixture-access-key",
                "AWS_SECRET_ACCESS_KEY": "fixture-secret-key",
            ]
        )
        let store = try OpenMusicEventAppViewStore(
            databaseURL: try #require(configuration.databaseURL),
            webhookSecretProtection: configuration.webhookSecretProtection
        )
        try await store.replaceWebhookSecret(
            Self.secret,
            source: .tangled,
            watchID: Self.watchID
        )
        let receiver = TangledWebhookServer(
            configuration: try #require(configuration.tangledWebhook),
            inbox: store,
            secret: { watchID in
                try await store.webhookSecret(source: .tangled, watchID: watchID)
            }
        )
        let payload = Self.pushPayload()

        let result = try await receiver.receive(
            TangledWebhookRequest(
                event: "push",
                hookID: "\(Self.hookID)",
                deliveryID: Self.deliveryID,
                repository: Self.repositoryFullName,
                signature: TangledWebhookSignature.value(
                    authenticating: payload,
                    secret: Self.secret
                ),
                payload: payload
            ),
            receivedAt: Self.receivedAt
        )

        expectNoDifference(result.recordResult, .inserted)
        expectNoDifference(
            result.sourceUpdate,
            TangledSourceUpdate(
                watchID: Self.watchID,
                deliveryID: .init(rawValue: Self.deliveryID),
                repositoryOwnerDID: try #require(DID(Self.repositoryDID)),
                ref: "refs/heads/main",
                before: "1111111111111111111111111111111111111111",
                after: "2222222222222222222222222222222222222222",
                receivedAt: Self.receivedAt,
                canonicalSource: CanonicalTangledSource(
                    organizerID: try #require(OME.Organizer.ID(Self.canonicalOrganizerID)),
                    repositoryRecordKey: .init(rawValue: Self.canonicalRepositoryRecordKey)
                ),
                repository: Self.repository
            )
        )
        let persisted = try await Self.persistedInbox(
            at: try #require(configuration.databaseURL)
        )
        expectNoDifference(persisted.count, 1)

        let rawDatabase = try DatabasePool(
            path: try #require(configuration.databaseURL).path(percentEncoded: false)
        )
        let ciphertext = try await rawDatabase.read { database in
            try Data.fetchOne(database, sql: "SELECT secret FROM webhookSecrets")
        }
        #expect(try #require(ciphertext).range(of: Self.secret) == nil)
    }

    @Test
    func `configured watch requires webhook protection and artifact storage`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let configurationURL = directory.appending(path: "tangled-webhooks.json")
        try Data(
            """
            {
              "watches": [{
                "id": "\(Self.watchID.rawValue)",
                "hookID": \(Self.hookID),
                "repositoryOwnerDID": "\(Self.repositoryDID)",
                "ref": "refs/heads/main",
                "canonicalSource": {
                  "organizerID": "\(Self.canonicalOrganizerID)",
                  "repositoryRecordKey": "\(Self.canonicalRepositoryRecordKey)"
                }
              }]
            }
            """.utf8
        )
        .write(to: configurationURL)

        // A public watch cannot receive authenticated webhooks without its encryption key.
        #expect(throws: AppViewConfigurationError.webhookSecretKeyMissing) {
            try AppViewConfiguration.fromEnvironment(
                environment: [
                    "OME_TANGLED_WEBHOOK_CONFIGURATION_PATH": configurationURL
                        .path(percentEncoded: false)
                ]
            )
        }

        // Supplying that key reveals the next deployment requirement: durable artifact storage.
        let keyURL = directory.appending(path: "webhook-secret-key")
        try Data(Self.protectionKey.base64EncodedString().utf8).write(to: keyURL)
        #expect(throws: AppViewConfigurationError.sourceArtifactConfigurationMissing) {
            try AppViewConfiguration.fromEnvironment(
                environment: [
                    "OME_TANGLED_WEBHOOK_CONFIGURATION_PATH": configurationURL
                        .path(percentEncoded: false),
                    "OME_WEBHOOK_SECRET_KEY_PATH": keyURL.path(percentEncoded: false),
                ]
            )
        }
    }

    @Test
    func `a verified Wicked Woods main push becomes one durable inbox delivery`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databaseURL = directory.appending(path: "appview.sqlite")
        let payload = Self.pushPayload()

        do {
            let store = try OpenMusicEventAppViewStore(
                databaseURL: databaseURL,
                webhookSecretProtection: Self.webhookSecretProtection()
            )
            try await store.replaceWebhookSecret(
                Self.secret,
                source: .tangled,
                watchID: Self.watchID
            )
            let app = try withDependencies {
                $0.date.now = Self.receivedAt
            } operation: {
                try OpenMusicEventAppViewServer.application(
                    configuration: AppViewConfiguration(
                        port: 0,
                        tangledWebhook: Self.webhookConfiguration()
                    ),
                    store: store,
                    tangledSourceUpdateProcessor: Self.notificationOutbox(store: store)
                )
            }

            try await withDependencies {
                $0.date.now = Self.receivedAt
            } operation: {
                try await app.test(.router) { client in
                    try await client.execute(
                        uri: TangledWebhookEndpoint.path,
                        method: .post,
                        headers: Self.headers(authenticating: payload),
                        body: ByteBuffer(data: payload)
                    ) { response in
                        #expect(response.status == .accepted)
                    }

                    // Tangled retries the same delivery ID after a failed acknowledgement.
                    try await client.execute(
                        uri: TangledWebhookEndpoint.path,
                        method: .post,
                        headers: Self.headers(authenticating: payload),
                        body: ByteBuffer(data: payload)
                    ) { response in
                        #expect(response.status == .accepted)
                    }

                    // A delivery ID cannot silently be reused for different verified bytes.
                    let conflictingPayload = Self.pushPayload(
                        after: "3333333333333333333333333333333333333333"
                    )
                    try await client.execute(
                        uri: TangledWebhookEndpoint.path,
                        method: .post,
                        headers: Self.headers(authenticating: conflictingPayload),
                        body: ByteBuffer(data: conflictingPayload)
                    ) { response in
                        #expect(response.status == .conflict)
                    }
                }
            }
        }

        let persistedAfterFirstProcess = try await Self.persistedInbox(at: databaseURL)
        expectNoDifference(
            persistedAfterFirstProcess,
            PersistedInbox(
                count: 1,
                delivery: PersistedDelivery(
                    source: "tangled",
                    watchID: Self.watchID.rawValue,
                    deliveryID: Self.deliveryID,
                    event: "push",
                    payload: payload,
                    receivedAt: Self.receivedAt
                )
            )
        )

        // A process restart still recognizes the provider's retry as the same delivery.
        do {
            let reopenedStore = try OpenMusicEventAppViewStore(
                databaseURL: databaseURL,
                webhookSecretProtection: Self.webhookSecretProtection()
            )
            let retryDate = Self.receivedAt.addingTimeInterval(60)
            let app = try withDependencies {
                $0.date.now = retryDate
            } operation: {
                try OpenMusicEventAppViewServer.application(
                    configuration: AppViewConfiguration(
                        port: 0,
                        tangledWebhook: Self.webhookConfiguration()
                    ),
                    store: reopenedStore,
                    tangledSourceUpdateProcessor: Self.notificationOutbox(store: reopenedStore)
                )
            }
            try await withDependencies {
                $0.date.now = retryDate
            } operation: {
                try await app.test(.router) { client in
                    try await client.execute(
                        uri: TangledWebhookEndpoint.path,
                        method: .post,
                        headers: Self.headers(authenticating: payload),
                        body: ByteBuffer(data: payload)
                    ) { response in
                        #expect(response.status == .accepted)
                    }
                }
            }
        }

        let persistedAfterRestart = try await Self.persistedInbox(at: databaseURL)
        expectNoDifference(
            persistedAfterRestart,
            PersistedInbox(
                count: 1,
                delivery: PersistedDelivery(
                    source: "tangled",
                    watchID: Self.watchID.rawValue,
                    deliveryID: Self.deliveryID,
                    event: "push",
                    payload: payload,
                    receivedAt: Self.receivedAt
                )
            )
        )
    }

    @Test
    func `a source update processing failure leaves the durable webhook retryable`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databaseURL = directory.appending(path: "appview.sqlite")
        let store = try OpenMusicEventAppViewStore(
            databaseURL: databaseURL,
            webhookSecretProtection: Self.webhookSecretProtection()
        )
        try await store.replaceWebhookSecret(
            Self.secret,
            source: .tangled,
            watchID: Self.watchID
        )
        let processor = FailOnceSourceUpdateProcessor()
        let app = try withDependencies {
            $0.date.now = Self.receivedAt
        } operation: {
            try OpenMusicEventAppViewServer.application(
                configuration: AppViewConfiguration(
                    port: 0,
                    tangledWebhook: Self.webhookConfiguration()
                ),
                store: store,
                tangledSourceUpdateProcessor: TangledSourceUpdateProcessor { update in
                    try await processor.process(update)
                }
            )
        }
        let payload = Self.pushPayload()

        try await withDependencies {
            $0.date.now = Self.receivedAt
        } operation: {
            try await app.test(.router) { client in
                try await client.execute(
                    uri: TangledWebhookEndpoint.path,
                    method: .post,
                    headers: Self.headers(authenticating: payload),
                    body: ByteBuffer(data: payload)
                ) { response in
                    #expect(response.status == .internalServerError)
                }
                try await client.execute(
                    uri: TangledWebhookEndpoint.path,
                    method: .post,
                    headers: Self.headers(authenticating: payload),
                    body: ByteBuffer(data: payload)
                ) { response in
                    #expect(response.status == .accepted)
                }
            }
        }

        let attemptCount = await processor.attemptCount
        let persistedCount = try await Self.persistedInbox(at: databaseURL).count
        expectNoDifference(attemptCount, 2)
        expectNoDifference(persistedCount, 1)
    }

    @Test
    func `a verified source update fans out exact APNs and FCM JSON`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let apnsPrivateKeyURL = directory.appending(path: "AuthKey_ABCDEFGHIJ.p8")
        try Data(Self.fixtureAPNSPrivateKey.utf8).write(to: apnsPrivateKeyURL)
        let fcmServiceAccountURL = directory.appending(path: "fcm-service-account.json")
        try JSONSerialization.data(
            withJSONObject: [
                "project_id": "ome-push-notifications",
                "client_email": "notifications@ome-push-notifications.iam.gserviceaccount.com",
                "private_key_id": "fixture-google-key-id",
                "private_key": Self.fixtureFCMPrivateKey,
                "token_uri": "https://oauth.example.test/token",
            ]
        ).write(to: fcmServiceAccountURL)
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
                  "environment": "production",
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

        let destinationProtection = try NotificationDestinationProtection(
            keyData: Data(repeating: 0x3B, count: 32)
        )
        let store = try OpenMusicEventAppViewStore(
            databaseURL: directory.appending(path: "appview.sqlite"),
            webhookSecretProtection: Self.webhookSecretProtection()
        )
        let omeApplicationID = Push.ApplicationID(rawValue: "app.openmusicevent")
        let wickedWoodsApplicationID = Push.ApplicationID(rawValue: "com.Festivl.WickedWoods")
        let omeAPNSDestination = Push.Destination.apns(
            Push.APNS(
                applicationID: omeApplicationID,
                environment: .development,
                deviceToken: .init(rawValue: "fixture-ome-apns-device-token")
            )
        )
        let wickedWoodsAPNSDestination = Push.Destination.apns(
            Push.APNS(
                applicationID: wickedWoodsApplicationID,
                environment: .production,
                deviceToken: .init(rawValue: "fixture-wicked-woods-apns-device-token")
            )
        )
        let wickedWoodsFCMDestination = Push.Destination.fcm(
            Push.FCM(
                applicationID: wickedWoodsApplicationID,
                installationID: .init(rawValue: "fixture-wicked-woods-fcm-installation-id")
            )
        )
        let subscriptions = NotificationSubscriptionsPayload(
            [NotificationSubscription(sourceID: Self.sourceID)]
        )
        try await store.replaceWebhookSecret(
            Self.secret,
            source: .tangled,
            watchID: Self.watchID
        )

        let providerRequests = ProviderHTTPRequestRecorder()
        let tokenRequests = ProviderHTTPRequestRecorder()
        let payload = Self.pushPayload()

        // This is the only mocked boundary in the story. The request has already passed through
        // the real signed webhook route, SQLite inbox and outbox, lifecycle worker, provider
        // selection, APNs credential loading and JWT signing, and provider JSON encoder before it
        // reaches this raw-network closure.
        try await withDependencies {
            $0.continuousClock = ContinuousClock()
            $0.date.now = Self.receivedAt
            $0.httpClient = .liveValue
            $0.requestInterceptors = []
            $0.responseInterceptors = []
            $0.errorInterceptors = []
            $0.dataForURL = { request, body in
                if request.url?.absoluteString == "https://oauth.example.test/token" {
                    await tokenRequests.record(request, body: body)
                    return (
                        Data(
                            """
                            {
                              "access_token": "fixture-fcm-oauth",
                              "expires_in": 3600,
                              "token_type": "Bearer"
                            }
                            """.utf8
                        ),
                        HTTPResponse(status: .ok)
                    )
                }
                await providerRequests.recordAndWaitForRelease(request, body: body)
                return (Data(), HTTPResponse(status: .ok))
            }
        } operation: {
            var appConfiguration = try AppViewConfiguration.fromEnvironment(
                environment: [
                    "OME_APNS_KEY_ID": "ABCDEFGHIJ",
                    "OME_APNS_PRIVATE_KEY_PATH": apnsPrivateKeyURL.path,
                    "OME_APNS_TEAM_ID": "YJRWV8Z7KT",
                    "OME_FCM_SERVICE_ACCOUNT_PATH": fcmServiceAccountURL.path,
                    "OME_NOTIFICATION_PROVIDER_CONFIGURATION_PATH":
                        providerConfigurationURL.path,
                ]
            )
            appConfiguration.port = 0
            appConfiguration.notificationDestinationProtection = destinationProtection
            appConfiguration.notificationRegistration = AppViewNotificationRegistrationConfiguration(
                authorization: .anonymous,
                allowedApplicationIDs: [omeApplicationID, wickedWoodsApplicationID]
            )
            appConfiguration.tangledWebhook = try Self.webhookConfiguration()
            let provider = try #require(
                await appConfiguration.notificationProvider()
            )
            let app = try OpenMusicEventAppViewServer.application(
                configuration: appConfiguration,
                store: store,
                notificationProvider: provider,
                tangledSourceUpdateProcessor: Self.notificationOutbox(store: store)
            )

            try await app.test(.live) { client in
                // The iPhone creates an anonymous installation through the public server route.
                let omeAPNSCredential = try await client.execute(
                    uri: NotificationRegistrationEndpoint.installationsPath,
                    method: .post
                ) { response in
                    #expect(response.status == .created)
                    return try JSONDecoder().decode(
                        NotificationInstallationCredentialPayload.self,
                        from: Data(response.body.readableBytesView)
                    ).credential
                }

                // It registers its OME APNs token and subscribes to the Wicked Woods source.
                try await client.execute(
                    uri: NotificationRegistrationEndpoint.destinationPath,
                    method: .put,
                    headers: [
                        .authorization: "Notification \(omeAPNSCredential.rawValue)",
                        .contentType: "application/json",
                    ],
                    body: ByteBuffer(
                        data: try JSONEncoder().encode(
                            NotificationDestinationPayload(omeAPNSDestination)
                        )
                    )
                ) { response in
                    #expect(response.status == .noContent)
                }
                try await client.execute(
                    uri: NotificationRegistrationEndpoint.subscriptionsPath,
                    method: .put,
                    headers: [
                        .authorization: "Notification \(omeAPNSCredential.rawValue)",
                        .contentType: "application/json",
                    ],
                    body: ByteBuffer(data: try JSONEncoder().encode(subscriptions))
                ) { response in
                    #expect(response.status == .noContent)
                }

                // The branded iOS app registers under its own APNs topic.
                let wickedWoodsAPNSCredential = try await client.execute(
                    uri: NotificationRegistrationEndpoint.installationsPath,
                    method: .post
                ) { response in
                    #expect(response.status == .created)
                    return try JSONDecoder().decode(
                        NotificationInstallationCredentialPayload.self,
                        from: Data(response.body.readableBytesView)
                    ).credential
                }
                try await client.execute(
                    uri: NotificationRegistrationEndpoint.destinationPath,
                    method: .put,
                    headers: [
                        .authorization: "Notification \(wickedWoodsAPNSCredential.rawValue)",
                        .contentType: "application/json",
                    ],
                    body: ByteBuffer(
                        data: try JSONEncoder().encode(
                            NotificationDestinationPayload(wickedWoodsAPNSDestination)
                        )
                    )
                ) { response in
                    #expect(response.status == .noContent)
                }
                try await client.execute(
                    uri: NotificationRegistrationEndpoint.subscriptionsPath,
                    method: .put,
                    headers: [
                        .authorization: "Notification \(wickedWoodsAPNSCredential.rawValue)",
                        .contentType: "application/json",
                    ],
                    body: ByteBuffer(data: try JSONEncoder().encode(subscriptions))
                ) { response in
                    #expect(response.status == .noContent)
                }

                // The Android app independently registers its FCM installation ID for the same
                // source.
                let fcmCredential = try await client.execute(
                    uri: NotificationRegistrationEndpoint.installationsPath,
                    method: .post
                ) { response in
                    #expect(response.status == .created)
                    return try JSONDecoder().decode(
                        NotificationInstallationCredentialPayload.self,
                        from: Data(response.body.readableBytesView)
                    ).credential
                }
                try await client.execute(
                    uri: NotificationRegistrationEndpoint.destinationPath,
                    method: .put,
                    headers: [
                        .authorization: "Notification \(fcmCredential.rawValue)",
                        .contentType: "application/json",
                    ],
                    body: ByteBuffer(
                        data: try JSONEncoder().encode(
                            NotificationDestinationPayload(wickedWoodsFCMDestination)
                        )
                    )
                ) { response in
                    #expect(response.status == .noContent)
                }
                try await client.execute(
                    uri: NotificationRegistrationEndpoint.subscriptionsPath,
                    method: .put,
                    headers: [
                        .authorization: "Notification \(fcmCredential.rawValue)",
                        .contentType: "application/json",
                    ],
                    body: ByteBuffer(data: try JSONEncoder().encode(subscriptions))
                ) { response in
                    #expect(response.status == .noContent)
                }

                // Tangled's signed HTTP delivery only commits the inbox and three outbox jobs.
                // Provider responses remain blocked, so a 202 here proves provider I/O is no
                // longer part of the webhook request.
                try await client.execute(
                    uri: TangledWebhookEndpoint.path,
                    method: .post,
                    headers: Self.headers(authenticating: payload),
                    body: ByteBuffer(data: payload)
                ) { response in
                    #expect(response.status == .accepted)
                }

                // Replaying the same verified delivery cannot enqueue another set of jobs.
                try await client.execute(
                    uri: TangledWebhookEndpoint.path,
                    method: .post,
                    headers: Self.headers(authenticating: payload),
                    body: ByteBuffer(data: payload)
                ) { response in
                    #expect(response.status == .accepted)
                }

                await providerRequests.releaseProviderResponses()
                try await providerRequests.waitForRequestCount(3)
                try await Self.waitForDeliveredOutboxCount(3, in: store.database)
            }
        }

        let requests = await providerRequests.requests
        expectNoDifference(requests.count, 3)
        let outboxCount = try await store.database.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM pushOutbox") ?? 0
        }
        expectNoDifference(outboxCount, 3)
        let apns = requests.filter {
            $0.request.url?.host?.hasSuffix("push.apple.com") == true
        }
        expectNoDifference(apns.count, 2)
        let fcm = try #require(
            requests.first {
                $0.request.url?.absoluteString.hasPrefix("https://fcm.googleapis.com/") == true
            }
        )

        let omeAPNS = try #require(
            apns.first {
                $0.request.url?.absoluteString.hasSuffix("/fixture-ome-apns-device-token") == true
            }
        )
        let wickedWoodsAPNS = try #require(
            apns.first {
                $0.request.url?.absoluteString.hasSuffix(
                    "/fixture-wicked-woods-apns-device-token"
                ) == true
            }
        )

        // Each APNs application receives the same background signal under its own topic.
        expectNoDifference(omeAPNS.request.method, .post)
        expectNoDifference(
            omeAPNS.request.url?.absoluteString,
            "https://api.sandbox.push.apple.com/3/device/fixture-ome-apns-device-token"
        )
        expectNoDifference(
            wickedWoodsAPNS.request.url?.absoluteString,
            "https://api.push.apple.com/3/device/fixture-wicked-woods-apns-device-token"
        )
        let authorization = try #require(omeAPNS.request.headerFields[.authorization])
        let token = try #require(
            authorization.hasPrefix("bearer ")
                ? String(authorization.dropFirst("bearer ".count))
                : nil
        )
        expectNoDifference(
            try Self.decodedAPNSProviderToken(token),
            DecodedAPNSProviderToken(
                algorithm: "ES256",
                issuedAt: Int64(Self.receivedAt.timeIntervalSince1970),
                issuer: "YJRWV8Z7KT",
                keyID: "ABCDEFGHIJ",
                type: "JWT"
            )
        )
        for request in [omeAPNS, wickedWoodsAPNS] {
            expectNoDifference(request.request.headerFields[.contentType], "application/json")
            expectNoDifference(request.request.headerFields[.init("apns-priority")!], "5")
            expectNoDifference(
                request.request.headerFields[.init("apns-push-type")!],
                "background"
            )
            expectNoDifference(
                String(decoding: try #require(request.body), as: UTF8.self),
                #"{"aps":{"content-available":1},"kind":"source_available","source":"\#(Self.sourceID.rawValue)","version":"2222222222222222222222222222222222222222"}"#
            )
        }
        expectNoDifference(
            omeAPNS.request.headerFields[.init("apns-topic")!],
            "app.openmusicevent"
        )
        expectNoDifference(
            wickedWoodsAPNS.request.headerFields[.init("apns-topic")!],
            "com.Festivl.WickedWoods"
        )

        // FCM receives the same semantic data as string values in its HTTP v1 message envelope.
        expectNoDifference(fcm.request.method, .post)
        expectNoDifference(
            fcm.request.url?.absoluteString,
            "https://fcm.googleapis.com/v1/projects/ome-push-notifications/messages:send"
        )
        expectNoDifference(fcm.request.headerFields[.authorization], "Bearer fixture-fcm-oauth")
        expectNoDifference(fcm.request.headerFields[.contentType], "application/json")
        expectNoDifference(
            String(decoding: try #require(fcm.body), as: UTF8.self),
            #"{"message":{"data":{"kind":"source_available","source":"\#(Self.sourceID.rawValue)","version":"2222222222222222222222222222222222222222"},"fid":"fixture-wicked-woods-fcm-installation-id"}}"#
        )

        let oauthRequests = await tokenRequests.requests
        expectNoDifference(oauthRequests.count, 1)
        let oauth = try #require(oauthRequests.first)
        expectNoDifference(oauth.request.method, .post)
        expectNoDifference(oauth.request.url?.absoluteString, "https://oauth.example.test/token")
        expectNoDifference(
            oauth.request.headerFields[.contentType],
            "application/x-www-form-urlencoded"
        )
        let oauthForm = try Self.decodedForm(try #require(oauth.body))
        expectNoDifference(
            oauthForm["grant_type"],
            "urn:ietf:params:oauth:grant-type:jwt-bearer"
        )
        let assertion = try #require(oauthForm["assertion"])
        expectNoDifference(
            try Self.decodedFCMServiceAccountAssertion(assertion),
            DecodedFCMServiceAccountAssertion(
                algorithm: "RS256",
                audience: "https://oauth.example.test/token",
                expiration: Int64(Self.receivedAt.timeIntervalSince1970) + 3_600,
                issuedAt: Int64(Self.receivedAt.timeIntervalSince1970),
                issuer: "notifications@ome-push-notifications.iam.gserviceaccount.com",
                keyID: "fixture-google-key-id",
                scope: "https://www.googleapis.com/auth/firebase.messaging",
                type: "JWT"
            )
        )
    }

    @Test
    func `a throttled provider request honors Retry-After and is delivered from the same outbox after restart`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databaseURL = directory.appending(path: "appview.sqlite")
        let destinationProtection = try NotificationDestinationProtection(
            keyData: Data(repeating: 0x3B, count: 32)
        )
        let fcmApplicationID = Push.ApplicationID(rawValue: "fm.woody.openmusicevent")
        let destination = Push.Destination.fcm(
            Push.FCM(
                applicationID: fcmApplicationID,
                installationID: .init(rawValue: "fixture-fcm-installation-id")
            )
        )
        let subscriptions = NotificationSubscriptionsPayload(
            [NotificationSubscription(sourceID: Self.sourceID)]
        )
        let firstRequests = ProviderHTTPRequestRecorder()
        let payload = Self.pushPayload()

        let store = try OpenMusicEventAppViewStore(
            databaseURL: databaseURL,
            webhookSecretProtection: Self.webhookSecretProtection()
        )
        try await store.replaceWebhookSecret(
            Self.secret,
            source: .tangled,
            watchID: Self.watchID
        )

        try await withDependencies {
            $0.continuousClock = ContinuousClock()
            $0.date.now = Self.receivedAt
            $0.httpClient = .liveValue
            $0.requestInterceptors = []
            $0.responseInterceptors = []
            $0.errorInterceptors = []
            $0.dataForURL = { request, body in
                await firstRequests.record(request, body: body)
                var response = HTTPResponse(status: .tooManyRequests)
                response.headerFields[.retryAfter] = "1"
                return (
                    Data(#"{"error":{"status":"RESOURCE_EXHAUSTED"}}"#.utf8),
                    response
                )
            }
        } operation: {
            let provider = NotificationProviderClient.http(
                configuration: NotificationProviderHTTPConfiguration(
                    fcm: [fcmApplicationID: .init(projectID: "open-music-event")]
                ),
                authorization: NotificationProviderAuthorization(
                    apnsBearerToken: { applicationID in
                        throw NotificationProviderHTTPError.missingAPNSConfiguration(
                            applicationID
                        )
                    },
                    fcmAccessToken: { _ in "fixture-fcm-oauth" }
                )
            )
            let app = try OpenMusicEventAppViewServer.application(
                configuration: AppViewConfiguration(
                    port: 0,
                    notificationDestinationProtection: destinationProtection,
                    notificationRegistration: AppViewNotificationRegistrationConfiguration(
                        authorization: .anonymous,
                        allowedApplicationIDs: [fcmApplicationID]
                    ),
                    tangledWebhook: Self.webhookConfiguration()
                ),
                store: store,
                notificationProvider: provider,
                tangledSourceUpdateProcessor: Self.notificationOutbox(store: store)
            )

            try await app.test(.live) { client in
                let credential = try await client.execute(
                    uri: NotificationRegistrationEndpoint.installationsPath,
                    method: .post
                ) { response in
                    #expect(response.status == .created)
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
                            NotificationDestinationPayload(destination)
                        )
                    )
                ) { response in
                    #expect(response.status == .noContent)
                }
                try await client.execute(
                    uri: NotificationRegistrationEndpoint.subscriptionsPath,
                    method: .put,
                    headers: [
                        .authorization: "Notification \(credential.rawValue)",
                        .contentType: "application/json",
                    ],
                    body: ByteBuffer(data: try JSONEncoder().encode(subscriptions))
                ) { response in
                    #expect(response.status == .noContent)
                }

                // Provider failure happens after acknowledgement and leaves the job pending.
                try await client.execute(
                    uri: TangledWebhookEndpoint.path,
                    method: .post,
                    headers: Self.headers(authenticating: payload),
                    body: ByteBuffer(data: payload)
                ) { response in
                    #expect(response.status == .accepted)
                }
                try await firstRequests.waitForRequestCount(1)
                try await Self.waitForFailedOutboxCount(1, in: store.database)
            }
        }

        let retryAt = Self.receivedAt.addingTimeInterval(1)
        let pendingLedger = try store.database.read { database in
            try Row.fetchOne(
                database,
                sql: """
                    SELECT
                      failedAttempts,
                      nextAttemptAt,
                      discardedAt,
                      providerStatus,
                      providerCode
                    FROM pushOutbox
                    """
            )
        }
        let pendingRow = try #require(pendingLedger)
        expectNoDifference(pendingRow["failedAttempts"] as Int, 1)
        expectNoDifference(pendingRow["nextAttemptAt"] as Date, retryAt)
        #expect((pendingRow["discardedAt"] as Date?) == nil)
        expectNoDifference(pendingRow["providerStatus"] as Int?, 429)
        expectNoDifference(pendingRow["providerCode"] as String?, "RESOURCE_EXHAUSTED")

        let retryRequests = ProviderHTTPRequestRecorder()
        let reopenedStore = try OpenMusicEventAppViewStore(
            databaseURL: databaseURL,
            webhookSecretProtection: Self.webhookSecretProtection()
        )
        try await withDependencies {
            $0.continuousClock = ContinuousClock()
            $0.date.now = retryAt
            $0.httpClient = .liveValue
            $0.requestInterceptors = []
            $0.responseInterceptors = []
            $0.errorInterceptors = []
            $0.dataForURL = { request, body in
                await retryRequests.record(request, body: body)
                return (Data(), HTTPResponse(status: .ok))
            }
        } operation: {
            let provider = NotificationProviderClient.http(
                configuration: NotificationProviderHTTPConfiguration(
                    fcm: [fcmApplicationID: .init(projectID: "open-music-event")]
                ),
                authorization: NotificationProviderAuthorization(
                    apnsBearerToken: { applicationID in
                        throw NotificationProviderHTTPError.missingAPNSConfiguration(
                            applicationID
                        )
                    },
                    fcmAccessToken: { _ in "fixture-fcm-oauth" }
                )
            )
            let app = try OpenMusicEventAppViewServer.application(
                configuration: AppViewConfiguration(
                    port: 0,
                    notificationDestinationProtection: destinationProtection
                ),
                store: reopenedStore,
                notificationProvider: provider
            )

            try await app.test(.live) { _ in
                try await retryRequests.waitForRequestCount(1)
                try await Self.waitForDeliveredOutboxCount(1, in: reopenedStore.database)
            }
        }

        let failedRequests = await firstRequests.requests
        let retriedRequests = await retryRequests.requests
        let failedRequest = try #require(failedRequests.first)
        let retryRequest = try #require(retriedRequests.first)
        expectNoDifference(failedRequest.request.url, retryRequest.request.url)
        expectNoDifference(failedRequest.body, retryRequest.body)
        expectNoDifference(
            String(decoding: try #require(retryRequest.body), as: UTF8.self),
            #"{"message":{"data":{"kind":"source_available","source":"\#(Self.sourceID.rawValue)","version":"2222222222222222222222222222222222222222"},"fid":"fixture-fcm-installation-id"}}"#
        )
        let ledger = try reopenedStore.database.read { database in
            try Row.fetchOne(
                database,
                sql: """
                    SELECT
                      failedAttempts,
                      deliveredAt,
                      discardedAt,
                      providerStatus,
                      providerCode
                    FROM pushOutbox
                    """
            )
        }
        let ledgerRow = try #require(ledger)
        let failedAttempts: Int = ledgerRow["failedAttempts"]
        let deliveredAt: Date = ledgerRow["deliveredAt"]
        expectNoDifference(failedAttempts, 1)
        expectNoDifference(deliveredAt, retryAt)
        #expect((ledgerRow["discardedAt"] as Date?) == nil)
        expectNoDifference(ledgerRow["providerStatus"] as Int?, 200)
        expectNoDifference(ledgerRow["providerCode"] as String?, nil as String?)
    }

    @Test
    func `invalid and permanent provider failures terminate while a healthy destination delivers`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let destinationProtection = try NotificationDestinationProtection(
            keyData: Data(repeating: 0x3B, count: 32)
        )
        let store = try OpenMusicEventAppViewStore(
            databaseURL: directory.appending(path: "appview.sqlite")
        )
        let applicationID = Push.ApplicationID(rawValue: "fm.woody.openmusicevent")
        let source = NotificationSource(
            id: Self.sourceID,
            version: .init(rawValue: "provider-outcomes")
        )
        let notifications = withDependencies {
            $0.defaultDatabase = store.database
            $0.notificationDestinationProtectionClient = destinationProtection.client(
                legacyAPNSEnvironments: [:]
            )
        } operation: {
            NotificationDatabase()
        }

        // Three active installations subscribe to the same source before delivery begins.
        for fixture in [
            ("invalid-installation", "invalid-fcm-token"),
            ("permanent-installation", "permanent-fcm-token"),
            ("healthy-installation", "healthy-fcm-token"),
        ] {
            let installationID = NotificationInstallation.ID(rawValue: fixture.0)
            try await notifications.insertInstallation(
                NotificationInstallation(id: installationID),
                credentialFingerprint: .init(rawValue: "\(fixture.0)-credential")
            )
            try await notifications.replaceDestination(
                .fcm(
                    Push.FCM(
                        applicationID: applicationID,
                        installationID: .init(rawValue: fixture.1)
                    )
                ),
                for: installationID
            )
            try await notifications.replaceSubscriptions(
                [NotificationSubscription(sourceID: source.id)],
                for: installationID
            )
        }
        let enqueuedCount = try await notifications.enqueue(
            source: source,
            at: Self.receivedAt
        )
        expectNoDifference(enqueuedCount, 3)

        let requests = ProviderHTTPRequestRecorder()
        try await withDependencies {
            $0.continuousClock = ContinuousClock()
            $0.date.now = Self.receivedAt
            $0.httpClient = .liveValue
            $0.requestInterceptors = []
            $0.responseInterceptors = []
            $0.errorInterceptors = []
            $0.dataForURL = { request, body in
                await requests.record(request, body: body)
                let json = String(decoding: body ?? Data(), as: UTF8.self)
                if json.contains("invalid-fcm-token") {
                    return (
                        Data(
                            #"{"error":{"code":404,"message":"Requested entity was not found.","status":"NOT_FOUND","details":[{"@type":"type.googleapis.com/google.firebase.fcm.v1.FcmError","errorCode":"UNREGISTERED"}]}}"#.utf8
                        ),
                        HTTPResponse(status: .notFound)
                    )
                }
                if json.contains("permanent-fcm-token") {
                    return (
                        Data(#"{"error":{"status":"INVALID_ARGUMENT"}}"#.utf8),
                        HTTPResponse(status: .badRequest)
                    )
                }
                return (Data(), HTTPResponse(status: .ok))
            }
        } operation: {
            let provider = NotificationProviderClient.http(
                configuration: NotificationProviderHTTPConfiguration(
                    fcm: [applicationID: .init(projectID: "open-music-event")]
                ),
                authorization: NotificationProviderAuthorization(
                    apnsBearerToken: { applicationID in
                        throw NotificationProviderHTTPError.missingAPNSConfiguration(
                            applicationID
                        )
                    },
                    fcmAccessToken: { _ in "fixture-fcm-oauth" }
                )
            )
            let app = try OpenMusicEventAppViewServer.application(
                configuration: AppViewConfiguration(
                    port: 0,
                    notificationDestinationProtection: destinationProtection
                ),
                store: store,
                notificationProvider: provider
            )

            try await app.test(.live) { _ in
                try await requests.waitForRequestCount(3)
                try await Self.waitForDeliveredOutboxCount(1, in: store.database)
                try await Self.waitForDiscardedOutboxCount(2, in: store.database)
            }
        }

        // The bad token is removed, but every installation and subscription remains durable.
        let persisted = try store.database.read { database in
            (
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM pushInstallations"),
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM pushRegistrations"),
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM pushSubscriptions"),
                try Row.fetchAll(
                    database,
                    sql: """
                        SELECT
                          installationID,
                          failedAttempts,
                          deliveredAt,
                          discardedAt,
                          discardReason,
                          providerStatus,
                          providerCode
                        FROM pushOutbox
                        """
                )
            )
        }
        expectNoDifference(persisted.0, 3)
        expectNoDifference(persisted.1, 2)
        expectNoDifference(persisted.2, 3)

        let rows = Dictionary(
            uniqueKeysWithValues: persisted.3.map { row in
                (row["installationID"] as String, row)
            }
        )
        let invalid = try #require(rows["invalid-installation"])
        #expect((invalid["deliveredAt"] as Date?) == nil)
        expectNoDifference(invalid["discardedAt"] as Date?, Self.receivedAt)
        expectNoDifference(
            invalid["discardReason"] as String?,
            NotificationDeliveryDiscardReason.invalidDestination.rawValue
        )
        expectNoDifference(invalid["providerStatus"] as Int?, 404)
        expectNoDifference(invalid["providerCode"] as String?, "UNREGISTERED")

        let permanent = try #require(rows["permanent-installation"])
        expectNoDifference(permanent["failedAttempts"] as Int, 1)
        #expect((permanent["deliveredAt"] as Date?) == nil)
        expectNoDifference(permanent["discardedAt"] as Date?, Self.receivedAt)
        expectNoDifference(
            permanent["discardReason"] as String?,
            NotificationDeliveryDiscardReason.permanentFailure.rawValue
        )
        expectNoDifference(permanent["providerStatus"] as Int?, 400)
        expectNoDifference(permanent["providerCode"] as String?, "INVALID_ARGUMENT")

        let healthy = try #require(rows["healthy-installation"])
        expectNoDifference(healthy["failedAttempts"] as Int, 0)
        expectNoDifference(healthy["deliveredAt"] as Date?, Self.receivedAt)
        #expect((healthy["discardedAt"] as Date?) == nil)
        expectNoDifference(healthy["providerStatus"] as Int?, 200)
        expectNoDifference(healthy["providerCode"] as String?, nil as String?)
    }

    @Test
    func `retry exhaustion terminates after eight attempts or twenty-four hours`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let destinationProtection = try NotificationDestinationProtection(
            keyData: Data(repeating: 0x3B, count: 32)
        )
        let store = try OpenMusicEventAppViewStore(
            databaseURL: directory.appending(path: "appview.sqlite")
        )
        let applicationID = Push.ApplicationID(rawValue: "fm.woody.openmusicevent")
        let notifications = withDependencies {
            $0.defaultDatabase = store.database
            $0.notificationDestinationProtectionClient = destinationProtection.client(
                legacyAPNSEnvironments: [:]
            )
        } operation: {
            NotificationDatabase()
        }
        let eightAttempts = NotificationSource(
            id: .init(rawValue: "eight-attempts"),
            version: .init(rawValue: "eight-attempts")
        )
        let twentyFourHours = NotificationSource(
            id: .init(rawValue: "twenty-four-hours"),
            version: .init(rawValue: "twenty-four-hours")
        )

        for fixture in [
            ("eight-attempts", eightAttempts),
            ("twenty-four-hours", twentyFourHours),
        ] {
            let installationID = NotificationInstallation.ID(rawValue: fixture.0)
            try await notifications.insertInstallation(
                NotificationInstallation(id: installationID),
                credentialFingerprint: .init(rawValue: "\(fixture.0)-credential")
            )
            try await notifications.replaceDestination(
                .fcm(
                    Push.FCM(
                        applicationID: applicationID,
                        installationID: .init(rawValue: "\(fixture.0)-fcm-token")
                    )
                ),
                for: installationID
            )
            try await notifications.replaceSubscriptions(
                [NotificationSubscription(sourceID: fixture.1.id)],
                for: installationID
            )
        }

        _ = try await notifications.enqueue(source: eightAttempts, at: Self.receivedAt)
        _ = try await notifications.enqueue(
            source: twentyFourHours,
            at: Self.receivedAt.addingTimeInterval(-(24 * 60 * 60) + 5)
        )
        try await store.database.write { database in
            try database.execute(
                sql: "UPDATE pushOutbox SET failedAttempts = 7 WHERE sourceID = ?",
                arguments: [eightAttempts.id.rawValue]
            )
        }

        let requests = ProviderHTTPRequestRecorder()
        try await withDependencies {
            $0.continuousClock = ContinuousClock()
            $0.date.now = Self.receivedAt
            $0.httpClient = .liveValue
            $0.requestInterceptors = []
            $0.responseInterceptors = []
            $0.errorInterceptors = []
            $0.dataForURL = { request, body in
                await requests.record(request, body: body)
                return (
                    Data(#"{"error":{"status":"UNAVAILABLE"}}"#.utf8),
                    HTTPResponse(status: .serviceUnavailable)
                )
            }
        } operation: {
            let provider = NotificationProviderClient.http(
                configuration: NotificationProviderHTTPConfiguration(
                    fcm: [applicationID: .init(projectID: "open-music-event")]
                ),
                authorization: NotificationProviderAuthorization(
                    apnsBearerToken: { applicationID in
                        throw NotificationProviderHTTPError.missingAPNSConfiguration(
                            applicationID
                        )
                    },
                    fcmAccessToken: { _ in "fixture-fcm-oauth" }
                )
            )
            let app = try OpenMusicEventAppViewServer.application(
                configuration: AppViewConfiguration(
                    port: 0,
                    notificationDestinationProtection: destinationProtection
                ),
                store: store,
                notificationProvider: provider
            )

            try await app.test(.live) { _ in
                try await requests.waitForRequestCount(2)
                try await Self.waitForDiscardedOutboxCount(2, in: store.database)
            }
        }

        let persisted = try store.database.read { database in
            try Row.fetchAll(
                database,
                sql: """
                    SELECT
                      sourceID,
                      failedAttempts,
                      deliveredAt,
                      discardedAt,
                      discardReason,
                      providerStatus,
                      providerCode
                    FROM pushOutbox
                    """
            )
        }
        let rows = Dictionary(
            uniqueKeysWithValues: persisted.map { row in
                (row["sourceID"] as String, row)
            }
        )

        let attempts = try #require(rows[eightAttempts.id.rawValue])
        expectNoDifference(attempts["failedAttempts"] as Int, 8)
        #expect((attempts["deliveredAt"] as Date?) == nil)
        expectNoDifference(attempts["discardedAt"] as Date?, Self.receivedAt)
        expectNoDifference(
            attempts["discardReason"] as String?,
            NotificationDeliveryDiscardReason.exhaustedAttempts.rawValue
        )
        expectNoDifference(attempts["providerStatus"] as Int?, 503)
        expectNoDifference(attempts["providerCode"] as String?, "UNAVAILABLE")

        let age = try #require(rows[twentyFourHours.id.rawValue])
        expectNoDifference(age["failedAttempts"] as Int, 1)
        #expect((age["deliveredAt"] as Date?) == nil)
        expectNoDifference(age["discardedAt"] as Date?, Self.receivedAt)
        expectNoDifference(
            age["discardReason"] as String?,
            NotificationDeliveryDiscardReason.exhaustedAge.rawValue
        )
        expectNoDifference(age["providerStatus"] as Int?, 503)
        expectNoDifference(age["providerCode"] as String?, "UNAVAILABLE")
    }

    @Test
    func `unverified or unrelated deliveries never enter the inbox`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databaseURL = directory.appending(path: "appview.sqlite")
        let store = try OpenMusicEventAppViewStore(
            databaseURL: databaseURL,
            webhookSecretProtection: Self.webhookSecretProtection()
        )
        try await store.replaceWebhookSecret(
            Self.secret,
            source: .tangled,
            watchID: Self.watchID
        )
        let app = try withDependencies {
            $0.date.now = Self.receivedAt
        } operation: {
            try OpenMusicEventAppViewServer.application(
                configuration: AppViewConfiguration(
                    port: 0,
                    tangledWebhook: Self.webhookConfiguration()
                ),
                store: store,
                tangledSourceUpdateProcessor: TangledSourceUpdateProcessor { _ in }
            )
        }
        let authenticPayload = Self.pushPayload()

        try await app.test(.router) { client in
            let tamperedPayload = Self.pushPayload(
                after: "3333333333333333333333333333333333333333"
            )
            try await client.execute(
                uri: TangledWebhookEndpoint.path,
                method: .post,
                headers: Self.headers(authenticating: authenticPayload),
                body: ByteBuffer(data: tamperedPayload)
            ) { response in
                #expect(response.status == .unauthorized)
            }

            let unrelatedPayload = Self.pushPayload(
                repositoryFullName: "did:plc:anotherfestival/another-workspace"
            )
            try await client.execute(
                uri: TangledWebhookEndpoint.path,
                method: .post,
                headers: Self.headers(
                    authenticating: unrelatedPayload,
                    repository: "did:plc:anotherfestival/another-workspace"
                ),
                body: ByteBuffer(data: unrelatedPayload)
            ) { response in
                #expect(response.status == .badRequest)
            }

            let unrelatedRefPayload = Self.pushPayload(ref: "refs/heads/preview")
            try await client.execute(
                uri: TangledWebhookEndpoint.path,
                method: .post,
                headers: Self.headers(authenticating: unrelatedRefPayload),
                body: ByteBuffer(data: unrelatedRefPayload)
            ) { response in
                #expect(response.status == .badRequest)
            }
        }

        let persisted = try await Self.persistedInbox(at: databaseURL)
        expectNoDifference(
            persisted,
            PersistedInbox(count: 0, delivery: nil)
        )
    }

    @Test
    func `unavailable webhook protection leaves the delivery retryable`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databaseURL = directory.appending(path: "appview.sqlite")
        let store = try OpenMusicEventAppViewStore(databaseURL: databaseURL)
        let app = try withDependencies {
            $0.date.now = Self.receivedAt
        } operation: {
            try OpenMusicEventAppViewServer.application(
                configuration: AppViewConfiguration(
                    port: 0,
                    tangledWebhook: Self.webhookConfiguration()
                ),
                store: store,
                tangledSourceUpdateProcessor: TangledSourceUpdateProcessor { _ in }
            )
        }
        let payload = Self.pushPayload()

        try await withDependencies {
            $0.date.now = Self.receivedAt
        } operation: {
            try await app.test(.router) { client in
                try await client.execute(
                    uri: TangledWebhookEndpoint.path,
                    method: .post,
                    headers: Self.headers(authenticating: payload),
                    body: ByteBuffer(data: payload)
                ) { response in
                    #expect(response.status == .serviceUnavailable)
                }
            }
        }

        let persisted = try await Self.persistedInbox(at: databaseURL)
        expectNoDifference(persisted, PersistedInbox(count: 0, delivery: nil))
    }

    @Test
    func `Tangled signature matches its HMAC SHA-256 wire contract`() {
        expectNoDifference(
            TangledWebhookSignature.value(
                authenticating: Data("payload".utf8),
                secret: Data("secret".utf8)
            ),
            "sha256=b82fcb791acec57859b989b430a826488ce2e479fdf92326bd0a2e8375a42ba4"
        )
    }
}

private extension TangledWebhookInboxTests {
    static let repositoryDID = "did:plc:5df2u7ief6m6tn77jznicxob"
    static let repositoryKey = "ome-workspace"
    static let repositoryFullName = "\(repositoryDID)/\(repositoryKey)"
    static let canonicalOrganizerID = "did:plc:wickedwoods"
    static let canonicalRepositoryRecordKey = "wicked-woods-source"
    static let watchID = WebhookInboxDelivery.WatchID(
        rawValue: "wickedwoods.ca/ome-workspace#refs/heads/main"
    )
    static let sourceID = NotificationSource.ID(
        rawValue: "at://did:plc:wickedwoods/app.openmusicevent.event/2026"
    )
    static let hookID: Int64 = 42
    static let deliveryID = "d8c7e4a5-48ad-4698-9a95-daee25f36701"
    static let secret = Data("fixture-webhook-secret".utf8)
    static let protectionKey = Data(repeating: 0x2A, count: 32)
    static let receivedAt = Date(timeIntervalSince1970: 1_786_291_200)
    static let fixtureAPNSPrivateKey = """
        -----BEGIN PRIVATE KEY-----
        MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgEGyTvWE/fARuNzwP
        jtjWV+YYelL6/PYZHNvD9LTSB/qhRANCAATZotYl3SYD4sy5kDC919aeH5rBFXaC
        NB10Nw/hVyIkTbgYJ0XiGshcDw3XWUYhqLyrHJpvfWoKDHjiXjzDAuc5
        -----END PRIVATE KEY-----
        """
    static let fixtureFCMPrivateKey = """
        -----BEGIN PRIVATE KEY-----
        MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQDL8W1D9w5zHpmD
        JqpTngIRJ+Sm21e42cRnTudhdejzKUiJQWkHSvQV5yC/+0iEXUsUJYEdSyrKhJFD
        PT+IFGdjIiwb7IX+rUreWXlD/YYBL3/byMG4kYoO4oiPp2A+WvfeyLpuN549OXhk
        7o5kXEZjKfjHTfmnAbCMoYW5BEpiHQC3HAeJZ5EiwAn8HZn5UY6lxJcf7H9hR83x
        D0W7IZTNyxUu4aLNuihFIxJKgP/L/y95Y6ddZsyyHQopM43/7JOYBwufa07MWaxi
        AdBdq1bR/ZeOt2aZaXhV+J6QUoUO8Z6fG6b2cQmvMgk4ybqoeciLII0DfFsyqavu
        ip4hRr59AgMBAAECggEAUIw994XwMw922hG/W98gOd5jtHMVJnD73UGQqTGEm+VG
        PM+Ux8iWtr/ec3Svo3elW4OkhwlVET9ikAf0u64zVzf769ty4K9YzpDQEEZlUrqL
        6SZVPKxetppKDVKx9G7BT0BAQZ+947h7EIIXwxOeyTOeijkFzSwhqqlwwy4qoqzV
        FTQS20QHE62hxzwuS5HBqw8ds183qAg9NbzR0Cp4za9qTiBB6C8KEcLqeatO+q+d
        VCDsJcAMZOvW14N6BozKgbQ/WXZQ/3kNUPBndZLzzqaILFNmB1Zf2DVVJ9gU7+EK
        xOac60StIfG81NllCTBrmRVq8yitNqwmutHMlxrIkQKBgQDvp39MkEHtNunFGkI5
        R8IB5BZjtx5OdRBKkmPasmNU8U0XoQAJUKY/9piIpCtRi87tMXv8WWmlbULi66pu
        4BnMIisw78xlIWRZTSizFrkFcEoVgEnbZBtSrOg/J5PAcjLEGCQoAdmMXAekR2/m
        htv7FPijHPNUjyIFLaxwjl9izwKBgQDZ2mQeKNRHjIb5ZBzB0ZCvUy2y4+kaLrhZ
        +CWMN1flL4dd1KuZKvCEfHY9kWOjqw6XneN4yT0aPmbBft4fihiiNW0Sm8i+fSpy
        g0klw2HJl49wnwctBpRgTdMKGo9n14OGeu0xKOAy7I4j1tKrUXiRWnP9R583Ti7c
        w7YHgdHM8wKBgEV147SaPzF08A6bzMPzY2zO4hpmsdcFoQIsKdryR04QXkrR9EO+
        52C0pYM9Kf0Jq6Ed7ZS3iaJT58YDjjNyqqd648/cQP6yzfYAIiK+HERSRnay5zU6
        b5zn1qyvWOi3cLVbVedumdJPvjtEJU/ImKvOaT5FntVMYwzjLw60hTsLAoGAZJnt
        UeAY51GFovUQMpDL96q5l7qXknewuhtVe4KzHCrun+3tsDWcDBJNp/DTymjbvDg1
        KzoC9XOLkB8+A+KJrZ5uWAGImi7Cw07NIJsxNR7AJonJjolTS4Wkxy2su49SNW/e
        yKzPm7SRjwtNDb/5pWXX2kaQx8Fa8qeOD7lrYPECgYAwQ6o0vYmr+L1tOZZgMVv9
        Jusa8beVUH5hyduJjmxbYOtFTkggAozdx7rs4BgyRsmDlV48cEmcVf/7IH4gMJLb
        O+bbERwCYUChe+piANhnwfwDHzbRd8mmQus54P06X7bWu6Rmi7gbQGVN/Z6VhbIm
        D2cOo0w4bk/3yb01xz1MEw==
        -----END PRIVATE KEY-----
        """

    static func decodedAPNSProviderToken(_ token: String) throws -> DecodedAPNSProviderToken {
        let header = try decodedProviderTokenSegment(token, index: 0)
        let payload = try decodedProviderTokenSegment(token, index: 1)
        return try DecodedAPNSProviderToken(
            algorithm: #require(header["alg"] as? String),
            issuedAt: #require((payload["iat"] as? NSNumber)?.int64Value),
            issuer: #require(payload["iss"] as? String),
            keyID: #require(header["kid"] as? String),
            type: #require(header["typ"] as? String)
        )
    }

    static func decodedFCMServiceAccountAssertion(
        _ token: String
    ) throws -> DecodedFCMServiceAccountAssertion {
        let header = try decodedProviderTokenSegment(token, index: 0)
        let payload = try decodedProviderTokenSegment(token, index: 1)
        return try DecodedFCMServiceAccountAssertion(
            algorithm: #require(header["alg"] as? String),
            audience: #require(payload["aud"] as? String),
            expiration: #require((payload["exp"] as? NSNumber)?.int64Value),
            issuedAt: #require((payload["iat"] as? NSNumber)?.int64Value),
            issuer: #require(payload["iss"] as? String),
            keyID: #require(header["kid"] as? String),
            scope: #require(payload["scope"] as? String),
            type: #require(header["typ"] as? String)
        )
    }

    static func decodedForm(_ data: Data) throws -> [String: String] {
        var components = URLComponents()
        components.percentEncodedQuery = String(decoding: data, as: UTF8.self)
        return try Dictionary(
            uniqueKeysWithValues: #require(components.queryItems).map {
                ($0.name, try #require($0.value))
            }
        )
    }

    static func decodedProviderTokenSegment(
        _ token: String,
        index: Int
    ) throws -> [String: Any] {
        let segments = token.split(separator: ".")
        guard segments.indices.contains(index) else {
            throw DecodedProviderTokenError.missingSegment(index)
        }
        var value = String(segments[index])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        let object = try JSONSerialization.jsonObject(
            with: #require(Data(base64Encoded: value))
        )
        return try #require(object as? [String: Any])
    }

    static func webhookSecretProtection() throws -> WebhookSecretProtection {
        try WebhookSecretProtection(keyData: protectionKey)
    }

    static func notificationOutbox(
        store: OpenMusicEventAppViewStore
    ) -> TangledSourceUpdateProcessor {
        withDependencies {
            $0.defaultDatabase = store.database
        } operation: {
            let database = NotificationDatabase()
            return TangledSourceUpdateProcessor { update in
                try await database.enqueue(
                    source: NotificationSource(
                        id: sourceID,
                        version: .init(rawValue: update.after)
                    ),
                    at: update.receivedAt
                )
            }
        }
    }

    static func watch() throws -> TangledWebhookWatch {
        TangledWebhookWatch(
            repository: repository,
            hookID: hookID,
            repositoryOwnerDID: try #require(DID(repositoryDID)),
            ref: "refs/heads/main",
            canonicalSource: CanonicalTangledSource(
                organizerID: try #require(OME.Organizer.ID(canonicalOrganizerID)),
                repositoryRecordKey: .init(rawValue: canonicalRepositoryRecordKey)
            )
        )
    }

    static let repository = TangledRepositoryReference(
        host: "tangled.org",
        owner: "wickedwoods.ca",
        repository: "ome-workspace"
    )

    static func webhookConfiguration() throws -> TangledWebhookConfiguration {
        try TangledWebhookConfiguration(watches: [try watch()])
    }

    static func pushPayload(
        repositoryFullName: String = repositoryFullName,
        ref: String = "refs/heads/main",
        after: String = "2222222222222222222222222222222222222222"
    ) -> Data {
        let ownerDID = repositoryFullName.split(separator: "/").first.map(String.init) ?? ""
        return Data(
            """
            {
              "ref": "\(ref)",
              "before": "1111111111111111111111111111111111111111",
              "after": "\(after)",
              "repository": {
                "name": "ome-workspace",
                "full_name": "\(repositoryFullName)",
                "description": "Wicked Woods Open Music Event workspace",
                "fork": false,
                "html_url": "https://tangled.org/\(repositoryFullName)",
                "clone_url": "https://tangled.org/\(repositoryFullName)",
                "ssh_url": "git@tangled.org:\(repositoryFullName)",
                "created_at": "2026-08-01T00:00:00Z",
                "updated_at": "2026-08-09T18:00:00Z",
                "owner": { "did": "\(ownerDID)" }
              },
              "pusher": { "did": "\(ownerDID)" }
            }
            """.utf8
        )
    }

    static func headers(
        authenticating payload: Data,
        repository: String = repositoryFullName
    ) -> HTTPFields {
        [
            .contentType: "application/json",
            .init("X-Tangled-Event")!: "push",
            .init("X-Tangled-Hook-ID")!: "\(hookID)",
            .init("X-Tangled-Delivery")!: deliveryID,
            .init("X-Tangled-Repo")!: repository,
            .init("X-Tangled-Signature-256")!: TangledWebhookSignature.value(
                authenticating: payload,
                secret: secret
            ),
        ]
    }

    static func persistedInbox(at databaseURL: URL) async throws -> PersistedInbox {
        let database = try DatabasePool(path: databaseURL.path(percentEncoded: false))
        return try await database.read { database in
            let count = try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM webhookInboxDeliveries"
            ) ?? 0
            let row = try Row.fetchOne(
                database,
                sql: """
                    SELECT source, watchID, deliveryID, event, payload, receivedAt
                    FROM webhookInboxDeliveries
                    """
            )
            let delivery = row.map { row in
                PersistedDelivery(
                    source: row["source"],
                    watchID: row["watchID"],
                    deliveryID: row["deliveryID"],
                    event: row["event"],
                    payload: row["payload"],
                    receivedAt: row["receivedAt"]
                )
            }
            return PersistedInbox(count: count, delivery: delivery)
        }
    }

    static func waitForDeliveredOutboxCount(
        _ expectedCount: Int,
        in database: any DatabaseWriter
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while clock.now < deadline {
            let count = try await database.read { database in
                try Int.fetchOne(
                    database,
                    sql: "SELECT COUNT(*) FROM pushOutbox WHERE deliveredAt IS NOT NULL"
                ) ?? 0
            }
            if count == expectedCount { return }
            try await clock.sleep(for: .milliseconds(10))
        }
        let actualCount = try await database.read { database in
            try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM pushOutbox WHERE deliveredAt IS NOT NULL"
            ) ?? 0
        }
        throw ProviderHarnessTimeout(
            condition: "delivered outbox rows",
            expectedCount: expectedCount,
            actualCount: actualCount
        )
    }

    static func waitForFailedOutboxCount(
        _ expectedCount: Int,
        in database: any DatabaseWriter
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while clock.now < deadline {
            let count = try await database.read { database in
                try Int.fetchOne(
                    database,
                    sql: "SELECT COUNT(*) FROM pushOutbox WHERE failedAttempts > 0"
                ) ?? 0
            }
            if count == expectedCount { return }
            try await clock.sleep(for: .milliseconds(10))
        }
        let actualCount = try await database.read { database in
            try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM pushOutbox WHERE failedAttempts > 0"
            ) ?? 0
        }
        throw ProviderHarnessTimeout(
            condition: "failed outbox rows",
            expectedCount: expectedCount,
            actualCount: actualCount
        )
    }

    static func waitForDiscardedOutboxCount(
        _ expectedCount: Int,
        in database: any DatabaseWriter
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while clock.now < deadline {
            let count = try await database.read { database in
                try Int.fetchOne(
                    database,
                    sql: "SELECT COUNT(*) FROM pushOutbox WHERE discardedAt IS NOT NULL"
                ) ?? 0
            }
            if count == expectedCount { return }
            try await clock.sleep(for: .milliseconds(10))
        }
        let actualCount = try await database.read { database in
            try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM pushOutbox WHERE discardedAt IS NOT NULL"
            ) ?? 0
        }
        throw ProviderHarnessTimeout(
            condition: "discarded outbox rows",
            expectedCount: expectedCount,
            actualCount: actualCount
        )
    }
}

private struct PersistedInbox: Equatable, Sendable {
    var count: Int
    var delivery: PersistedDelivery?
}

private struct PersistedDelivery: Equatable, Sendable {
    var source: String
    var watchID: String
    var deliveryID: String
    var event: String
    var payload: Data
    var receivedAt: Date
}

private struct DecodedAPNSProviderToken: Equatable {
    var algorithm: String
    var issuedAt: Int64
    var issuer: String
    var keyID: String
    var type: String
}

private struct DecodedFCMServiceAccountAssertion: Equatable {
    var algorithm: String
    var audience: String
    var expiration: Int64
    var issuedAt: Int64
    var issuer: String
    var keyID: String
    var scope: String
    var type: String
}

private enum DecodedProviderTokenError: Error {
    case missingSegment(Int)
}

private actor FailOnceSourceUpdateProcessor {
    private(set) var attemptCount = 0

    func process(_: TangledSourceUpdate) throws {
        attemptCount += 1
        if attemptCount == 1 {
            throw Failure.firstAttempt
        }
    }

    private enum Failure: Error {
        case firstAttempt
    }
}

private actor ProviderHTTPRequestRecorder {
    struct Request: Sendable {
        var body: Data?
        var request: HTTPRequest
    }

    var requests: [Request] = []
    var responsesReleased = false
    var responseWaiters: [CheckedContinuation<Void, Never>] = []

    func record(_ request: HTTPRequest, body: Data?) {
        requests.append(Request(body: body, request: request))
    }

    func recordAndWaitForRelease(_ request: HTTPRequest, body: Data?) async {
        record(request, body: body)
        guard !responsesReleased else { return }
        await withCheckedContinuation { continuation in
            responseWaiters.append(continuation)
        }
    }

    func releaseProviderResponses() {
        responsesReleased = true
        let waiters = responseWaiters
        responseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func waitForRequestCount(_ count: Int) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while requests.count < count, clock.now < deadline {
            try await clock.sleep(for: .milliseconds(10))
        }
        guard requests.count >= count else {
            throw ProviderHarnessTimeout(
                condition: "provider requests",
                expectedCount: count,
                actualCount: requests.count
            )
        }
    }
}

private struct ProviderHarnessTimeout: Error, Equatable {
    let condition: String
    let expectedCount: Int
    let actualCount: Int
}
