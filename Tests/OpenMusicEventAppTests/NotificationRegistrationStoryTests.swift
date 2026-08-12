import ATProtoOAuth
import ComposableArchitecture2
import ComposableNotifications
import ComposableNotificationsHTTP
import CustomDump
import Crypto
import Dependencies
import Foundation
import HTTPClient
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import NIOCore
@testable import OpenMusicEventApp
import OpenMusicEventAppViewServer
import OpenMusicEventDatabase
import OpenMusicEventSourceEditing
import Sharing
import SQLiteData
import TCATProtoAuthentication
import Testing
import XRPCClient

@Suite(.serialized)
struct NotificationRegistrationStoryTests {
    @Test @MainActor
    func `registration routes fail closed until runtime services are installed`() async throws {
        let app = try OpenMusicEventAppViewServer.application(
            configuration: AppViewConfiguration(port: 0)
        )

        try await app.test(.router) { client in
            try await client.execute(
                uri: NotificationRegistrationEndpoint.installationsPath,
                method: .post
            ) { response in
                #expect(response.status == .serviceUnavailable)
            }
            try await client.execute(
                uri: NotificationRegistrationEndpoint.destinationPath,
                method: .put
            ) { response in
                #expect(response.status == .serviceUnavailable)
            }
        }
    }

    @Test @MainActor
    func `registration routes reject requests the host cannot authenticate`() async throws {
        let installationStore = InMemoryNotificationInstallationStore()
        let store = InMemoryNotificationRegistrationStore()
        let app = try OpenMusicEventAppViewServer.application(
            configuration: AppViewConfiguration(port: 0),
            notificationRegistration: NotificationRegistrationServer(
                store: store,
                installationAuthorizer: .anonymous(store: installationStore),
                policy: NotificationRegistrationPolicy(
                    allowedApplicationIDs: [.init(rawValue: "app.openmusicevent")]
                )
            )
        )
        let payload = NotificationDestinationPayload(
            .apns(
                Push.APNS(
                    applicationID: .init(rawValue: "app.openmusicevent"),
                    deviceToken: .init(rawValue: "device-token")
                ),
            )
        )

        try await app.test(.router) { client in
            try await client.execute(
                uri: NotificationRegistrationEndpoint.destinationPath,
                method: .put,
                headers: [
                    .authorization: "Notification forged-credential",
                    .contentType: "application/json",
                ],
                body: ByteBuffer(data: try JSONEncoder().encode(payload))
            ) { response in
                #expect(response.status == .unauthorized)
            }
        }

        #expect(await store.destinationCount == 0)
        #expect(await installationStore.installationCount == 0)
    }

