import ATProtoOAuth
import ComposableArchitecture2
import Dependencies
import Foundation
import Sharing
import SwiftUI
import TCATProtoAuthentication

@Feature
public struct AuthenticationCoordinator {
    public init() {}

    public struct State {
        public init() {
            self._authFailureMessage = OpenMusicEventOAuth.authFailureMessage
            self._session = OpenMusicEventOAuth.session
            self._sessionStore = OpenMusicEventOAuth.sessionStore
        }

        public var authorization: AuthorizationFlow.State?

        @Shared public var authFailureMessage: ErrorMessage?
        @Shared public var session: OAuth.Session?
        @Shared public var sessionStore: OAuth.SessionStore
        @DebugSnapshotIgnored
        public var routedAuthorizationRequest: AuthorizationPresentationRequest?
    }

    @CasePathable
    public enum Action {
        case authorization(AuthorizationFlow.Action)
        case authorizationPresentationRequested(AuthorizationPresentationRequest)
        case authorizationRequestChanged(AuthorizationRequestCenter.Request?)
        case handleOpenURL(URL)
        case resetAuthentication
    }

    @Dependency(\.openMusicEventAuthorizationRequests) var authorizationRequests
    @StoreTaskID var authorizationRequestsTask

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .authorization(.delegate(.succeeded)):
                state.$session.withLock {
                    $0 = state.sessionStore.selectedSession
                }
                let routedRequest = state.routedAuthorizationRequest
                state.routedAuthorizationRequest = nil
                state.authorization = nil
                store.addTask {
                    if let routedRequest {
                        await routedRequest.responder.succeed()
                    } else {
                        await authorizationRequests.succeed()
                    }
                }

            case .authorization(.delegate(.cancelled)):
                let routedRequest = state.routedAuthorizationRequest
                state.routedAuthorizationRequest = nil
                state.authorization = nil
                store.addTask {
                    if let routedRequest {
                        await routedRequest.responder.cancel()
                    } else {
                        await authorizationRequests.cancel()
                    }
                }

            case .authorization(.delegate(.failed(let error))):
                let routedRequest = state.routedAuthorizationRequest
                state.routedAuthorizationRequest = nil
                state.authorization = nil
                store.addTask {
                    if let routedRequest {
                        await routedRequest.responder.fail(error)
                    } else {
                        await authorizationRequests.fail(error)
                    }
                }

            case .authorization:
                break

            case .authorizationPresentationRequested(let request):
                state.routedAuthorizationRequest = request
                state.authorization = OpenMusicEventOAuth.authorizationFlowState(
                    for: request,
                    session: state.session,
                    sessionStore: state.sessionStore
                )

            case .authorizationRequestChanged(.some(let request)):
                state.routedAuthorizationRequest = nil
                state.authorization = OpenMusicEventOAuth.authorizationFlowState(
                    for: AuthorizationPresentationRequest(requirement: request.requirement),
                    session: state.session,
                    sessionStore: state.sessionStore
                )

            case .authorizationRequestChanged(nil):
                state.routedAuthorizationRequest = nil
                state.authorization = nil

            case .handleOpenURL(let url):
                guard OpenMusicEventOAuth.isCallbackURL(url),
                      state.authorization != nil
                else { return }

                store.addTask {
                    try store.send(.authorization(.onOpenCallbackURL(.init(url))))
                }

            case .resetAuthentication:
                state.authorization = nil
                let routedRequest = state.routedAuthorizationRequest
                state.routedAuthorizationRequest = nil
                state.$session.withLock { $0 = nil }
                state.$sessionStore.withLock { $0 = OAuth.SessionStore() }
                state.$authFailureMessage.withLock { $0 = nil }
                store.addTask {
                    if let routedRequest {
                        await routedRequest.responder.cancel()
                    } else {
                        await authorizationRequests.cancel()
                    }
                }
            }
        }
        .onMount { state in
            if let session = state.session, state.sessionStore.selectedSession == nil {
                state.$sessionStore.withLock {
                    $0.upsert(session)
                }
            }
            state.$session.withLock {
                $0 = state.sessionStore.selectedSession
            }

            store.addTask(id: authorizationRequestsTask) {
                var hasPresentedRequest = false
                for await request in await authorizationRequests.requests() {
                    if request != nil {
                        hasPresentedRequest = true
                    }
                    guard hasPresentedRequest else { continue }
                    try store.send(.authorizationRequestChanged(request))
                }
            }
        }
        .onChange(of: store.session) { _, session, state in
            guard let session else { return }
            state.$sessionStore.withLock {
                $0.upsert(session)
            }
        }
        .ifLet(\.authorization, action: \.authorization) {
            AuthorizationFlow(sessionStore: store.$sessionStore)
        }
    }
}

public struct AuthenticationCoordinatorView<Content: View>: View {
    @Bindable var store: StoreOf<AuthenticationCoordinator>
    let content: Content

    public init(
        store: StoreOf<AuthenticationCoordinator>,
        @ViewBuilder content: () -> Content
    ) {
        self.store = store
        self.content = content()
    }

    public var body: some View {
        content
            .sheet(item: $store.scope(\.authorization, action: \.authorization)) { authorizationStore in
                AuthorizationFlowSheetView(store: authorizationStore)
            }
    }
}

public struct AuthorizationFlowSheetView: View {
    @Bindable var store: StoreOf<AuthorizationFlow>

    public init(store: StoreOf<AuthorizationFlow>) {
        self.store = store
    }

    public var body: some View {
        OpenMusicEventAuthorizationFlowView(store: store)
    }
}

public struct OpenMusicEventAuthorizationFlowView: View {
    @Bindable var store: StoreOf<AuthorizationFlow>

    public init(store: StoreOf<AuthorizationFlow>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            Form {
                TextField("Handle", text: $store.loginHint)
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif

                if let error = store.error {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(error.message)
                            .font(.headline)
                        if let subtitle = error.subtitle {
                            Text(subtitle)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Button {
                    store.send(.submit)
                } label: {
                    HStack {
                        Spacer()
                        if store.isLoading {
                            ProgressView()
                        } else {
                            Text("Continue")
                        }
                        Spacer()
                    }
                }
                .disabled(store.isLoading)
            }
            .navigationTitle("Sign in")
            .toolbar {
                Button("Cancel") {
                    store.send(.cancel)
                }
            }
        }
    }
}
