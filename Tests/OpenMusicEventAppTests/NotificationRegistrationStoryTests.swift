#if os(macOS)
import ATProtoOAuth
import ComposableArchitecture2
import ComposableNotifications
import ComposableNotificationsHTTP
import ComposableNotificationsServer
import CustomDump
import Dependencies
import Foundation
import HTTPClient
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import NIOCore
import OpenMusicEventDatabase
import SQLiteData
import Sharing
import ComposableAtmosphere
import Testing
import ATProto

@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer
@testable import OpenMusicEventAppViewServer

@Suite(.serialized)
struct NotificationRegistrationStoryTests {
    @Test
    func `simulator registrations use the development APNS environment`() throws {
        expectNoDifference(
            try APNSEnvironmentConfiguration.resolve(
                isSimulator: true,
                embeddedProfileData: nil
            ),
            .development
        )
    }

    @Test
    func `development-signed registrations use the development APNS environment`() throws {
        expectNoDifference(
            try APNSEnvironmentConfiguration.resolve(
                isSimulator: false,
                embeddedProfileData: try Self.embeddedProfile(
                    apsEnvironment: "development"
                )
            ),
            .development
        )
    }

    @Test
    func `distribution-signed registrations use the production APNS environment`() throws {
        expectNoDifference(
            try APNSEnvironmentConfiguration.resolve(
                isSimulator: false,
                embeddedProfileData: try Self.embeddedProfile(
                    apsEnvironment: "production"
                )
            ),
            .production
        )
    }

    @Test
    func `Apple-distributed registrations without an embedded profile use production APNS`() throws {
        expectNoDifference(
            try APNSEnvironmentConfiguration.resolve(
                isSimulator: false,
                embeddedProfileData: nil
            ),
            .production
        )
    }

