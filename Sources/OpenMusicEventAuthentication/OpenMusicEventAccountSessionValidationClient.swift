import ATProtoOAuth
import ATProtoServer
import Dependencies
import Sharing
import TCATProtoAuthentication

public struct OpenMusicEventAccountSessionValidationClient: Sendable {
    public enum ValidationResult: Equatable, Sendable {
        case accepted(OAuth.Session)
        case requiresRelog
        case unverified
    }

    public var validate: @Sendable (OAuth.Session) async -> ValidationResult

    public init(
        validate: @escaping @Sendable (OAuth.Session) async -> ValidationResult
    ) {
        self.validate = validate
    }
}

private enum OpenMusicEventAccountSessionValidationClientKey: TestDependencyKey {
    static let testValue = OpenMusicEventAccountSessionValidationClient { session in
        .accepted(session)
    }
}

extension OpenMusicEventAccountSessionValidationClientKey: DependencyKey {
    static var liveValue: OpenMusicEventAccountSessionValidationClient {
        OpenMusicEventAccountSessionValidationClient { session in
            let validatedSession = Shared(value: session as OAuth.Session?)
            let authFailureMessage = Shared<ErrorMessage?>(value: nil)

            do {
                try await withDependencies {
                    $0.getDefaultSession = {
                        validatedSession.wrappedValue ?? session
                    }
                    $0.getOptionalDefaultSession = {
                        validatedSession.wrappedValue
                    }
                    $0.errorInterceptors = [
                        .tokenRefresh(
                            session: validatedSession,
                            authFailureMessage: authFailureMessage
                        ),
                    ]
                } operation: {
                    @Dependency(ATProto.Server.Client.self) var serverClient
                    _ = try await serverClient.getSession()
                }

                guard let acceptedSession = validatedSession.wrappedValue else {
                    return .requiresRelog
                }
                return .accepted(acceptedSession)
            } catch is CancellationError {
                return .unverified
            } catch is OAuth.TerminalAuthenticatedSessionFailure {
                return .requiresRelog
            } catch {
                return .unverified
            }
        }
    }
}

public extension DependencyValues {
    var openMusicEventAccountSessionValidationClient: OpenMusicEventAccountSessionValidationClient {
        get { self[OpenMusicEventAccountSessionValidationClientKey.self] }
        set { self[OpenMusicEventAccountSessionValidationClientKey.self] = newValue }
    }
}
