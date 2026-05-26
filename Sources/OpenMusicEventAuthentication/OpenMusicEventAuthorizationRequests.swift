import ATProtoOAuth
import Dependencies
import Foundation
import TCATProtoAuthentication

public struct OpenMusicEventAuthorizationRequests: Sendable {
    public var broker: @Sendable () -> OAuth.AuthorizationBroker
    public var requests: @Sendable () async -> AsyncStream<AuthorizationRequestCenter.Request?>
    public var succeed: @Sendable () async -> Void
    public var fail: @Sendable (OAuth.AuthorizationRequired) async -> Void
    public var cancel: @Sendable () async -> Void

    public init(
        broker: @escaping @Sendable () -> OAuth.AuthorizationBroker,
        requests: @escaping @Sendable () async -> AsyncStream<AuthorizationRequestCenter.Request?>,
        succeed: @escaping @Sendable () async -> Void,
        fail: @escaping @Sendable (OAuth.AuthorizationRequired) async -> Void,
        cancel: @escaping @Sendable () async -> Void
    ) {
        self.broker = broker
        self.requests = requests
        self.succeed = succeed
        self.fail = fail
        self.cancel = cancel
    }
}

public extension OpenMusicEventAuthorizationRequests {
    init(center: AuthorizationRequestCenter) {
        self.init(
            broker: { center.broker },
            requests: { await center.requests() },
            succeed: { await center.succeed() },
            fail: { error in await center.fail(error) },
            cancel: { await center.cancel() }
        )
    }

    static let noop = Self(
        broker: {
            OAuth.AuthorizationBroker { requirement in
                throw OAuth.AuthorizationRequired.signIn(requirement)
            }
        },
        requests: {
            AsyncStream { continuation in
                continuation.finish()
            }
        },
        succeed: {},
        fail: { _ in },
        cancel: {}
    )
}

private let liveAuthorizationRequestCenter = AuthorizationRequestCenter()

private enum OpenMusicEventAuthorizationRequestsKey: TestDependencyKey {
    static let testValue = OpenMusicEventAuthorizationRequests.noop
}

extension OpenMusicEventAuthorizationRequestsKey: DependencyKey {
    static var liveValue: OpenMusicEventAuthorizationRequests {
        OpenMusicEventAuthorizationRequests(center: liveAuthorizationRequestCenter)
    }
}

public extension DependencyValues {
    var openMusicEventAuthorizationRequests: OpenMusicEventAuthorizationRequests {
        get { self[OpenMusicEventAuthorizationRequestsKey.self] }
        set { self[OpenMusicEventAuthorizationRequestsKey.self] = newValue }
    }
}
