#if canImport(SwiftUI) || os(Android)
import ATProto
import ATProtoOAuth
import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventComponents
import Sharing
#if os(Android) || SKIP_BRIDGE
import SkipSwiftUI
#else
import SwiftUI
#endif
import TCATProtoAuthentication

#if SKIP_BRIDGE
private typealias _AuthenticationForm = SkipSwiftUI.Form
#else
private typealias _AuthenticationForm = SwiftUI.Form
#endif

public typealias AuthenticationCoordinator = OAuthAuthenticationCoordinator
public typealias AuthorizationFlowSheetView = OpenMusicEventAuthorizationFlowSheetView

public extension OAuthAuthenticationCoordinator.State {
    init() {
        self.init(storage: OpenMusicEventOAuth.storage)
    }
}

public struct OpenMusicEventAuthorizationView<
    AuthorizedContent: FeatureProtocol,
    Content: View
>: View {
    let content: (StoreOf<AuthorizedContent>) -> Content
    let store: StoreOf<OAuthAuthorization<AuthorizedContent>>

    public init(
        store: StoreOf<OAuthAuthorization<AuthorizedContent>>,
        @ViewBuilder content: @escaping (StoreOf<AuthorizedContent>) -> Content
    ) {
        self.store = store
        self.content = content
    }

    public var body: some View {
        OAuthAuthorizationView(
            store: store,
            authorizationContent: {
                OpenMusicEventAuthorizationFlowSheetView(store: $0)
            },
            content: content
        )
    }
}

public struct AuthenticationCoordinatorView<Content: View>: View {
    let store: StoreOf<AuthenticationCoordinator>
    let isPresentationEnabled: Bool
    let content: Content

    public init(
        store: StoreOf<AuthenticationCoordinator>,
        isPresentationEnabled: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.store = store
        self.isPresentationEnabled = isPresentationEnabled
        self.content = content()
    }

    public var body: some View {
        if isPresentationEnabled {
            OAuthAuthenticationCoordinatorView(
                store: store,
                authorizationContent: { authorizationStore in
                    OpenMusicEventAuthorizationFlowSheetView(store: authorizationStore)
                },
                content: { content }
            )
        } else {
            content
        }
    }
}

public struct OpenMusicEventAuthorizationFlowSheetView: View {
    @Bindable var store: StoreOf<AuthorizationFlow>

    public init(store: StoreOf<AuthorizationFlow>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            OpenMusicEventAuthorizationFormView(store: store)
        }
    }
}

public struct OpenMusicEventAuthorizationFormView: View {
    @Bindable var store: StoreOf<AuthorizationFlow>
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails
    @State var signInActorSearchFailures: [PredictiveSearchFailure] = []
    @State var signInActorSearchIsLoading = false
    @State var signInActorSearchRequest: SignInActorSearchRequest?
    @State var signInActorSearchResults: [ActorIdentity] = []

    struct SignInActorSearchRequest: Equatable {
        let includingExactLookup: Bool
        let query: String
    }

    public init(store: StoreOf<AuthorizationFlow>) {
        self.store = store
    }