    @Test @MainActor
    func `entered event receives an FCM update and survives app and AppView restarts`() async throws {
        let database = try withDependencies {
            $0.context = .test
            try OME.prepareDependencies(&$0)
        } operation: {
            @Dependency(\.defaultDatabase) var database
            return database
        }
        let organizerID = try #require(DID("did:plc:wickedwoods"))
        let eventID = OME.Event.ID(
            organizerID: organizerID,
            eventID: OME.ID<OME.Event>(rawValue: "2026")
        )
        try await database.write { database in
            try OME.Organizer.insert {
                OME.Organizer.Draft(id: organizerID)
            }
            .execute(database)
            try OME.Event.insert {
                testEventDraft(
                    id: eventID,
                    name: "Wicked Woods 2026"
                )
            }
            .execute(database)
            try EventSourceProvenanceRecord.insert {
                EventSourceProvenanceRecord(
                    id: eventID,
                    sourceKind: .tangled,
                    sourceReference: "tangled.org/wickedwoods.ca/ome-workspace",
                    ref: "main",
                    eventIDOrigin: .explicit,
                    sourceEventDirectory: "wicked-woods-2026"
                )
            }
            .execute(database)
        }
        let eventSubscription = NotificationSubscription(
            sourceID: .init(
                rawValue: "at://did:plc:wickedwoods/app.openmusicevent.event/2026"
            )
        )
        let updatedSource = NotificationSource(
            id: eventSubscription.sourceID,
            version: .init(rawValue: "2222222222222222222222222222222222222222")
        )

        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let appViewDatabaseURL = directory.appending(path: "appview.sqlite")
        let destinationProtection = try NotificationDestinationProtection(
            keyData: Data(repeating: 0x2A, count: 32)
        )
        let webhookSecret = Data("fixture-tangled-webhook-secret".utf8)
        let webhookSecretProtection = try WebhookSecretProtection(
            keyData: Data(repeating: 0x3B, count: 32)
        )
        let webhookWatchID = WebhookInboxDelivery.WatchID(
            rawValue: "wickedwoods.ca/ome-workspace#refs/heads/main"
        )
        let webhookHookID: Int64 = 42
        let repositoryKey = ATProto.Record.Key(rawValue: "ome-workspace")
        let configuration = AppViewConfiguration(
            port: 0,
            databaseURL: appViewDatabaseURL,
            notificationDestinationProtection: destinationProtection,
            notificationRegistration: AppViewNotificationRegistrationConfiguration(
                authorization: .anonymous,
                allowedApplicationIDs: [.init(rawValue: "app.openmusicevent")]
            ),
            webhookSecretProtection: webhookSecretProtection,
            tangledWebhook: try TangledWebhookConfiguration(
                watches: [
                    TangledWebhookWatch(
                        id: webhookWatchID,
                        hookID: webhookHookID,
                        repositoryDID: organizerID,
                        repositoryKey: repositoryKey,
                        ref: "refs/heads/main",
                        sourceID: eventSubscription.sourceID
                    )
                ]
            )
        )
        let destination = Push.Destination.fcm(
            Push.FCM(
                applicationID: .init(rawValue: "app.openmusicevent"),
                registrationToken: .init(
                    rawValue: "fcm-registration-token-that-must-not-be-rewritten"
                )
            )
        )
        let tokenClient = NotificationTokenClient {
            AsyncStream { continuation in
                continuation.yield(destination)
                continuation.finish()
            }
        }
        let requestRecorder = NotificationRequestRecorder()
        let keychainStorage = KeychainStorageClient.inMemory()
        let appViewStore = try OpenMusicEventAppViewStore(
            databaseURL: appViewDatabaseURL,
            notificationDestinationProtection: destinationProtection,
            webhookSecretProtection: webhookSecretProtection
        )
        try await appViewStore.replaceWebhookSecret(
            webhookSecret,
            source: .tangled,
            watchID: webhookWatchID
        )
        let fakeFCM = FakeFCMProvider()
        let sourceUpdateProcessor = TangledSourceUpdateProcessor.notifications(
            store: appViewStore,
            provider: NotificationProviderClient { message, destination in
                try await fakeFCM.send(message, to: destination)
            }
        )

        do {
            let app = try OpenMusicEventAppViewServer.application(
                configuration: configuration,
                store: appViewStore,
                tangledSourceUpdateProcessor: sourceUpdateProcessor
            )
            try await app.test(.router) { server in
                try await withDependencies {
                    $0.context = .test
                    $0.date = .constant(Date(timeIntervalSince1970: 0))
                    $0.uuid = .incrementing
                    $0.httpClient = .liveValue
                    $0.keychainStorage = keychainStorage
                    OME.prepareDependencies(&$0, database: database)
                    $0.notificationTokenClient = tokenClient
                    $0[XRPC.Client.self] = .liveValue
                    $0.requestInterceptors = []
                    $0.dataForURL = { request, body in
                        let url = try #require(request.url)
                        let components = try #require(
                            URLComponents(url: url, resolvingAgainstBaseURL: false)
                        )
                        let uri = components.percentEncodedQuery.map {
                            "\(components.percentEncodedPath)?\($0)"
                        } ?? components.percentEncodedPath
                        let response = try await server.execute(
                            uri: uri,
                            method: request.method,
                            headers: request.headerFields,
                            body: body.map { ByteBuffer(data: $0) }
                        )
                        switch request.url?.path {
                        case NotificationRegistrationEndpoint.installationsPath:
                            #expect(response.head.status == .created)
                            #expect(response.head.headerFields[.cacheControl] == "no-store")
                        case NotificationRegistrationEndpoint.destinationPath,
                            NotificationRegistrationEndpoint.subscriptionsPath:
                            #expect(response.head.status == .noContent)
                        default:
                            #expect(response.head.status == .ok)
                        }
                        let responseBody = Data(response.body.readableBytesView)
                        await requestRecorder.record(
                            request,
                            response: response.head,
                            responseBody: responseBody
                        )
                        return (responseBody, response.head)
                    }
                } operation: {
                    let storage = OAuthSessionStorage(
                        sessionStore: Shared(value: OAuth.SessionStore()),
                        authFailureMessage: Shared(value: nil),
                        selectedSessionID: Shared(value: nil)
                    )
                    let appStore = await MainActor.run {
                        Store(
                            initialState: OpenMusicEventApplication.State(storage: storage) {
                                OpenMusicEventAppRoot.State(
                                    selectedEventIDAtLaunch: eventID
                                )
                            }
                        ) {
                            OpenMusicEventApplication(storage: storage) {
                                OpenMusicEventAppRoot()
                            }
                        }
                    }

                    try await requestRecorder.waitForRequestCount(3)
                    let browse = await MainActor.run {
                        appStore
                            .scope(\.content, action: \.content)
                            .scope(\.browser, action: \.browser)
                            .spawn(\.browse)
                    }
                    let browseTask = await MainActor.run {
                        browse.send(.task)
                    }
                    await browseTask?.value
                    try await requestRecorder.waitForRequestCount(4)

                    // Tangled reports the organizer's new source revision to the real webhook.
                    let webhookPayload = tangledPushPayload(
                        repositoryDID: organizerID,
                        repositoryKey: repositoryKey,
                        after: updatedSource.version.rawValue
                    )
                    let webhookResponse = try await server.execute(
                        uri: TangledWebhookEndpoint.path,
                        method: .post,
                        headers: tangledWebhookHeaders(
                            payload: webhookPayload,
                            hookID: webhookHookID,
                            secret: webhookSecret,
                            repositoryDID: organizerID,
                            repositoryKey: repositoryKey
                        ),
                        body: ByteBuffer(data: webhookPayload)
                    )
                    #expect(webhookResponse.head.status == .accepted)
                    try await requestRecorder.waitForRequestCount(5)

                    let providerDeliveries = await fakeFCM.deliveries()
                    expectNoDifference(
                        providerDeliveries,
                        [
                            FakeFCMProvider.Delivery(
                                message: NotificationProviderMessage(
                                    signal: .sourceAvailable(updatedSource)
                                ),
                                destination: destination
                            )
                        ]
                    )
                    withExtendedLifetime(appStore) {}
                }
            }
        }

