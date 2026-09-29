#if os(macOS)
import ATProtoOAuth
import ComposableArchitecture2
import ComposableNotifications
import ComposableNotificationsHTTP
import ComposableNotificationsServer
import Crypto
import CustomDump
import Dependencies
import Foundation
import HTTPClient
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import NIOCore
import OpenMusicEventDatabase
import OpenMusicEventSource
import OpenMusicEventSourceClone
import OpenMusicEventSourceEditing
import SQLiteData
import Sharing
import TCATProtoAuthentication
import Testing
import XRPCClient

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
    func `entered event receives standard and emergency FCM updates across restarts`() async throws {
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
        let channelID = OME.Channel.ID(
            organizerID: organizerID,
            eventID: eventID.eventID,
            channelID: OME.ID<OME.Channel>(rawValue: "announcements")
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
            try InstalledEventRecord.insert {
                InstalledEventRecord(id: eventID)
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
            try OME.Channel.insert {
                OME.Channel.Draft(
                    id: channelID,
                    name: "Announcements",
                    description: "Official festival updates.",
                    iconImageURL: nil,
                    headerImageURL: nil,
                    sortIndex: nil,
                    defaultNotificationState: .unsubscribed,
                    notificationsRequired: false
                )
            }
            .execute(database)
        }
        let eventSubscription = NotificationSubscription(
            sourceID: .init(
                rawValue: "at://did:plc:wickedwoods/app.openmusicevent.event/2026"
            )
        )
        let channelSubscription = NotificationSubscription(
            sourceID: .init(
                rawValue: AppRoute.event(eventID, .channel(channelID.channelID))
                    .notificationRoute
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
        let beforeRepository = directory.appending(path: "before", directoryHint: .isDirectory)
        let afterRepository = directory.appending(path: "after", directoryHint: .isDirectory)
        try writeNotificationSourceRepository(to: beforeRepository, posts: [:])
        try writeNotificationSourceRepository(
            to: afterRepository,
            posts: [
                "gates-open": NotificationSourcePost(
                    contents: "The gates are now open."
                ),
                "evacuate-now": NotificationSourcePost(
                    contents: "Proceed to the marked evacuation point.",
                    delivery: .emergency
                ),
            ]
        )
        let sourceCheckout = TangledSourceCheckoutClient { request in
            let repository: URL
            switch request.ref {
            case "1111111111111111111111111111111111111111":
                repository = beforeRepository
            case updatedSource.version.rawValue:
                repository = afterRepository
            default:
                throw NotificationSourceFixtureError.unexpectedRevision(request.ref)
            }
            try FileManager.default.copyItem(at: repository, to: request.outputURL)
            return TangledSourceCheckout(repositoryURL: request.outputURL)
        }
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
                        repository: TangledRepositoryReference(
                            host: "tangled.org",
                            owner: "wickedwoods.ca",
                            repository: "ome-workspace"
                        ),
                        hookID: webhookHookID,
                        repositoryOwnerDID: organizerID,
                        repositoryDID: organizerID,
                        ref: "refs/heads/main",
                        canonicalSource: CanonicalTangledSource(
                            organizerID: try #require(
                                OME.Organizer.ID(organizerID.description)
                            ),
                            repositoryRecordKey: repositoryKey
                        )
                    )
                ]
            ),
            sourceArtifacts: SourceArtifactS3Configuration(
                bucket: "resources.openmusicevent.app",
                region: "us-west-2",
                publicOrigin: try #require(
                    URL(string: "https://resources.openmusicevent.app")
                ),
                credentials: SourceArtifactAWSCredentials(
                    accessKeyID: "fixture-access-key",
                    secretAccessKey: "fixture-secret-key"
                )
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
        let eventRefreshRecorder = EventRefreshRecorder()
        let keychainStorage = KeychainStorageClient.inMemory()
        let appViewStore = try OpenMusicEventAppViewStore(
            databaseURL: appViewDatabaseURL,
            webhookSecretProtection: webhookSecretProtection
        )
        try await appViewStore.replaceWebhookSecret(
            webhookSecret,
            source: .tangled,
            watchID: webhookWatchID
        )
        let fakeFCM = FakeFCMTransport()
        let notificationProvider = NotificationProviderClient.http(
            configuration: NotificationProviderHTTPConfiguration(
                fcm: [
                    .init(rawValue: "app.openmusicevent"): .init(
                        projectID: "open-music-event",
                        emergencyChannelID: "emergency-alerts"
                    )
                ]
            ),
            authorization: NotificationProviderAuthorization(
                apnsBearerToken: { _ in "unused-apns-token" },
                fcmAccessToken: { applicationID in
                    expectNoDifference(applicationID.rawValue, "app.openmusicevent")
                    return "fixture-fcm-oauth-token"
                }
            ),
            transport: NotificationProviderHTTPTransport { request in
                try await fakeFCM.send(request)
            },
            now: { Date(timeIntervalSince1970: 0) }
        )

        do {
            try await withDependencies {
                $0.continuousClock = ContinuousClock()
                $0.date = .constant(Date(timeIntervalSince1970: 0))
                $0.uuid = .incrementing
                $0.tangledSourceCheckout = sourceCheckout
            } operation: {
                let app = try OpenMusicEventAppViewServer.application(
                    configuration: configuration,
                    store: appViewStore,
                    notificationProvider: notificationProvider,
                    tangledSourceUpdateProcessor: .publishSourceAndNotifyChannels(
                        store: appViewStore,
                        artifactPublisher: notificationSourceArtifactPublisher,
                        downloadAndValidate: loadNotificationSourceArchive
                    )
                )
                try await app.test(.live) { server in
                    try await withDependencies {
                        $0.context = .test
                        $0.date = .constant(Date(timeIntervalSince1970: 0))
                        $0.uuid = .incrementing
                        $0.httpClient = .liveValue
                        $0.keychainStorage = keychainStorage
                        OME.prepareDependencies(&$0, database: database)
                        $0.defaultEventID = eventID
                        $0.omeEventInstallation = OMEEventInstallationClient(
                            ensureInstalled: { _ in eventID },
                            synchronizeInstalledEvent: { eventID in
                                await eventRefreshRecorder.record(eventID)
                            }
                        )
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
                        let appStore = await MainActor.run {
                            Store(
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
                            }
                        }
                        await fakeFCM.deliverNotifications { json in
                            let reaction = await MainActor.run {
                                appStore.send(
                                    .notification(
                                        NotificationEvent(
                                            json: json,
                                            delivery: .contentAvailable
                                        )
                                    )
                                )
                            }
                            await reaction?.value
                        }
                        let destinationTask = await MainActor.run {
                            appStore.send(.notificationDestination(destination))
                        }
                        await destinationTask?.value

                        try await requestRecorder.waitForRequestCount(3)
                        let communications = try await MainActor.run {
                            let root = appStore
                                .scope(\.content, action: \.content)
                                .scope(\.content, action: \.content)
                            let destination = try #require(
                                root.scope(\.destination, action: \.destination)
                            )
                            let workspace = try #require(
                                destination.scope(\.eventViewer, action: \.eventViewer)
                            )
                            let authoring = workspace.scope(\.authoring, action: \.authoring)
                            let workspaceContent = authoring.scope(\.content, action: \.content)
                            let eventViewer = workspaceContent.scope(\.content, action: \.content)
                            return try #require(
                                eventViewer.scope(
                                    \.communicationsViewer,
                                    action: \.communicationsViewer
                                )
                            )
                        }
                        let subscriptionTask = await MainActor.run {
                            communications.send(
                                .notificationStateButtonTapped(channelID, .subscribed)
                            )
                        }
                        await subscriptionTask?.value
                        try await requestRecorder.waitForRequestCount(4)

                        let browse = await MainActor.run {
                            appStore
                                .scope(\.content, action: \.content)
                                .scope(\.content, action: \.content)
                                .scope(\.browser, action: \.browser)
                                .spawn(\.browse)
                        }
                        let browseTask = await MainActor.run {
                            browse.send(.task)
                        }
                        await browseTask?.value
                        try await requestRecorder.waitForRequestCount(5)

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
                        try await fakeFCM.waitForRequestCount(3)
                        try await requestRecorder.waitForRequestCount(8)
                        let refreshedEventIDs = await eventRefreshRecorder.eventIDs()
                        expectNoDifference(
                            refreshedEventIDs,
                            [eventID, eventID, eventID]
                        )

                        let providerRequests = await fakeFCM.requests()
                        expectNoDifference(providerRequests.count, 3)
                        for providerRequest in providerRequests {
                            expectNoDifference(providerRequest.method, .post)
                            expectNoDifference(
                                providerRequest.url.absoluteString,
                                "https://fcm.googleapis.com/v1/projects/open-music-event/messages:send"
                            )
                            expectNoDifference(
                                providerRequest.headerFields,
                                [
                                    "Authorization": "Bearer fixture-fcm-oauth-token",
                                    "Content-Type": "application/json",
                                ]
                            )
                        }
                        expectNoDifference(
                            providerRequests.map { String(decoding: $0.body, as: UTF8.self) },
                            [
                                #"{"message":{"android":{"priority":"HIGH","ttl":"900s"},"data":{"body":"Proceed to the marked evacuation point.","kind":"content","route":"/orgs/did%3Aplc%3Awickedwoods/events/2026/communications/announcements/posts/evacuate-now","source":"at://did:plc:wickedwoods/app.openmusicevent.event/2026","title":"evacuate-now","version":"2222222222222222222222222222222222222222"},"fid":"fcm-registration-token-that-must-not-be-rewritten","notification":{"body":"Proceed to the marked evacuation point.","channel_id":"emergency-alerts","title":"evacuate-now"}}}"#,
                                #"{"message":{"data":{"kind":"source_available","source":"at://did:plc:wickedwoods/app.openmusicevent.event/2026","version":"2222222222222222222222222222222222222222"},"fid":"fcm-registration-token-that-must-not-be-rewritten"}}"#,
                                #"{"message":{"android":{"priority":"HIGH"},"data":{"body":"The gates are now open.","kind":"content","route":"/orgs/did%3Aplc%3Awickedwoods/events/2026/communications/announcements/posts/gates-open","source":"/orgs/did%3Aplc%3Awickedwoods/events/2026/communications/announcements","title":"gates-open","version":"2222222222222222222222222222222222222222"},"fid":"fcm-registration-token-that-must-not-be-rewritten","notification":{"body":"The gates are now open.","title":"gates-open"}}}"#,
                            ]
                        )
                        withExtendedLifetime(appStore) {}
                    }
                }
            }
        }

        let installationID = try await storedInstallationID(at: appViewDatabaseURL)
        _ = try OpenMusicEventAppViewStore(
            databaseURL: appViewDatabaseURL
        )
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
        expectNoDifference(
            reopenedDestination,
            Optional(destination)
        )
        expectNoDifference(
            reopenedSubscriptions,
            Set([eventSubscription, channelSubscription])
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
                $0.defaultEventID = eventID
                $0.omeEventInstallation = OMEEventInstallationClient(
                    ensureInstalled: { _ in eventID },
                    synchronizeInstalledEvent: { eventID in
                        await eventRefreshRecorder.record(eventID)
                    }
                )
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
                let relaunchedStore = await MainActor.run {
                    Store(
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
                    }
                }
                let destinationTask = await MainActor.run {
                    relaunchedStore.send(.notificationDestination(destination))
                }
                await destinationTask?.value

                try await requestRecorder.waitForRequestCount(8)
                withExtendedLifetime(relaunchedStore) {}
            }
        }

        _ = try OpenMusicEventAppViewStore(
            databaseURL: appViewDatabaseURL
        )
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
        expectNoDifference(
            relaunchedDestination,
            Optional(destination)
        )
        expectNoDifference(
            relaunchedSubscriptions,
            Set([eventSubscription, channelSubscription])
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
            [.created, .noContent, .noContent, .noContent, .noContent, .noContent]
        )
        expectNoDifference(
            try registrationExchanges.map { exchange in
                try exchange.requestBody.map(canonicalJSONString)
            },
            [
                nil,
                #"{"applicationID":"app.openmusicevent","provider":"fcm","value":"fcm-registration-token-that-must-not-be-rewritten"}"#,
                #"{"sourceIDs":["at://did:plc:wickedwoods/app.openmusicevent.event/2026"]}"#,
                #"{"sourceIDs":["/orgs/did%3Aplc%3Awickedwoods/events/2026/communications/announcements","at://did:plc:wickedwoods/app.openmusicevent.event/2026"]}"#,
                #"{"applicationID":"app.openmusicevent","provider":"fcm","value":"fcm-registration-token-that-must-not-be-rewritten"}"#,
                #"{"sourceIDs":["/orgs/did%3Aplc%3Awickedwoods/events/2026/communications/announcements","at://did:plc:wickedwoods/app.openmusicevent.event/2026"]}"#,
            ]
        )
        expectNoDifference(browseExchanges.count, 4)
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

