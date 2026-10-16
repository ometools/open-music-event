import ATProtoOAuth
import ComposableNotifications
import ComposableNotificationsHTTP
import CustomDump
import Dependencies
import Foundation
import HTTPClient
import HTTPTypes
import Testing

@testable import OpenMusicEventAuthentication

@Suite(.serialized)
struct OpenMusicEventServiceEnvironmentTests {
    @Test
    func `production and staging have distinct service endpoints`() {
        expectNoDifference(
            OpenMusicEventServiceEnvironment.production.serverURL,
            URL(string: "https://openmusicevent.app")!
        )
        expectNoDifference(
            OpenMusicEventServiceEnvironment.staging.serverURL,
            URL(string: "https://stg.openmusicevent.app")!
        )
    }

    @Test
    func `the persisted selection defaults to production and restores staging`() throws {
        let suiteName = "OpenMusicEventServiceEnvironmentTests"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        expectNoDifference(
            OpenMusicEventServiceEnvironment.persisted(userDefaults: userDefaults),
            .production
        )

        userDefaults.set(
            OpenMusicEventServiceEnvironment.staging.rawValue,
            forKey: OpenMusicEventServiceEnvironment.userDefaultsKey
        )

        expectNoDifference(
            OpenMusicEventServiceEnvironment.persisted(userDefaults: userDefaults),
            .staging
        )
    }

    @Test
    func `production and staging keep separate installation credentials`() async throws {
        var dependencies = DependencyValues()
        dependencies.keychainStorage = .inMemory()
        let productionStorage = OpenMusicEventNotificationAuthorization.credentialStorage(
            dependencies,
            environment: .production
        )
        let stagingStorage = OpenMusicEventNotificationAuthorization.credentialStorage(
            dependencies,
            environment: .staging
        )
        let productionCredential = NotificationInstallation.Credential(
            rawValue: "production-installation"
        )
        let stagingCredential = NotificationInstallation.Credential(
            rawValue: "staging-installation"
        )

        try await productionStorage.setCredential(productionCredential)
        let storedProductionCredential = try await productionStorage.credential()
        let missingStagingCredential = try await stagingStorage.credential()
        expectNoDifference(storedProductionCredential, productionCredential)
        expectNoDifference(missingStagingCredential, nil)

        try await stagingStorage.setCredential(stagingCredential)
        let preservedProductionCredential = try await productionStorage.credential()
        let storedStagingCredential = try await stagingStorage.credential()
        expectNoDifference(preservedProductionCredential, productionCredential)
        expectNoDifference(storedStagingCredential, stagingCredential)
    }

    @Test
    func `staging registration replaces an installation rejected by the staging AppView`() async throws {
        let staleCredential = NotificationInstallation.Credential(rawValue: "stale-credential")
        let replacementCredential = NotificationInstallation.Credential(
            rawValue: "replacement-credential"
        )
        var dependencies = DependencyValues()
        dependencies.keychainStorage = .inMemory()
        let credentialStorage = OpenMusicEventNotificationAuthorization.credentialStorage(
            dependencies,
            environment: .staging
        )
        try await credentialStorage.setCredential(staleCredential)
        let requests = NotificationRegistrationRequestRecorder()

        try await withDependencies {
            $0.keychainStorage = dependencies.keychainStorage
            $0.httpClient = .liveValue
            $0.dataForURL = { request, _ in
                await requests.record(request)
                expectNoDifference(request.url?.host(), "stg.openmusicevent.app")

                switch request.url?.path {
                case NotificationRegistrationEndpoint.installationsPath:
                    #expect(request.headerFields[.authorization] == nil)
                    return (
                        try JSONEncoder().encode(
                            NotificationInstallationCredentialPayload(
                                credential: replacementCredential
                            )
                        ),
                        HTTPResponse(status: .created)
                    )

                case NotificationRegistrationEndpoint.destinationPath,
                    NotificationRegistrationEndpoint.subscriptionsPath:
                    let status: HTTPResponse.Status =
                        request.headerFields[.authorization] == "Notification stale-credential"
                        ? .unauthorized
                        : .noContent
                    return (Data(), HTTPResponse(status: status))

                default:
                    Issue.record("Unexpected notification request: \(String(describing: request.url))")
                    return (Data(), HTTPResponse(status: .notFound))
                }
            }
            OpenMusicEventNotificationAuthorization.prepareDependencies(
                &$0,
                environment: .staging
            )
        } operation: {
            let notifications = NotificationsClient.http(
                baseURL: OpenMusicEventServiceEnvironment.staging.serverURL
            )
            try await notifications.registerDestination(
                .apns(
                    Push.APNS(
                        applicationID: .init(rawValue: "fm.woody.wickedwoods"),
                        environment: .development,
                        deviceToken: .init(rawValue: "fixture-device-token")
                    )
                )
            )
        }

        let recordedRequests = await requests.requests
        expectNoDifference(
            recordedRequests.map { $0.url?.path },
            [
                NotificationRegistrationEndpoint.destinationPath,
                NotificationRegistrationEndpoint.installationsPath,
                NotificationRegistrationEndpoint.destinationPath,
                NotificationRegistrationEndpoint.subscriptionsPath,
            ]
        )
        expectNoDifference(
            recordedRequests.map { $0.headerFields[.authorization] },
            [
                "Notification stale-credential",
                nil,
                "Notification replacement-credential",
                "Notification replacement-credential",
            ]
        )
        let storedCredential = try await credentialStorage.credential()
        expectNoDifference(storedCredential, replacementCredential)
    }
}

actor NotificationRegistrationRequestRecorder {
    var requests: [HTTPRequest] = []

    func record(_ request: HTTPRequest) {
        requests.append(request)
    }
}
