import ATProto
import ComposableNotifications
import ComposableNotificationsHTTP
import CustomDump
import Dependencies
import Foundation
import GRDB
import Hummingbird
import HummingbirdTesting
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
    func `a verified source update fans out exact APNs and FCM JSON`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let destinationProtection = try NotificationDestinationProtection(
            keyData: Data(repeating: 0x3B, count: 32)
        )
        let store = try OpenMusicEventAppViewStore(
            databaseURL: directory.appending(path: "appview.sqlite"),
            notificationDestinationProtection: destinationProtection,
            webhookSecretProtection: Self.webhookSecretProtection()
        )
        let applicationID = Push.ApplicationID(rawValue: "fm.woody.openmusicevent")
        let apnsDestination = Push.Destination.apns(
            Push.APNS(
                applicationID: applicationID,
                deviceToken: .init(rawValue: "fixture-apns-device-token")
            )
        )
        let fcmDestination = Push.Destination.fcm(
            Push.FCM(
                applicationID: applicationID,
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
        // the real signed webhook route, SQLite inbox and subscription lookup, dispatcher, provider
        // selection, and provider JSON encoder before it reaches this raw-network closure.
        try await withDependencies {
            $0.date.now = Self.receivedAt
        } operation: {
            let provider = NotificationProviderClient.http(
                configuration: NotificationProviderHTTPConfiguration(
                    apns: [
                        applicationID: .init(
                            environment: .production,
                            topic: "fm.woody.openmusicevent"
                        )
                    ],
                    fcm: [
                        applicationID: .init(projectID: "open-music-event")
                    ]
                ),
                authorization: NotificationProviderAuthorization(
                    apnsBearerToken: { _ in "fixture-apns-jwt" },
                    fcmAccessToken: { _ in "fixture-fcm-oauth" }
                ),
                transport: NotificationProviderHTTPTransport { request in
                    await providerRequests.record(request)
                }
            )
            let app = try OpenMusicEventAppViewServer.application(
                configuration: AppViewConfiguration(
                    port: 0,
                    notificationRegistration: AppViewNotificationRegistrationConfiguration(
                        authorization: .anonymous,
                        allowedApplicationIDs: [applicationID]
                    ),
                    tangledWebhook: Self.webhookConfiguration()
                ),
                store: store,
                notificationProvider: provider
            )

            try await app.test(.router) { client in
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

                // Tangled's signed HTTP delivery is the trigger. No source-update processor,
                // notification store, dispatcher, or provider client is called directly.
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

        let requests = await providerRequests.requests
        expectNoDifference(requests.count, 2)
        let apns = try #require(
            requests.first {
                $0.url.absoluteString.hasPrefix("https://api.push.apple.com/")
            }
        )
        let fcm = try #require(
            requests.first {
                $0.url.absoluteString.hasPrefix("https://fcm.googleapis.com/")
            }
        )

        // APNs receives a background push whose custom keys preserve the opaque source revision.
        expectNoDifference(apns.method, .post)
        expectNoDifference(
            apns.url.absoluteString,
            "https://api.push.apple.com/3/device/fixture-apns-device-token"
        )
        expectNoDifference(apns.headerFields["Authorization"], "bearer fixture-apns-jwt")
        expectNoDifference(apns.headerFields["Content-Type"], "application/json")
        expectNoDifference(apns.headerFields["apns-priority"], "5")
        expectNoDifference(
            apns.headerFields["apns-push-type"],
            "background"
        )
        expectNoDifference(
            apns.headerFields["apns-topic"],
            "fm.woody.openmusicevent"
        )
        expectNoDifference(
            String(decoding: apns.body, as: UTF8.self),
            #"{"aps":{"content-available":1},"kind":"source_available","source":"\#(Self.sourceID.rawValue)","version":"2222222222222222222222222222222222222222"}"#
        )

        // FCM receives the same semantic data as string values in its HTTP v1 message envelope.
        expectNoDifference(fcm.method, .post)
        expectNoDifference(
            fcm.url.absoluteString,
            "https://fcm.googleapis.com/v1/projects/open-music-event/messages:send"
        )
        expectNoDifference(fcm.headerFields["Authorization"], "Bearer fixture-fcm-oauth")
        expectNoDifference(fcm.headerFields["Content-Type"], "application/json")
        expectNoDifference(
            String(decoding: fcm.body, as: UTF8.self),
            #"{"message":{"data":{"kind":"source_available","source":"\#(Self.sourceID.rawValue)","version":"2222222222222222222222222222222222222222"},"token":"fixture-fcm-registration-token"}}"#
        )
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

private actor ProviderHTTPRequestRecorder {
    var requests: [NotificationProviderHTTPRequest] = []

    func record(_ request: NotificationProviderHTTPRequest) {
        requests.append(request)
    }
}