        let installationID = try await storedInstallationID(at: appViewDatabaseURL)
        let reopenedAppViewStore = try OpenMusicEventAppViewStore(
            databaseURL: appViewDatabaseURL,
            notificationDestinationProtection: destinationProtection
        )
        let reopenedDestination = try await reopenedAppViewStore.notificationDestination(
            for: installationID
        )
        let reopenedSubscriptions = try await reopenedAppViewStore.notificationSubscriptions(
            for: installationID
        )
        expectNoDifference(
            reopenedDestination,
            Optional(destination)
        )
        expectNoDifference(
            reopenedSubscriptions,
            Set([eventSubscription])
        )
        let relaunchedApp = try OpenMusicEventAppViewServer.application(
            configuration: configuration
        )
        try await relaunchedApp.test(.router) { server in
            try await withDependencies {
                $0.context = .test
                $0.date = .constant(Date(timeIntervalSince1970: 0))
                $0.uuid = .incrementing
                $0.httpClient = .liveValue
                $0.keychainStorage = keychainStorage
                OME.prepareDependencies(&$0, database: database)
                $0.notificationTokenClient = tokenClient
                $0[XRPC.Client.self] = .liveValue
                $0.requestInterceptors = []
                $0.dataForURL = { request, body in
                    let url = try #require(request.url)
                    let components = try #require(
                        URLComponents(url: url, resolvingAgainstBaseURL: false)
                    )
                    let uri = components.percentEncodedQuery.map {
                        "\(components.percentEncodedPath)?\($0)"
                    } ?? components.percentEncodedPath
                    let response = try await server.execute(
                        uri: uri,
                        method: request.method,
                        headers: request.headerFields,
                        body: body.map { ByteBuffer(data: $0) }
                    )
                    #expect(response.head.status == .noContent)
                    let responseBody = Data(response.body.readableBytesView)
                    await requestRecorder.record(
                        request,
                        response: response.head,
                        responseBody: responseBody
                    )
                    return (responseBody, response.head)
                }
            } operation: {
                let storage = OAuthSessionStorage(
                    sessionStore: Shared(value: OAuth.SessionStore()),
                    authFailureMessage: Shared(value: nil),
                    selectedSessionID: Shared(value: nil)
                )
                let relaunchedStore = await MainActor.run {
                    Store(
                        initialState: OpenMusicEventApplication.State(storage: storage) {
                            OpenMusicEventAppRoot.State(
                                selectedEventIDAtLaunch: eventID
                            )
                        }
                    ) {
                        OpenMusicEventApplication(storage: storage) {
                            OpenMusicEventAppRoot()
                        }
                    }
                }

                try await requestRecorder.waitForRequestCount(7)
                withExtendedLifetime(relaunchedStore) {}
            }
        }

        let relaunchedStore = try OpenMusicEventAppViewStore(
            databaseURL: appViewDatabaseURL,
            notificationDestinationProtection: destinationProtection
        )
        let relaunchedDestination = try await relaunchedStore.notificationDestination(
            for: installationID
        )
        let relaunchedSubscriptions = try await relaunchedStore.notificationSubscriptions(
            for: installationID
        )
        expectNoDifference(
            relaunchedDestination,
            Optional(destination)
        )
        expectNoDifference(
            relaunchedSubscriptions,
            Set([eventSubscription])
        )

        let exchanges = await requestRecorder.allExchanges()
        let bootstrapCredential = try await requestRecorder.bootstrapCredential()
        let credential = try #require(bootstrapCredential)
        let registrationExchanges = exchanges.filter {
            switch $0.request.url?.path {
            case NotificationRegistrationEndpoint.installationsPath,
                NotificationRegistrationEndpoint.destinationPath,
                NotificationRegistrationEndpoint.subscriptionsPath:
                true
            default:
                false
            }
        }
        let browseExchanges = exchanges.filter {
            $0.request.url?.path == "/xrpc/app.openmusicevent.calendar.getEvents"
        }
        expectNoDifference(
            registrationExchanges.map(NotificationRequestSummary.init),
            [
                NotificationRequestSummary(
                    method: .post,
                    path: NotificationRegistrationEndpoint.installationsPath
                ),
                NotificationRequestSummary(
                    method: .put,
                    path: NotificationRegistrationEndpoint.destinationPath
                ),
                NotificationRequestSummary(
                    method: .put,
                    path: NotificationRegistrationEndpoint.subscriptionsPath
                ),
                NotificationRequestSummary(
                    method: .put,
                    path: NotificationRegistrationEndpoint.destinationPath
                ),
                NotificationRequestSummary(
                    method: .put,
                    path: NotificationRegistrationEndpoint.subscriptionsPath
                ),
            ]
        )
        expectNoDifference(
            registrationExchanges.map { $0.response.status },
            [.created, .noContent, .noContent, .noContent, .noContent]
        )
        expectNoDifference(browseExchanges.count, 2)
        #expect(browseExchanges.allSatisfy { $0.response.status == .ok })
        #expect(registrationExchanges.dropFirst().allSatisfy { $0.responseBody.isEmpty })
        #expect(registrationExchanges[0].request.headerFields[.authorization] == nil)
        for exchange in registrationExchanges.dropFirst() {
            #expect(
                exchange.request.headerFields[.authorization]
                    == "Notification \(credential.rawValue)"
            )
        }
    }
}

