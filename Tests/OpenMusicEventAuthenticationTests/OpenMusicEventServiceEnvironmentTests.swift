import ATProtoOAuth
import ComposableNotifications
import CustomDump
import Dependencies
import Foundation
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
}
