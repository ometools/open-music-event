import ATProtoOAuth
import ComposableArchitecture2
import Dependencies
import Foundation
import Sharing
import SwiftUI
import TCATProtoAuthentication

@Feature
public struct Account {
    public init() {}

    public struct State: Equatable {
        public init(
            authFailureMessage: Shared<ErrorMessage?> = OpenMusicEventOAuth.authFailureMessage,
            session: Shared<OAuth.Session?> = OpenMusicEventOAuth.session,
            sessionStore: Shared<OAuth.SessionStore> = OpenMusicEventOAuth.sessionStore
        ) {
            self._authFailureMessage = authFailureMessage
            self._session = session
            self._sessionStore = sessionStore
        }

        public var errorMessage: String?
        public var isLoginInProgress = false

        @Shared public var authFailureMessage: ErrorMessage?
        @Shared public var session: OAuth.Session?
        @Shared public var sessionStore: OAuth.SessionStore

        public var accountIDDescription: String? {
            session?.accountID.rawValue.description
        }
    }

    public enum LoginFailure: Error, Equatable, Sendable {
        case cancelled
        case failed(String)
    }

    public enum Action {
        case loginButtonTapped
        case loginResponse(Result<Void, LoginFailure>)
        case logoutButtonTapped
    }

    @Dependency(\.openMusicEventAuthorizationRequests) var authorizationRequests

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .loginButtonTapped:
                state.errorMessage = nil
                guard state.session == nil else { return }
                state.isLoginInProgress = true
                store.addTask {
                    do {
                        try await authorizationRequests
                            .broker()
                            .authorize(OpenMusicEventOAuth.baseAuthRequirement)
                        try store.send(.loginResponse(.success(())))
                    } catch is CancellationError {
                        try store.send(.loginResponse(.failure(.cancelled)))
                    } catch {
                        try store.send(.loginResponse(.failure(.failed(error.localizedDescription))))
                    }
                }

            case .loginResponse(.success):
                state.isLoginInProgress = false
                state.errorMessage = nil
                state.$session.withLock {
                    $0 = state.sessionStore.selectedSession
                }

            case .loginResponse(.failure(.cancelled)):
                state.isLoginInProgress = false

            case .loginResponse(.failure(.failed)):
                state.isLoginInProgress = false
                state.errorMessage = "Sign in failed."

            case .logoutButtonTapped:
                state.errorMessage = nil
                state.isLoginInProgress = false
                state.$authFailureMessage.withLock { $0 = nil }
                state.$session.withLock { $0 = nil }
                state.$sessionStore.withLock { $0 = OAuth.SessionStore() }
                store.addTask {
                    await authorizationRequests.cancel()
                }
            }
        }
        .onMount { state in
            guard state.session == nil else { return }
            state.$session.withLock {
                $0 = state.sessionStore.selectedSession
            }
        }
    }
}

public struct AccountView: View {
    public init(store: StoreOf<Account>) {
        self.store = store
    }

    @Bindable var store: StoreOf<Account>

    public var body: some View {
        Section("Account") {
            if let accountID = store.accountIDDescription {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Signed in")
                    Text(accountID)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button(role: .destructive) {
                    store.send(.logoutButtonTapped)
                } label: {
                    Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } else {
                if let errorMessage = store.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }

                Button {
                    store.send(.loginButtonTapped)
                } label: {
                    if store.isLoginInProgress {
                        Label("Signing In...", systemImage: "hourglass")
                    } else {
                        Label("Log In", systemImage: "person.crop.circle.badge.checkmark")
                    }
                }
                .disabled(store.isLoginInProgress)
            }
        }
    }
}
