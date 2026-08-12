import ComposableNotifications
import Crypto
import Foundation
import Hummingbird
import Tagged

/// Runtime services for authenticated notification registration.
///
/// This is deliberately separate from ``AppViewConfiguration``: the app-view configuration holds
/// static host and resource settings, while this value owns runtime authentication and persistence.
/// The authorizer can use an anonymous installation credential today and OAuth/session/DPoP later.
/// In either case, it derives the installation identity from the authenticated request rather than
/// accepting it from the registration body.
public struct NotificationRegistrationServer: Sendable {
    public var installationAuthorizer: NotificationInstallationAuthorizer
    public var policy: NotificationRegistrationPolicy
    public var store: any NotificationRegistrationStore

    public init(
        store: any NotificationRegistrationStore,
        installationAuthorizer: NotificationInstallationAuthorizer,
        policy: NotificationRegistrationPolicy
    ) {
        self.installationAuthorizer = installationAuthorizer
        self.policy = policy
        self.store = store
    }
}

public struct NotificationRegistrationPolicy: Sendable {
    public init(
        allowedApplicationIDs: Set<Push.ApplicationID>,
        maximumDestinationBytes: Int = 4_096,
        maximumSourceIDBytes: Int = 512,
        maximumSubscriptions: Int = 256
    ) {
        self.allowedApplicationIDs = allowedApplicationIDs
        self.maximumDestinationBytes = maximumDestinationBytes
        self.maximumSourceIDBytes = maximumSourceIDBytes
        self.maximumSubscriptions = maximumSubscriptions
    }

    public var allowedApplicationIDs: Set<Push.ApplicationID>
    public var maximumDestinationBytes: Int
    public var maximumSourceIDBytes: Int
    public var maximumSubscriptions: Int

    func validate(_ payload: NotificationDestinationPayload) throws {
        guard allowedApplicationIDs.contains(Push.ApplicationID(rawValue: payload.applicationID))
        else {
            throw HTTPError(.forbidden)
        }
        guard
            !payload.value.isEmpty,
            payload.value.utf8.count <= maximumDestinationBytes
        else {
            throw HTTPError(.badRequest)
        }
    }

    func validate(_ payload: NotificationSubscriptionsPayload) throws {
        guard
            payload.sourceIDs.count <= maximumSubscriptions,
            Set(payload.sourceIDs).count == payload.sourceIDs.count,
            payload.sourceIDs.allSatisfy({
                !$0.isEmpty && $0.utf8.count <= maximumSourceIDBytes
            })
        else {
            throw HTTPError(.badRequest)
        }
    }
}

public struct NotificationInstallationAuthorizer: Sendable {
    public var createInstallation: @Sendable () async throws
        -> CreatedNotificationInstallation
    public var authenticateInstallation: @Sendable (Request) async throws
        -> NotificationInstallation.ID

    public init(
        createInstallation: @escaping @Sendable () async throws
            -> CreatedNotificationInstallation,
        authenticateInstallation: @escaping @Sendable (Request) async throws
            -> NotificationInstallation.ID
    ) {
        self.createInstallation = createInstallation
        self.authenticateInstallation = authenticateInstallation
    }

    public static func anonymous(
        store: any NotificationInstallationStore,
        makeInstallationID: (@Sendable () -> NotificationInstallation.ID)? = nil,
        makeCredential: (@Sendable () -> NotificationInstallation.Credential)? = nil
    ) -> Self {
        let makeInstallationID = makeInstallationID ?? {
            NotificationInstallation.ID(rawValue: UUID().uuidString.lowercased())
        }
        let makeCredential = makeCredential ?? {
            NotificationInstallation.Credential.random()
        }

        return Self(
            createInstallation: {
                let installation = NotificationInstallation(id: makeInstallationID())
                let credential = makeCredential()
                try await store.insertInstallation(
                    installation,
                    credentialFingerprint: credential.fingerprint
                )
                return CreatedNotificationInstallation(
                    id: installation.id,
                    credential: credential
                )
            },
            authenticateInstallation: { request in
                let credential = try request.notificationInstallationCredential
                guard let installationID = try await store.installationID(
                    for: credential.fingerprint
                ) else {
                    throw HTTPError(.unauthorized)
                }
                return installationID
            }
        )
    }
}

public struct CreatedNotificationInstallation: Equatable, Sendable {
    public var id: NotificationInstallation.ID
    public var credential: NotificationInstallation.Credential

    public init(
        id: NotificationInstallation.ID,
        credential: NotificationInstallation.Credential
    ) {
        self.id = id
        self.credential = credential
    }
}

private extension NotificationInstallation.Credential {
    static func random() -> Self {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in
            UInt8.random(in: .min ... .max, using: &generator)
        }
        let value = Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return Self(rawValue: value)
    }

    var fingerprint: NotificationInstallation.CredentialFingerprint {
        let digest = SHA256.hash(data: Data(rawValue.utf8))
        return NotificationInstallation.CredentialFingerprint(
            rawValue: Data(digest).base64EncodedString()
        )
    }
}

private extension Request {
    var notificationInstallationCredential: NotificationInstallation.Credential {
        get throws {
            guard let authorization = headers[.authorization] else {
                throw HTTPError(.unauthorized)
            }
            let prefix = "\(NotificationRegistrationEndpoint.authorizationScheme) "
            guard authorization.hasPrefix(prefix) else {
                throw HTTPError(.unauthorized)
            }
            let rawValue = String(authorization.dropFirst(prefix.count))
            guard
                !rawValue.isEmpty,
                rawValue.utf8.count <= 512,
                !rawValue.contains(" ")
            else {
                throw HTTPError(.unauthorized)
            }
            return NotificationInstallation.Credential(rawValue: rawValue)
        }
    }
}
