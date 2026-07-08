import ATProtoOAuth
import Dependencies
import TCATProtoAuthentication

public typealias OpenMusicEventAuthorizationRequests = OAuthAuthorizationRequests

private enum OpenMusicEventSignUpServerConfigurationKey: DependencyKey {
    static var liveValue: OAuthSignUpServerConfiguration {
        OpenMusicEventOAuth.signUpServerConfiguration
    }

    static var testValue: OAuthSignUpServerConfiguration {
        OAuthSignUpServerConfiguration(
            defaultServerHost: "bsky.social",
            options: [
                OAuthSignUpServerOption(
                    id: "bsky",
                    title: "BlueSky",
                    subtitle: "bsky.social",
                    metadataSource: "test",
                    availability: .available(serverHost: "bsky.social")
                )
            ]
        )
    }
}

public extension DependencyValues {
    var openMusicEventAuthorizationRequests: OpenMusicEventAuthorizationRequests {
        get { oauthAuthorizationRequests }
        set { oauthAuthorizationRequests = newValue }
    }

    var openMusicEventSignUpServerConfiguration: OAuthSignUpServerConfiguration {
        get { self[OpenMusicEventSignUpServerConfigurationKey.self] }
        set { self[OpenMusicEventSignUpServerConfigurationKey.self] = newValue }
    }
}

public extension OpenMusicEventAuthorizationRequests {
    func openMusicEventAutoStartingAuthorizationUpgrades(
        session: @escaping @Sendable () -> OAuth.Session?,
        sessionStore: @escaping @Sendable () -> OAuth.SessionStore,
        appManifest: OAuth.AppManifest
    ) -> Self {
        let authorizeWithLoginHint = authorizeWithLoginHint
        let broker = broker
        let requests = requests
        let signUp = signUp
        let signUpWithConfiguration = signUpWithConfiguration
        let succeed = succeed
        let fail = fail
        let cancel = cancel

        return Self(
            authorizeWithLoginHint: authorizeWithLoginHint,
            broker: {
                let upstreamBroker = broker()
                return OAuth.AuthorizationBroker { requirement in
                    guard let currentSession = session() ?? sessionStore().selectedSession
                    else {
                        try await upstreamBroker.authorize(requirement)
                        return
                    }

                    switch OAuth.authorizationStatus(
                        for: requirement,
                        session: currentSession,
                        manifest: appManifest
                    ) {
                    case .satisfied:
                        return

                    case .upgradeAvailable:
                        try await authorizeWithLoginHint(
                            requirement,
                            currentSession.accountID.rawValue.description
                        )

                    case .signInRequired, .wrongAccount, .impossible:
                        try await upstreamBroker.authorize(requirement)
                    }
                }
            },
            requests: requests,
            signUp: signUp,
            signUpWithConfiguration: signUpWithConfiguration,
            succeed: succeed,
            fail: fail,
            cancel: cancel
        )
    }

    func openMusicEventDefaultingSignUpServerConfiguration(
        _ signUpServerConfiguration: OAuthSignUpServerConfiguration
    ) -> Self {
        let authorizeWithLoginHint = authorizeWithLoginHint
        let broker = broker
        let requests = requests
        let signUp = signUp
        let signUpWithConfiguration = signUpWithConfiguration
        let succeed = succeed
        let fail = fail
        let cancel = cancel

        return Self(
            authorizeWithLoginHint: authorizeWithLoginHint,
            broker: broker,
            requests: {
                let upstream = await requests()
                return AsyncStream { continuation in
                    let task = Task {
                        for await request in upstream {
                            continuation.yield(
                                request?
                                    .openMusicEventDefaultingSignUpServerConfiguration(
                                        signUpServerConfiguration
                                    )
                            )
                        }
                        continuation.finish()
                    }
                    continuation.onTermination = { _ in
                        task.cancel()
                    }
                }
            },
            signUp: signUp,
            signUpWithConfiguration: signUpWithConfiguration,
            succeed: succeed,
            fail: fail,
            cancel: cancel
        )
    }
}

public extension AuthorizationPresentationRequest {
    func openMusicEventDefaultingSignUpServerConfiguration(
        _ signUpServerConfiguration: OAuthSignUpServerConfiguration
    ) -> Self {
        guard self.signUpServerConfiguration.options.isEmpty else { return self }
        return Self(
            id: id,
            loginHint: loginHint,
            mode: mode,
            startsImmediately: startsImmediately,
            serverHost: serverHost,
            signUpServerConfiguration: signUpServerConfiguration,
            requirement: requirement,
            responder: responder
        )
    }
}

public extension AuthorizationRequestCenter.Request {
    func openMusicEventDefaultingSignUpServerConfiguration(
        _ signUpServerConfiguration: OAuthSignUpServerConfiguration
    ) -> Self {
        guard self.signUpServerConfiguration.options.isEmpty else { return self }
        return Self(
            id: id,
            loginHint: loginHint,
            mode: mode,
            startsImmediately: startsImmediately,
            serverHost: serverHost,
            signUpServerConfiguration: signUpServerConfiguration,
            requirement: requirement
        )
    }
}