    @Test
    func `malformed embedded provisioning profiles fail closed`() {
        #expect(throws: APNSEnvironmentConfigurationError.invalidProfile) {
            try APNSEnvironmentConfiguration.resolve(
                isSimulator: false,
                embeddedProfileData: Data("not a provisioning profile".utf8)
            )
        }
    }

    @Test
    func `embedded profiles without an APNS environment fail closed`() throws {
        #expect(throws: APNSEnvironmentConfigurationError.missing) {
            try APNSEnvironmentConfiguration.resolve(
                isSimulator: false,
                embeddedProfileData: try Self.embeddedProfile(apsEnvironment: nil)
            )
        }
    }

    @Test
    func `embedded profiles accept only Apple's two APNS environment values`() throws {
        #expect(throws: APNSEnvironmentConfigurationError.invalid("staging")) {
            try APNSEnvironmentConfiguration.resolve(
                isSimulator: false,
                embeddedProfileData: try Self.embeddedProfile(
                    apsEnvironment: "staging"
                )
            )
        }
    }

    static func embeddedProfile(apsEnvironment: String?) throws -> Data {
        var entitlements: [String: Any] = [:]
        entitlements["aps-environment"] = apsEnvironment
        let propertyList = try PropertyListSerialization.data(
            fromPropertyList: ["Entitlements": entitlements],
            format: .xml,
            options: 0
        )
        var profile = Data([0x00, 0xFF])
        profile.append(propertyList)
        profile.append(contentsOf: [0xFF, 0x00])
        return profile
    }

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
        let payload = NotificationDestinationPayload(
            .apns(
                Push.APNS(
                    applicationID: .init(rawValue: "app.openmusicevent"),
                    environment: .development,
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
        let database = try DatabasePool(path: databaseURL.path(percentEncoded: false))
        let counts = try await database.read { database in
            (
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM pushInstallations") ?? 0,
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM pushRegistrations") ?? 0
            )
        }
        expectNoDifference(counts.0, 0)
        expectNoDifference(counts.1, 0)
    }

    @Test @MainActor
    func `canonical event and category registration survive app and server relaunch`() async throws {
        let database = try withDependencies {
            $0.context = .test
            try OME.prepareDependencies(&$0)
        } operation: {
            @Dependency(\.defaultDatabase) var database
            return database
        }
        let eventID = canonicalRouteEventID
        let categoryID = canonicalRouteRecordID(
            "social.ome.category", "3mrdbziccpcae"
        )
        let event = try Event(
            id: eventID,
            name: "Wicked Woods 2026",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: .gmt
        )
        var category = try Social.Category(
            id: categoryID,
            event: eventID,
            name: "Announcements",
            createdAt: "2026-09-01T12:00:00Z"
        )
        category.description = "Official festival updates."
        category.defaultNotificationState = .known(.unsubscribed)
        let categoryRecord = category
        try await database.write { db in
            try Event.insert { event }.execute(db)
            try Social.Category.insert { categoryRecord }.execute(db)
            try InstalledEvent.insert { InstalledEvent(id: eventID) }.execute(db)
        }
        let eventSubscription = NotificationSubscription(
            sourceID: .init(rawValue: eventID.description)
        )
        let categorySubscription = NotificationSubscription(
            sourceID: .init(
                rawValue: AppRoute.event(eventID, .channel(categoryID))
                    .notificationRoute
            )
        )

        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let appViewDatabaseURL = directory.appending(path: "appview.sqlite")
        let destinationProtection = try NotificationDestinationProtection(
            keyData: Data(repeating: 0x2A, count: 32)
        )
        let configuration = AppViewConfiguration(
            port: 0,
            databaseURL: appViewDatabaseURL,
            notificationDestinationProtection: destinationProtection,
            notificationRegistration: AppViewNotificationRegistrationConfiguration(
                authorization: .anonymous,
                allowedApplicationIDs: [.init(rawValue: "app.openmusicevent")]
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
        let requestRecorder = NotificationRequestRecorder()
        let keychainStorage = KeychainStorageClient.inMemory()

        let app = try OpenMusicEventAppViewServer.application(
            configuration: configuration
        )
        try await app.test(.live) { server in
            try await withDependencies {
                $0.context = .test
                $0.date = .constant(Date(timeIntervalSince1970: 0))
                $0.uuid = .incrementing
                $0.httpClient = .liveValue
                $0.keychainStorage = keychainStorage
                OME.prepareDependencies(&$0, database: database)
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
                    let responseBody = Data(response.body.readableBytesView)
                    await requestRecorder.record(
                        request,
                        requestBody: body,
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
                let appStore = await MainActor.run { Store(
                    initialState: OpenMusicEventApp.State(
                        content: OpenMusicEventApplication.State(storage: storage) {
                            OpenMusicEventAppRoot.State(
                                selectedEventIDAtLaunch: eventID
                            )
                        }
                    )
                ) {
                    OpenMusicEventApp(
                        eventTrigger:
                            \OpenMusicEventApplication.State.content.appDelegateEvent,
                        notificationDestinationTrigger:
                            \OpenMusicEventApplication.State.content.notificationDestination,
                        notificationEventTrigger:
                            \OpenMusicEventApplication.State.content.notificationEvent
                    ) {
                        OpenMusicEventApplication(storage: storage) {
                            OpenMusicEventAppRoot()
                        }
                    }
                } }
                let destinationTask = await MainActor.run {
                    appStore.send(.notificationDestination(destination))
                }
                await destinationTask?.value
                try await requestRecorder.waitForRequestCount(3)

                let communications = try await MainActor.run {
                    let root = appStore.scope(\.content).scope(\.content)
                    let mounted = try #require(root.scope(\.destination))
                    let viewer = try #require(mounted.scope(\.eventViewer))
                    return try #require(
                        viewer.scope(\.communicationsViewer)
                    )
                }
                let subscriptionTask = await MainActor.run {
                    communications.send(
                        .notificationStateButtonTapped(categoryID, .subscribed)
                    )
                }
                await subscriptionTask?.value
                try await requestRecorder.waitForRequestCount(4)
                withExtendedLifetime(appStore) {}
            }
        }

        let installationID = try await storedInstallationID(at: appViewDatabaseURL)
        _ = try OpenMusicEventAppViewStore(databaseURL: appViewDatabaseURL)
        let reopenedNotifications = try notificationDatabase(
            at: appViewDatabaseURL,
            protection: destinationProtection
        )
        let reopenedDestination = try await reopenedNotifications.destination(
            for: installationID
        )
        let reopenedSubscriptions = try await reopenedNotifications.subscriptions(
            for: installationID
        )
        expectNoDifference(reopenedDestination, Optional(destination))
        expectNoDifference(reopenedSubscriptions, Set([eventSubscription, categorySubscription]))

        let relaunchedApp = try OpenMusicEventAppViewServer.application(
            configuration: configuration
        )
        try await relaunchedApp.test(.live) { server in
            try await withDependencies {
                $0.context = .test
                $0.date = .constant(Date(timeIntervalSince1970: 0))
                $0.uuid = .incrementing
                $0.httpClient = .liveValue
                $0.keychainStorage = keychainStorage
                OME.prepareDependencies(&$0, database: database)
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
                    let responseBody = Data(response.body.readableBytesView)
                    await requestRecorder.record(
                        request,
                        requestBody: body,
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
                let relaunchedStore = await MainActor.run { Store(
                    initialState: OpenMusicEventApp.State(
                        content: OpenMusicEventApplication.State(storage: storage) {
                            OpenMusicEventAppRoot.State(
                                selectedEventIDAtLaunch: eventID
                            )
                        }
                    )
                ) {
                    OpenMusicEventApp(
                        eventTrigger:
                            \OpenMusicEventApplication.State.content.appDelegateEvent,
                        notificationDestinationTrigger:
                            \OpenMusicEventApplication.State.content.notificationDestination,
                        notificationEventTrigger:
                            \OpenMusicEventApplication.State.content.notificationEvent
                    ) {
                        OpenMusicEventApplication(storage: storage) {
                            OpenMusicEventAppRoot()
                        }
                    }
                } }
                let destinationTask = await MainActor.run {
                    relaunchedStore.send(.notificationDestination(destination))
                }
                await destinationTask?.value
                try await requestRecorder.waitForRequestCount(6)
                withExtendedLifetime(relaunchedStore) {}
            }
        }

        let relaunchedNotifications = try notificationDatabase(
            at: appViewDatabaseURL,
            protection: destinationProtection
        )
        let relaunchedDestination = try await relaunchedNotifications.destination(
            for: installationID
        )
        let relaunchedSubscriptions = try await relaunchedNotifications.subscriptions(
            for: installationID
        )
        expectNoDifference(relaunchedDestination, Optional(destination))
        expectNoDifference(relaunchedSubscriptions, Set([eventSubscription, categorySubscription]))

        let exchanges = await requestRecorder.allExchanges()
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
        let eventOnlyBody = try canonicalJSONString(
            JSONEncoder().encode(
                NotificationSubscriptionsPayload(
                    [eventSubscription]
                )
            )
        )
        let eventAndCategoryBody = try canonicalJSONString(
            JSONEncoder().encode(
                NotificationSubscriptionsPayload(
                    [eventSubscription, categorySubscription]
                )
            )
        )
        expectNoDifference(
            try registrationExchanges.map { exchange in
                try exchange.requestBody.map(canonicalJSONString)
            },
            [
                nil,
                #"{"applicationID":"app.openmusicevent","provider":"fcm","value":"fcm-registration-token-that-must-not-be-rewritten"}"#,
                eventOnlyBody,
                eventAndCategoryBody,
                #"{"applicationID":"app.openmusicevent","provider":"fcm","value":"fcm-registration-token-that-must-not-be-rewritten"}"#,
                eventAndCategoryBody,
            ]
        )
        let credential = try #require(await requestRecorder.bootstrapCredential())
        #expect(registrationExchanges[0].request.headerFields[.authorization] == nil)
        for exchange in registrationExchanges.dropFirst() {
            #expect(
                exchange.request.headerFields[.authorization]
                    == "Notification \(credential.rawValue)"
            )
        }
    }
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
        var requestBody: Data?
        var response: HTTPResponse
        var responseBody: Data
    }

    private var exchanges: [Exchange] = []

    func record(
        _ request: HTTPRequest,
        requestBody: Data?,
        response: HTTPResponse,
        responseBody: Data
    ) {
        exchanges.append(
            Exchange(
                request: request,
                requestBody: requestBody,
                response: response,
                responseBody: responseBody
            )
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

private func canonicalJSONString(_ data: Data) throws -> String {
    let object = try JSONSerialization.jsonObject(with: data)
    let canonicalData = try JSONSerialization.data(
        withJSONObject: object,
        options: [.sortedKeys, .withoutEscapingSlashes]
    )
    return String(decoding: canonicalData, as: UTF8.self)
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

private func notificationDatabase(
    at databaseURL: URL,
    protection: NotificationDestinationProtection
) throws -> NotificationDatabase {
    let database = try DatabasePool(path: databaseURL.path(percentEncoded: false))
    return withDependencies {
        $0.defaultDatabase = database
        $0.notificationDestinationProtectionClient = protection.client
    } operation: {
        NotificationDatabase()
    }
}
#endif
