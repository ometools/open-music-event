import ATProto
import ATProtoOAuth
import ATProtoServer
import Dependencies
import Foundation
import TCATProtoAuthentication

public struct OpenMusicEventAccountAuthorizationClient: Sendable {
    public var signIn: @Sendable (
        OAuth.AuthRequirement,
        String,
        OAuth.SessionStore
    ) async throws -> OAuth.Session
    public var signUp: @Sendable (
        OAuth.AuthRequirement,
        String
    ) async throws -> OAuth.Session

    public init(
        signIn: @escaping @Sendable (
            OAuth.AuthRequirement,
            String,
            OAuth.SessionStore
        ) async throws -> OAuth.Session,
        signUp: @escaping @Sendable (
            OAuth.AuthRequirement,
            String
        ) async throws -> OAuth.Session
    ) {
        self.signIn = signIn
        self.signUp = signUp
    }
}

private enum OpenMusicEventAccountAuthorizationClientKey: TestDependencyKey {
    static let testValue = OpenMusicEventAccountAuthorizationClient(
        signIn: { _, _, _ in
            unimplemented("\(Self.self).signIn", placeholder: .placeholder)
        },
        signUp: { _, _ in
            unimplemented("\(Self.self).signUp", placeholder: .placeholder)
        }
    )
}

extension OpenMusicEventAccountAuthorizationClientKey: DependencyKey {
    static var liveValue: OpenMusicEventAccountAuthorizationClient {
        OpenMusicEventAccountAuthorizationClient(
            signIn: { requirement, loginHint, sessionStore in
                @Dependency(OAuth.Client.self) var authClient
                @Dependency(\.oauthAppConfiguration) var oauthAppConfig
                @Dependency(\.oauthAppManifest) var appManifest
                @Dependency(\.oauthBrowserStrategy) var browserStrategy
                @Dependency(\.webAuthenticationSession) var webAuthenticationSession

                let login = try parseLoginHint(loginHint)
                let currentSession = sessionStore.session(for: requirement.account)
                let requested = try OAuth.requestedPermissions(
                    for: requirement,
                    currentSession: currentSession,
                    manifest: appManifest
                )
                let pending = try await authClient.beginAuthorizationWithPermissions(
                    login,
                    requested
                )

                let session: OAuth.Session
                switch browserStrategy {
                case .webAuthenticationSession:
                    let callbackURL = try await webAuthenticationSession.open(
                        url: pending.authorizationURL,
                        redirectURI: oauthAppConfig.redirectURI.rawValue
                    )
                    session = try await authClient.handleCallback(
                        url: callbackURL,
                        pending: pending.session
                    )

                case .externalBrowser:
                    throw URLError(.unsupportedURL)
                }

                return try validatedSession(
                    session,
                    requirement: requirement,
                    manifest: appManifest
                )
            },
            signUp: { requirement, serverHostString in
                @Dependency(ATProto.Server.Client.self) var serverClient
                @Dependency(OAuth.Client.self) var authClient
                @Dependency(\.oauthAppConfiguration) var oauthAppConfig
                @Dependency(\.oauthAppManifest) var appManifest
                @Dependency(\.oauthBrowserStrategy) var browserStrategy
                @Dependency(\.webAuthenticationSession) var webAuthenticationSession

                let serverHost = try parseServerHost(serverHostString)
                _ = try await serverClient.describeServer(serverHost)
                let requested = try OAuth.requestedPermissions(
                    for: requirement,
                    currentSession: nil,
                    manifest: appManifest
                )
                let pending = try await authClient.beginAuthorizationFromServerHost(
                    serverHost,
                    requested
                )

                let session: OAuth.Session
                switch browserStrategy {
                case .webAuthenticationSession:
                    let callbackURL = try await webAuthenticationSession.open(
                        url: pending.authorizationURL,
                        redirectURI: oauthAppConfig.redirectURI.rawValue
                    )
                    session = try await authClient.handleCallback(
                        url: callbackURL,
                        pending: pending.session
                    )

                case .externalBrowser:
                    throw URLError(.unsupportedURL)
                }

                return try validatedSession(
                    session,
                    requirement: requirement,
                    manifest: appManifest
                )
            }
        )
    }
}

public extension DependencyValues {
    var openMusicEventAccountAuthorizationClient: OpenMusicEventAccountAuthorizationClient {
        get { self[OpenMusicEventAccountAuthorizationClientKey.self] }
        set { self[OpenMusicEventAccountAuthorizationClientKey.self] = newValue }
    }
}

private func parseLoginHint(_ rawValue: String) throws -> ATProto.URI.Authority {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let login = Atmosphere.Account.Identifier(trimmed) else {
        throw URLError(.badURL)
    }
    return login
}

private func parseServerHost(_ rawValue: String) throws -> ATProto.PDSHost {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw URLError(.badURL) }

    if let url = URL(string: trimmed),
       url.scheme != nil,
       let host = url.host
    {
        return ATProto.PDSHost(host)
    }

    return ATProto.PDSHost(trimmed)
}

private func validatedSession(
    _ session: OAuth.Session,
    requirement: OAuth.AuthRequirement,
    manifest: OAuth.AppManifest
) throws -> OAuth.Session {
    switch OAuth.authorizationStatus(
        for: requirement,
        session: session,
        manifest: manifest
    ) {
    case .satisfied:
        return session

    case .signInRequired(let requirement):
        throw OAuth.AuthorizationRequired.signIn(requirement)

    case .wrongAccount(let required, let actual):
        throw OAuth.AuthorizationRequired.wrongAccount(
            required: required,
            actual: actual
        )

    case .upgradeAvailable(let missing, let requirement):
        throw OAuth.AuthorizationRequired.upgrade(
            requirement,
            missing: missing
        )

    case .impossible(let missing, let requirement):
        throw OAuth.AuthorizationRequired.impossible(
            requirement,
            missing: missing
        )
    }
}
