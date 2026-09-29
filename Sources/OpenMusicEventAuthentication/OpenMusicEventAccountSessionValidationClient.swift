import ATProto
import ATProtoOAuth
import ATProtoServer
import Dependencies
import Sharing
import TCATProtoAuthentication

public struct OpenMusicEventAccountSessionValidationClient: Sendable {
    public enum ValidationResult: Equatable, Sendable {
        case accepted(handle: Atmosphere.Account.Handle? = nil)
        case requiresRelog
        case unverified
    }

    public var validate: @Sendable (Atmosphere.Account.ID) async throws -> ValidationResult

    public init(
        validate: @escaping @Sendable (Atmosphere.Account.ID) async throws -> ValidationResult
    ) {
        self.validate = validate
    }
}

private enum OpenMusicEventAccountSessionValidationClientKey: TestDependencyKey {
    static let testValue = OpenMusicEventAccountSessionValidationClient { _ in
        .accepted()
    }
}

extension OpenMusicEventAccountSessionValidationClientKey: DependencyKey {
    static var liveValue: OpenMusicEventAccountSessionValidationClient {
        OpenMusicEventAccountSessionValidationClient { accountID in
            @Dependency(\.oauthSessionReference) var sessionReference
            guard let reference = sessionReference(accountID), reference.wrappedValue != nil else {
                return .requiresRelog
            }
            do {
                let bound = try OAuth.StoredSession(reference: reference)
                let serverSession = try await bound.withAccount {
                    @Dependency(ATProto.Server.Client.self) var serverClient
                    return try await serverClient.getSession()
                }
                guard serverSession.did == accountID else { return .unverified }
                return .accepted(handle: serverSession.handle)
            } catch is CancellationError {
                throw CancellationError()
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
