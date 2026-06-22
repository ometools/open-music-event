import ATProtoOAuth
import Dependencies
import TCATProtoAuthentication

public typealias OpenMusicEventAuthorizationRequests = OAuthAuthorizationRequests

private enum OpenMusicEventSignUpServerConfigurationKey: DependencyKey {
    static var liveValue: OAuthSignUpServerConfiguration {
        OpenMusicEventOAuth.signUpServerConfiguration
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