    public var body: some View {
        _AuthenticationForm {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Atmosphere account")
                        .font(.headline)
                    Text(
                        showsTechnicalDetails
                            ? "Use one portable social account across Open Music Event and other AT Protocol apps."
                            : "Use one portable social account across Open Music Event and other compatible apps."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Account") {
                Picker("Action", selection: selectedAccountAction) {
                    ForEach(AccountAction.allCases) { action in
                        Text(action.title)
                            .tag(action)
                    }
                }
                .pickerStyle(.segmented)
            }

            switch store.mode {
            case .signIn:
                Section {
                    Text(AccountAction.signIn.helperText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    TextField(
                        "Search profiles",
                        text: Binding(
                            get: { store.loginHint },
                            set: { store.send(.loginHintChanged($0)) }
                        ),
                        prompt: Text("name.atmo.social")
                    )
                    #if os(iOS) || os(macOS)
                    .textContentType(.username)
                    #endif
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .onSubmit {
                        requestSignInActorSearch(includingExactLookup: true)
                    }
                    .onChange(of: store.loginHint) { _, query in
                        requestSignInActorSearch(
                            query: query,
                            includingExactLookup: false
                        )
                    }

                    if signInActorSearchIsLoading {
                        ProgressView()
                    }

                    ForEach(
                        signInActorSearchResults.filter {
                            showsTechnicalDetails || $0.handle != nil
                        }
                    ) { identity in
                        Button {
                            selectSignInActor(identity)
                        } label: {
                            AccountActorIdentityRow(identity: identity)
                        }
                        .buttonStyle(.plain)
                    }

                    if store.loginHint.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
                        Button(
                            showsTechnicalDetails
                                ? "Look up exact handle or DID"
                                : "Look up exact account"
                        ) {
                            requestSignInActorSearch(includingExactLookup: true)
                        }
                        .disabled(signInActorSearchIsLoading)
                    }

                    ForEach(signInActorSearchFailures, id: \.sourceID) { failure in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(failure.title)
                            Text(failure.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(showsTechnicalDetails ? "ATProto Identity" : "Account")
                } footer: {
                    Text("Already use Bluesky? Your Bluesky handle works too.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

            case .signUp:
                Section {
                    Text(AccountAction.signUp.helperText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Account provider")
                }

                authorizationSignUpServerForm
            }

            if let error = store.error {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        authorizationErrorText(error.message)
                            .font(.headline)
                        if let subtitle = error.subtitle {
                            authorizationErrorText(subtitle)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .onChange(of: store.mode) { _, mode in
            if mode == .signUp {
                resetSignInActorSearch()
            }
        }
        .task(id: signInActorSearchRequest) {
            guard let request = signInActorSearchRequest else { return }
            signInActorSearchIsLoading = true
            let response = await (
                request.includingExactLookup
                    ? Account.exactActorIdentitySearch
                    : Account.signInActorTypeaheadSearch
            )
            .search(request.query)
            guard !Task.isCancelled else { return }
            signInActorSearchIsLoading = false
            signInActorSearchFailures = response.failures
            signInActorSearchResults = response.results
        }
        #if os(macOS)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        #endif
        .navigationTitle("Account")
        .safeEdgeExpansion(edge: .bottom) {
            authorizationSubmitButton
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    store.send(.cancel)
                } label: {
                    Label("Close", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                }
            }
        }
    }

    func authorizationErrorText(
        _ resource: TCATProtoLocalizedStringResource
    ) -> Text {
        #if SKIP_BRIDGE && !os(Android)
        Text(String(localized: resource))
        #else
        Text(resource)
        #endif
    }

    private func requestSignInActorSearch(
        query: String? = nil,
        includingExactLookup: Bool
    ) {
        let query = (query ?? store.loginHint)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            resetSignInActorSearch()
            return
        }
        signInActorSearchRequest = SignInActorSearchRequest(
            includingExactLookup: includingExactLookup,
            query: query
        )
    }

    private func resetSignInActorSearch() {
        signInActorSearchFailures = []
        signInActorSearchIsLoading = false
        signInActorSearchRequest = nil
        signInActorSearchResults = []
    }

    private func selectSignInActor(_ identity: ActorIdentity) {
        guard showsTechnicalDetails || identity.handle != nil else { return }
        store.send(.loginHintChanged(identity.handle?.rawValue ?? identity.did.description))
        resetSignInActorSearch()
        store.send(.submit)
    }

    @ViewBuilder
    private var authorizationSignUpServerForm: some View {
        Section("Provider") {
            ForEach(store.signUpServerConfiguration.options) { option in
                Button {
                    store.send(.signUpServerOptionTapped(option.id))
                } label: {
                    AccountSignUpServerOptionRow(
                        option: option,
                        isSelected: store.selectedSignUpServerOptionID == option.id
                    )
                }
                .buttonStyle(.plain)
                .disabled(option.isComingSoon)
            }

            if store.signUpServerConfiguration.allowsCustomServerHost {
                Button {
                    store.send(.customSignUpServerOptionTapped)
                } label: {
                    AccountCustomSignUpServerOptionRow(
                        isSelected: store.usesCustomSignUpServerHost
                    )
                }
                .buttonStyle(.plain)
            }
        }

        if store.showsSignUpServerTextField {
            Section("Server") {
                TextField(
                    "Server Host",
                    text: Binding(
                        get: { store.serverHost },
                        set: { store.send(.serverHostChanged($0)) }
                    )
                )
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
            }
        }
    }

    private var authorizationSubmitButton: some View {
        Button {
            store.send(.submit)
        } label: {
            if store.isLoading {
                Label(selectedAccountAction.wrappedValue.progressTitle, systemImage: "hourglass")
            } else {
                Label(
                    selectedAccountAction.wrappedValue.title,
                    systemImage: selectedAccountAction.wrappedValue.systemImage
                )
            }
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.borderedProminent)
        .accountExtraLargeControlSize()
        .disabled(store.isSubmitDisabled)
    }

    private var selectedAccountAction: Binding<AccountAction> {
        Binding {
            AccountAction(mode: store.mode)
        } set: { action in
            store.send(.modeChanged(action.mode))
        }
    }
}

private enum AccountAction: String, CaseIterable, Identifiable {
    case signIn
    case signUp

    var id: Self { self }

    init(mode: AuthorizationPresentationMode) {
        switch mode {
        case .signIn:
            self = .signIn
        case .signUp:
            self = .signUp
        }
    }

    var mode: AuthorizationPresentationMode {
        switch self {
        case .signIn:
            .signIn
        case .signUp:
            .signUp
        }
    }

    var helperText: String {
        switch self {
        case .signIn:
            "Sign in with your handle, like name.atmo.social or your own domain."
        case .signUp:
            "Choose a provider to create your Atmosphere account. Your provider hosts your account and data, and you can move later."
        }
    }

    var progressTitle: String {
        switch self {
        case .signIn:
            "Signing In..."
        case .signUp:
            "Creating Account..."
        }
    }

    var systemImage: String {
        switch self {
        case .signIn:
            "person.crop.circle.badge.checkmark"
        case .signUp:
            "person.crop.circle.badge.plus"
        }
    }

    var title: String {
        switch self {
        case .signIn:
            "Sign In"
        case .signUp:
            "Create Account"
        }
    }
}

public extension OpenMusicEventOAuth {
    static func authorizationFlowState(
        for request: AuthorizationPresentationRequest,
        session: OAuth.Session?,
        sessionStore: Shared<OAuth.SessionStore>
    ) -> AuthorizationFlow.State {
        @Dependency(\.openMusicEventSignUpServerConfiguration)
        var signUpServerConfiguration
        return OAuthAuthenticationCoordinator.authorizationFlowState(
            for: request.openMusicEventDefaultingSignUpServerConfiguration(
                signUpServerConfiguration
            ),
            session: session,
            sessionStore: sessionStore
        )
    }

    static func authorizationFlowState(
        for request: AuthorizationPresentationRequest
    ) -> AuthorizationFlow.State {
        authorizationFlowState(
            for: request,
            session: session.wrappedValue,
            sessionStore: sessionStore
        )
    }
}
#endif
