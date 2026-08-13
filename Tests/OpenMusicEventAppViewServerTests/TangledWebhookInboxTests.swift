import ATProto
import ComposableNotifications
import ComposableNotificationsHTTP
import CustomDump
import Dependencies
import Foundation
import GRDB
import Hummingbird
import HummingbirdTesting
import HTTPClient
import HTTPTypes
@testable import OpenMusicEventAppViewServer
import Testing

@Suite(.serialized)
struct TangledWebhookInboxTests {
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
                "repositoryDID": "\(Self.repositoryDID)",
                "repositoryKey": "\(Self.repositoryKey)",
                "ref": "refs/heads/main",
                "sourceID": "\(Self.sourceID.rawValue)"
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
                repositoryDID: try #require(DID(Self.repositoryDID)),
                repositoryKey: ATProto.Record.Key(rawValue: Self.repositoryKey),
                ref: "refs/heads/main",
                before: "1111111111111111111111111111111111111111",
                after: "2222222222222222222222222222222222222222",
                receivedAt: Self.receivedAt,
                source: NotificationSource(
                    id: Self.sourceID,
                    version: .init(rawValue: "2222222222222222222222222222222222222222")
                )
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
    func `configured watch requires its deployment encryption key file`() throws {
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
                "repositoryDID": "\(Self.repositoryDID)",
                "repositoryKey": "\(Self.repositoryKey)",
                "ref": "refs/heads/main",
                "sourceID": "\(Self.sourceID.rawValue)"
              }]
            }
            """.utf8
        )
        .write(to: configurationURL)

        #expect(throws: AppViewConfigurationError.webhookSecretKeyMissing) {
            try AppViewConfiguration.fromEnvironment(
                environment: [
                    "OME_TANGLED_WEBHOOK_CONFIGURATION_PATH": configurationURL
                        .path(percentEncoded: false)
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
                    store: store
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
                    store: reopenedStore
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

        let destinationProtection = try NotificationDestinationProtection(
            keyData: Data(repeating: 0x3B, count: 32)
        )
        let store = try OpenMusicEventAppViewStore(
            databaseURL: directory.appending(path: "appview.sqlite"),
            webhookSecretProtection: Self.webhookSecretProtection()
        )
        let apnsApplicationID = Push.ApplicationID(rawValue: "app.openmusicevent")
        let fcmApplicationID = Push.ApplicationID(rawValue: "fm.woody.openmusicevent")
        let apnsDestination = Push.Destination.apns(
            Push.APNS(
                applicationID: apnsApplicationID,
                deviceToken: .init(rawValue: "fixture-apns-device-token")
            )
        )
        let fcmDestination = Push.Destination.fcm(
            Push.FCM(
                applicationID: fcmApplicationID,
                registrationToken: .init(rawValue: "fixture-fcm-registration-token")
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
                await providerRequests.recordAndWaitForRelease(request, body: body)
                return (Data(), HTTPResponse(status: .ok))
            }
        } operation: {
            let appConfiguration = AppViewConfiguration(
                port: 0,
                apnsNotificationProvider: AppViewAPNSNotificationProviderConfiguration(
                    applicationID: apnsApplicationID,
                    environment: .production,
                    topic: "app.openmusicevent",
                    teamID: "YJRWV8Z7KT",
                    keyID: "ABCDEFGHIJ",
                    privateKeyURL: apnsPrivateKeyURL
                ),
                notificationDestinationProtection: destinationProtection,
                notificationRegistration: AppViewNotificationRegistrationConfiguration(
                    authorization: .anonymous,
                    allowedApplicationIDs: [apnsApplicationID, fcmApplicationID]
                ),
                tangledWebhook: try Self.webhookConfiguration()
            )
            let configuredAPNSProvider = try #require(
                await appConfiguration.notificationProvider()
            )
            let fcmProvider = NotificationProviderClient.http(
                configuration: NotificationProviderHTTPConfiguration(
                    fcm: [
                        fcmApplicationID: .init(projectID: "open-music-event")
                    ]
                ),
                authorization: NotificationProviderAuthorization(
                    apnsBearerToken: { applicationID in
                        throw NotificationProviderHTTPError.missingAPNSConfiguration(applicationID)
                    },
                    fcmAccessToken: { _ in "fixture-fcm-oauth" }
                )
            )
            let provider = NotificationProviderClient { message, destination in
                switch destination {
                case .apns:
                    try await configuredAPNSProvider.send(message, destination)
                case .fcm:
                    try await fcmProvider.send(message, destination)
                }
            }
            let app = try OpenMusicEventAppViewServer.application(
                configuration: appConfiguration,
                store: store,
                notificationProvider: provider
            )

            try await app.test(.live) { client in
                // The iPhone creates an anonymous installation through the public server route.
                let apnsCredential = try await client.execute(
                    uri: NotificationRegistrationEndpoint.installationsPath,
                    method: .post
                ) { response in
                    #expect(response.status == .created)
                    return try JSONDecoder().decode(
                        NotificationInstallationCredentialPayload.self,
                        from: Data(response.body.readableBytesView)
                    ).credential
                }

                // It registers its APNs token and subscribes to the Wicked Woods source.
                try await client.execute(
                    uri: NotificationRegistrationEndpoint.destinationPath,
                    method: .put,
                    headers: [
                        .authorization: "Notification \(apnsCredential.rawValue)",
                        .contentType: "application/json",
                    ],
                    body: ByteBuffer(
                        data: try JSONEncoder().encode(
                            NotificationDestinationPayload(apnsDestination)
                        )
                    )
                ) { response in
                    #expect(response.status == .noContent)
                }
                try await client.execute(
                    uri: NotificationRegistrationEndpoint.subscriptionsPath,
                    method: .put,
                    headers: [
                        .authorization: "Notification \(apnsCredential.rawValue)",
                        .contentType: "application/json",
                    ],
                    body: ByteBuffer(data: try JSONEncoder().encode(subscriptions))
                ) { response in
                    #expect(response.status == .noContent)
                }

                // The Android app independently registers its FCM token for the same source.
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
                            NotificationDestinationPayload(fcmDestination)
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

                // Tangled's signed HTTP delivery only commits the inbox and two outbox jobs.
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

                // Replaying the same verified delivery cannot enqueue a second pair of jobs.
                try await client.execute(
                    uri: TangledWebhookEndpoint.path,
                    method: .post,
                    headers: Self.headers(authenticating: payload),
                    body: ByteBuffer(data: payload)
                ) { response in
                    #expect(response.status == .accepted)
                }

                await providerRequests.releaseProviderResponses()
                await providerRequests.waitForRequestCount(2)
                try await Self.waitForDeliveredOutboxCount(2, in: store.database)
            }
        }

        let requests = await providerRequests.requests
        expectNoDifference(requests.count, 2)
        let outboxCount = try await store.database.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM pushOutbox") ?? 0
        }
        expectNoDifference(outboxCount, 2)
        let apns = try #require(
            requests.first {
                $0.request.url?.absoluteString.hasPrefix("https://api.push.apple.com/") == true
            }
        )
        let fcm = try #require(
            requests.first {
                $0.request.url?.absoluteString.hasPrefix("https://fcm.googleapis.com/") == true
            }
        )

        // APNs receives a background push whose custom keys preserve the opaque source revision.
        expectNoDifference(apns.request.method, .post)
        expectNoDifference(
            apns.request.url?.absoluteString,
            "https://api.push.apple.com/3/device/fixture-apns-device-token"
        )
        let authorization = try #require(apns.request.headerFields[.authorization])
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
        expectNoDifference(apns.request.headerFields[.contentType], "application/json")
        expectNoDifference(apns.request.headerFields[.init("apns-priority")!], "5")
        expectNoDifference(
            apns.request.headerFields[.init("apns-push-type")!],
            "background"
        )
        expectNoDifference(
            apns.request.headerFields[.init("apns-topic")!],
            "app.openmusicevent"
        )
        expectNoDifference(
            String(decoding: try #require(apns.body), as: UTF8.self),
            #"{"aps":{"content-available":1},"kind":"source_available","source":"\#(Self.sourceID.rawValue)","version":"2222222222222222222222222222222222222222"}"#
        )

        // FCM receives the same semantic data as string values in its HTTP v1 message envelope.
        expectNoDifference(fcm.request.method, .post)
        expectNoDifference(
            fcm.request.url?.absoluteString,
            "https://fcm.googleapis.com/v1/projects/open-music-event/messages:send"
        )
        expectNoDifference(fcm.request.headerFields[.authorization], "Bearer fixture-fcm-oauth")
        expectNoDifference(fcm.request.headerFields[.contentType], "application/json")
        expectNoDifference(
            String(decoding: try #require(fcm.body), as: UTF8.self),
            #"{"message":{"data":{"kind":"source_available","source":"\#(Self.sourceID.rawValue)","version":"2222222222222222222222222222222222222222"},"token":"fixture-fcm-registration-token"}}"#
        )
    }

    @Test
    func `a failed provider request is delivered from the same outbox after restart`() async throws {
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
                registrationToken: .init(rawValue: "fixture-fcm-registration-token")
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
                throw ProviderTransportFailure.unavailable
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
                notificationProvider: provider
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
                await firstRequests.waitForRequestCount(1)
                try await Self.waitForFailedOutboxCount(1, in: store.database)
            }
        }

        let retryRequests = ProviderHTTPRequestRecorder()
        let retryAt = Self.receivedAt.addingTimeInterval(1)
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
                await retryRequests.waitForRequestCount(1)
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
            #"{"message":{"data":{"kind":"source_available","source":"\#(Self.sourceID.rawValue)","version":"2222222222222222222222222222222222222222"},"token":"fixture-fcm-registration-token"}}"#
        )
        let ledger = try reopenedStore.database.read { database in
            try Row.fetchOne(
                database,
                sql: "SELECT failedAttempts, deliveredAt FROM pushOutbox"
            )
        }
        let ledgerRow = try #require(ledger)
        let failedAttempts: Int = ledgerRow["failedAttempts"]
        let deliveredAt: Date = ledgerRow["deliveredAt"]
        expectNoDifference(failedAttempts, 1)
        expectNoDifference(deliveredAt, retryAt)
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
                store: store
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
                store: store
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

    static func watch() throws -> TangledWebhookWatch {
        TangledWebhookWatch(
            id: watchID,
            hookID: hookID,
            repositoryDID: try #require(DID(repositoryDID)),
            repositoryKey: ATProto.Record.Key(rawValue: repositoryKey),
            ref: "refs/heads/main",
            sourceID: sourceID
        )
    }

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
        let observation = ValueObservation.tracking { database in
            try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM pushOutbox WHERE deliveredAt IS NOT NULL"
            ) ?? 0
        }
        for try await count in observation.values(
            in: database,
            bufferingPolicy: .bufferingNewest(1)
        ) {
            if count == expectedCount { return }
        }
    }

    static func waitForFailedOutboxCount(
        _ expectedCount: Int,
        in database: any DatabaseWriter
    ) async throws {
        let observation = ValueObservation.tracking { database in
            try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM pushOutbox WHERE failedAttempts > 0"
            ) ?? 0
        }
        for try await count in observation.values(
            in: database,
            bufferingPolicy: .bufferingNewest(1)
        ) {
            if count == expectedCount { return }
        }
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

private enum DecodedProviderTokenError: Error {
    case missingSegment(Int)
}

private enum ProviderTransportFailure: Error {
    case unavailable
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

    var requestCountWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]
    var requests: [Request] = []
    var responsesReleased = false
    var responseWaiters: [CheckedContinuation<Void, Never>] = []

    func record(_ request: HTTPRequest, body: Data?) {
        requests.append(Request(body: body, request: request))
        let readyCounts = requestCountWaiters.keys.filter { requests.count >= $0 }
        for count in readyCounts {
            requestCountWaiters.removeValue(forKey: count)?.forEach { $0.resume() }
        }
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

    func waitForRequestCount(_ count: Int) async {
        guard requests.count < count else { return }
        await withCheckedContinuation { continuation in
            requestCountWaiters[count, default: []].append(continuation)
        }
    }
}
