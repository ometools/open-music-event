import ATProto
import ATProtoOAuth
import Dependencies
import Foundation
import HTTPClient
import IssueReporting
import Sharing
import ComposableAtmosphere

public struct OpenMusicEventSelectedOAuthSessionClient: Sendable {
    public var current: @Sendable () -> OAuth.Session?
    public var update: @Sendable (
        @escaping @Sendable (inout OAuth.Session?) -> Void
    ) async -> Void

    public init(
        current: @escaping @Sendable () -> OAuth.Session?,
        update: @escaping @Sendable (
            @escaping @Sendable (inout OAuth.Session?) -> Void
        ) async -> Void
    ) {
        self.current = current
        self.update = update
    }
}

public extension OpenMusicEventSelectedOAuthSessionClient {
    static func live(
        sessionStore: Shared<OAuth.SessionStore>,
        selectedSessionID: Shared<Atmosphere.Account.ID?>
    ) -> Self {
        Self(
            current: {
                sessionStore.wrappedValue[selectedSessionID.wrappedValue]
            },
            update: { update in
                sessionStore.withLock { sessionStore in
                    var session = sessionStore[selectedSessionID.wrappedValue]
                    update(&session)
                    sessionStore[selectedSessionID.wrappedValue] = session
                }
                await saveOpenMusicEventSharedValue(sessionStore)
            }
        )
    }

    static let none = Self(
        current: { nil },
        update: { _ in }
    )
}

private enum SelectedOAuthSessionIDKey: DependencyKey {
    static let liveValue: @Sendable () -> Atmosphere.Account.ID? = { nil }
    static let testValue: @Sendable () -> Atmosphere.Account.ID? = { nil }
}

private enum SelectedOAuthSessionKey: DependencyKey {
    static let liveValue = OpenMusicEventSelectedOAuthSessionClient.none
    static let testValue = OpenMusicEventSelectedOAuthSessionClient.none
}

public extension DependencyValues {
    var selectedOAuthSessionID: Atmosphere.Account.ID? {
        get { getSelectedOAuthSessionID() }
        set {
            getSelectedOAuthSessionID = { newValue }
        }
    }

    var getSelectedOAuthSessionID: @Sendable () -> Atmosphere.Account.ID? {
        get { self[SelectedOAuthSessionIDKey.self] }
        set { self[SelectedOAuthSessionIDKey.self] = newValue }
    }

    var selectedOAuthSession: OpenMusicEventSelectedOAuthSessionClient {
        get { self[SelectedOAuthSessionKey.self] }
        set { self[SelectedOAuthSessionKey.self] = newValue }
    }
}

public extension OAuthSessionStorage {
    init(
        sessionStore: Shared<OAuth.SessionStore>,
        authFailureMessage: Shared<ErrorMessage?>,
        selectedSessionID: Shared<Atmosphere.Account.ID?>
    ) {
        syncOpenMusicEventSelectedSessionID(selectedSessionID, into: sessionStore)
        self.init(
            sessionStore: sessionStore,
            authFailureMessage: authFailureMessage
        )
    }
}

func syncOpenMusicEventSelectedSessionID(
    _ selectedSessionID: Shared<Atmosphere.Account.ID?>,
    into sessionStore: Shared<OAuth.SessionStore>
) {
    let selectedAccountID = selectedSessionID.withLock { $0 }
    sessionStore.selectedAccountID.withLock {
        $0 = selectedAccountID
    }
}

public extension ErrorInterceptor {
    static func openMusicEventTokenRefresh(
        selectedSession: OpenMusicEventSelectedOAuthSessionClient,
        authFailureMessage: Shared<ErrorMessage?>
    ) -> ErrorInterceptor {
        ErrorInterceptor { failedRequest, failureCode, _, failureBody, retry in
            guard failureCode == .unauthorized,
                  let failureBody
            else { return nil }

            @Dependency(\.jsonDecoder) var jsonDecoder
            let error: String
            do {
                error = try jsonDecoder.decode(
                    OAuth.DPOP.ErrorBody.self,
                    from: failureBody
                )
                .error
            } catch {
                return nil
            }

            guard error == "invalid_token" else { return nil }

            @Dependency(OAuth.Client.self) var client

            do {
                let refreshed = try await client.refreshToken(
                    selectedSession.current() ?? .placeholder
                )
                await selectedSession.update {
                    $0?.accessToken = refreshed.accessToken
                    $0?.refreshToken = refreshed.refreshToken
                    $0?.scope = refreshed.scope
                }

                return try await retry(failedRequest)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if isTerminalAuthenticatedSessionFailure(error) {
                    await selectedSession.update { $0 = nil }
                    authFailureMessage.withLock {
                        $0 = openMusicEventTerminalAuthErrorMessage(error)
                    }
                    await saveOpenMusicEventSharedValue(authFailureMessage)
                    throw OAuth.TerminalAuthenticatedSessionFailure()
                }
                throw error
            }
        }
    }
}

private func saveOpenMusicEventSharedValue<Value>(_ value: Shared<Value>) async {
    do {
        try await value.save()
    } catch {
        reportIssue(error)
    }
}

private func openMusicEventTerminalAuthErrorMessage(_ error: Error) -> ErrorMessage {
    let subtitle = TCATProtoLocalizedStringResource(
        stringLiteral: error.localizedDescription
    )
    return ErrorMessage(
        message: "Session Expired",
        subtitle: subtitle,
        originalError: error
    )
}