private func tangledPushPayload(
    repositoryDID: DID,
    repositoryKey: ATProto.Record.Key,
    after: String
) -> Data {
    Data(
        """
        {
          "ref": "refs/heads/main",
          "before": "1111111111111111111111111111111111111111",
          "after": "\(after)",
          "repository": {
            "name": "\(repositoryKey.rawValue)",
            "full_name": "\(repositoryDID.description)/\(repositoryKey.rawValue)",
            "owner": { "did": "\(repositoryDID.description)" }
          },
          "pusher": { "did": "\(repositoryDID.description)" }
        }
        """.utf8
    )
}

private func tangledWebhookHeaders(
    payload: Data,
    hookID: Int64,
    secret: Data,
    repositoryDID: DID,
    repositoryKey: ATProto.Record.Key
) -> HTTPFields {
    let authenticationCode = HMAC<SHA256>.authenticationCode(
        for: payload,
        using: SymmetricKey(data: secret)
    )
    let signature = "sha256=" + authenticationCode
        .map { String(format: "%02x", $0) }
        .joined()
    return [
        .contentType: "application/json",
        .init("X-Tangled-Event")!: "push",
        .init("X-Tangled-Hook-ID")!: "\(hookID)",
        .init("X-Tangled-Delivery")!: "d8c7e4a5-48ad-4698-9a95-daee25f36701",
        .init("X-Tangled-Repo")!: "\(repositoryDID.description)/\(repositoryKey.rawValue)",
        .init("X-Tangled-Signature-256")!: signature,
    ]
}