private let notificationSourceArtifactPublisher = SourceArtifactPublisher { request in
    PublishedSourceArtifact(
        url: URL(
            string: "https://resources.openmusicevent.app/wickedwoods.ca/ome-workspace/archive/\(request.revision).tar.gz"
        )!,
        reference: "https://resources.openmusicevent.app/wickedwoods.ca/ome-workspace",
        objectKey: "wickedwoods.ca/ome-workspace/archive/\(request.revision).tar.gz",
        revision: request.revision,
        checksumSHA256: "fixture-sha256",
        byteCount: request.archiveData.count,
        publishedAt: Date(timeIntervalSince1970: 0)
    )
}

private func loadNotificationSourceArchive(
    update: TangledSourceUpdate,
    revision: String
) async throws -> ValidatedSourceArchive {
    let repository =
        "at://\(update.repositoryOwnerDID)/sh.tangled.repo/\(update.repositoryKey.rawValue)"
    let validation = try await OpenMusicEventSourceValidator(
        OpenMusicEventSourceValidationRequest(
            source: repository,
            organizerID: update.canonicalSource.organizerID,
            sourceProvenance: update.canonicalSource.provenance(ref: revision),
            ref: revision
        )
    )
    .validate()
    return ValidatedSourceArchive(
        data: Data(revision.utf8),
        snapshot: try TangledSourceSnapshot(
            validated: validation.insertion,
            revision: revision
        )
    )
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

private func writeNotificationSourceRepository(
    to root: URL,
    posts: [String: NotificationSourcePost]
) throws {
    let event = root
        .appending(path: "events", directoryHint: .isDirectory)
        .appending(path: "2026", directoryHint: .isDirectory)
    let communications = event
        .appending(path: "communications", directoryHint: .isDirectory)
        .appending(path: "announcements", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: communications, withIntermediateDirectories: true)
    let channels = event.appending(path: "channels", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: channels, withIntermediateDirectories: true)
    try Data(
        """
        id:
          organizerID: did:plc:wickedwoods
          eventID: "2026"
        name: Wicked Woods 2026
        timeZone: America/Denver
        """.utf8
    ).write(to: event.appending(path: "event.yml"))
    try Data(
        """
        name: Announcements
        description: Official festival updates.
        defaultNotificationState: subscribed
        notificationsRequired: false
        """.utf8
    ).write(to: channels.appending(path: "announcements.yml"))
    for (postID, post) in posts {
        try Data(
            """
            ---
            title: \(postID)
            delivery: \(post.delivery.rawValue)
            ---
            \(post.contents)
            """.utf8
        ).write(to: communications.appending(path: "\(postID).md"))
    }
}

private struct NotificationSourcePost {
    var contents: String
    var delivery: OME.Announcement.Delivery = .standard
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

private actor FakeFCMTransport {
    typealias Delivery = @Sendable (String) async -> Void

    private var delivery: Delivery?
    private var recordedRequests: [NotificationProviderHTTPRequest] = []

    func deliverNotifications(_ delivery: @escaping Delivery) {
        // Delivery re-enters the app from the server, which owns a different database.
        self.delivery = withEscapedDependencies { dependencies in
            { json in
                await dependencies.yield { await delivery(json) }
            }
        }
    }

    func send(
        _ request: NotificationProviderHTTPRequest
    ) async throws -> NotificationProviderHTTPResponse {
        let payload = try JSONSerialization.jsonObject(with: request.body)
        guard
            let payload = payload as? [String: Any],
            let message = payload["message"] as? [String: Any],
            let data = message["data"] as? [String: String]
        else {
            throw FakeFCMTransportError.invalidPayload
        }
        let appPayload = try JSONSerialization.data(
            withJSONObject: data,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        await delivery?(String(decoding: appPayload, as: UTF8.self))
        recordedRequests.append(request)
        return NotificationProviderHTTPResponse(status: 200)
    }

    func requests() -> [NotificationProviderHTTPRequest] {
        recordedRequests
    }

    func waitForRequestCount(_ count: Int) async throws {
        for _ in 0..<500 {
            guard recordedRequests.count < count else { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw FakeFCMTransportError.timedOut(
            expectedRequestCount: count,
            actualRequestCount: recordedRequests.count
        )
    }
}

private actor EventRefreshRecorder {
    private var recordedEventIDs: [OMERecord.Event.ID] = []

    func record(_ eventID: OMERecord.Event.ID) {
        recordedEventIDs.append(eventID)
    }

    func eventIDs() -> [OMERecord.Event.ID] {
        recordedEventIDs
    }
}

private enum FakeFCMTransportError: Error {
    case invalidPayload
    case timedOut(expectedRequestCount: Int, actualRequestCount: Int)
}

private enum NotificationSourceFixtureError: Error {
    case unexpectedRevision(String)
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