private actor FakeFCMProvider {
    struct Delivery: Equatable, Sendable {
        var message: NotificationProviderMessage
        var destination: Push.Destination
    }

    private var recordedDeliveries: [Delivery] = []

    func send(
        _ message: NotificationProviderMessage,
        to destination: Push.Destination
    ) throws {
        guard case .fcm = destination else {
            throw FakeFCMProviderError.unsupportedDestination
        }
        recordedDeliveries.append(
            Delivery(message: message, destination: destination)
        )
        OpenMusicEventAppDelegate.shared.onRemoteNotification(data: message.data)
    }

    func deliveries() -> [Delivery] {
        recordedDeliveries
    }
}

private enum FakeFCMProviderError: Error {
    case unsupportedDestination
}

private struct NotificationRequestSummary: Equatable {
    var method: HTTPRequest.Method
    var path: String?

    init(_ exchange: NotificationRequestRecorder.Exchange) {
        self.init(
            method: exchange.request.method,
            path: exchange.request.url?.path
        )
    }

    init(method: HTTPRequest.Method, path: String?) {
        self.method = method
        self.path = path
    }
}

private actor NotificationRequestRecorder {
    struct Exchange: Sendable {
        var request: HTTPRequest
        var response: HTTPResponse
        var responseBody: Data
    }

    private var exchanges: [Exchange] = []

    func record(
        _ request: HTTPRequest,
        response: HTTPResponse,
        responseBody: Data
    ) {
        exchanges.append(
            Exchange(request: request, response: response, responseBody: responseBody)
        )
    }

    func waitForRequestCount(_ count: Int) async throws {
        for _ in 0..<500 {
            guard exchanges.count < count else { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw NotificationRequestRecorderError.timedOut(
            expectedRequestCount: count,
            actualRequestCount: exchanges.count
        )
    }

    func allExchanges() -> [Exchange] {
        exchanges
    }

    func bootstrapCredential() throws -> NotificationInstallation.Credential? {
        guard let exchange = exchanges.first(where: {
            $0.request.url?.path == NotificationRegistrationEndpoint.installationsPath
        }) else { return nil }
        return try JSONDecoder().decode(
            NotificationInstallationCredentialPayload.self,
            from: exchange.responseBody
        )
        .credential
    }
}

private enum NotificationRequestRecorderError: Error, Equatable {
    case timedOut(expectedRequestCount: Int, actualRequestCount: Int)
}

private func storedInstallationID(
    at databaseURL: URL
) async throws -> NotificationInstallation.ID {
    let database = try DatabasePool(path: databaseURL.path(percentEncoded: false))
    let rawValue = try await database.read { database in
        let storedID = try String.fetchOne(
            database,
            sql: "SELECT id FROM pushInstallations LIMIT 1"
        )
        return try #require(storedID)
    }
    return NotificationInstallation.ID(rawValue: rawValue)
}

private actor InMemoryNotificationInstallationStore: NotificationInstallationStore {
    private var installationIDsByCredentialFingerprint: [
        NotificationInstallation.CredentialFingerprint: NotificationInstallation.ID
    ] = [:]

    var installationCount: Int {
        installationIDsByCredentialFingerprint.count
    }

    func insertInstallation(
        _ installation: NotificationInstallation,
        credentialFingerprint: NotificationInstallation.CredentialFingerprint
    ) async throws {
        installationIDsByCredentialFingerprint[credentialFingerprint] = installation.id
    }

    func installationID(
        for credentialFingerprint: NotificationInstallation.CredentialFingerprint
    ) async throws -> NotificationInstallation.ID? {
        installationIDsByCredentialFingerprint[credentialFingerprint]
    }
}

private actor InMemoryNotificationRegistrationStore: NotificationRegistrationStore {
    private var destinationsByInstallation: [
        NotificationInstallation.ID: Push.Destination
    ] = [:]
    private var subscriptionsByInstallation: [
        NotificationInstallation.ID: Set<NotificationSubscription>
    ] = [:]

    var destinationCount: Int {
        destinationsByInstallation.count
    }

    func replaceDestination(
        _ destination: Push.Destination,
        for installationID: NotificationInstallation.ID
    ) {
        destinationsByInstallation[installationID] = destination
    }

    func replaceSubscriptions(
        _ subscriptions: Set<NotificationSubscription>,
        for installationID: NotificationInstallation.ID
    ) {
        subscriptionsByInstallation[installationID] = subscriptions
    }
}
