import ComposableArchitecture2
import Dependencies
import ErrorHandling
import Foundation
import OpenMusicEventAppEventViewer
import OpenMusicEventAuthentication
import OpenMusicEventDatabase
import OpenMusicEventSource
import OpenMusicEventSourceClone
import OpenMusicEventSourceEditing
import OpenMusicEventViewers
import OpenMusicEventWhiteLabel
import SQLiteData
import SwiftUI

@Feature
public struct WhiteLabelRoot {
    public init() {}

    public struct State {
        public init(configuration: WhiteLabelAppConfiguration) {
            self.configuration = configuration
        }

        public var account = Spawn(Account.State())
        public var authoringMode: Authoring.Mode = .attendee
        public var authoringSubject: Authoring.Subject?
        public var configuration: WhiteLabelAppConfiguration
        public var errorMessage: String?
        public var isAccountManagementPresented = false
        public var isAuthoringAuthorizationInFlight = false
        public var isLoading = false
        public var loadingPhase: LoadingPhase = .idle
        public var organizationRoot: Spawn<OrganizationRoot>?
        public var organizerID: OMERecord.Organizer.ID?
        public var teamWorkspaceDetail: Spawn<TeamWorkspaceDetail>?

        public var showsAuthoringControls: Bool {
            authoringMode.isAuthoring
        }

        public enum LoadingPhase: Equatable, Sendable {
            case idle
            case preparing
            case resolvingOrganizer
            case locatingSource
            case importingSource
            case openingEvent
        }
    }

    public enum Action {
        case accountManagementButtonTapped
        case accountManagementDoneButtonTapped
        case enterAuthoringAuthorizationFailed(Authoring.Subject)
        case enterAuthoringAuthorized(Authoring.Subject, Authoring.Scope)
        case enterAuthoringButtonTapped
        case loadDataSucceeded(LoadedRoot)
        case retryButtonTapped
        case task
    }

    public struct LoadedRoot: Equatable, Sendable {
        public init(
            organizerID: OMERecord.Organizer.ID,
            sourceBaselineIDs: [SourceBaselineRecord.ID]
        ) {
            self.organizerID = organizerID
            self.sourceBaselineIDs = sourceBaselineIDs
        }

        public var organizerID: OMERecord.Organizer.ID
        public var sourceBaselineIDs: [SourceBaselineRecord.ID]
    }

    @Dependency(\.authoringPolicy) var authoringPolicy
    @Dependency(\.defaultDatabase) var database
    @Dependency(\.openMusicEventStoredAuthentication) var storedAuthentication
    @Dependency(\.whiteLabelDevelopmentSourceOverride) var developmentSourceOverride
    @Dependency(\.whiteLabelOrganizerIdentityResolver) var identityResolver
    @Dependency(\.whiteLabelSourceImport) var sourceImport
    @Dependency(\.whiteLabelSourceRegistry) var sourceRegistry

    public var body: some Feature {
//        let _ = Self._logChanges()

        Update { state, action in
            switch action {
            case .accountManagementButtonTapped:
                state.refreshAuthoringMode()
                state.isAccountManagementPresented = true

            case .accountManagementDoneButtonTapped:
                state.refreshAuthoringMode()
                state.isAccountManagementPresented = false

            case let .enterAuthoringAuthorizationFailed(subject):
                state.isAuthoringAuthorizationInFlight = false
                guard state.authoringSubject == subject else { return }

            case let .enterAuthoringAuthorized(subject, scope):
                state.isAuthoringAuthorizationInFlight = false
                guard state.authoringSubject == subject else { return }
                state.authoringMode = .authoring(scope)

            case .enterAuthoringButtonTapped:
                guard !state.isAuthoringAuthorizationInFlight,
                      let authoringSubject = state.authoringSubject
                else { return }
                state.refreshAuthoringMode()
                guard !state.showsAuthoringControls else { return }

                let authoringPolicy = authoringPolicy
                state.isAuthoringAuthorizationInFlight = true
                store.addTask {
                    let scope = await store.withErrorHandling(
                        fallbackMessage: .authoringAuthorizationFailed,
                        operation: .authoringAuthorization
                    ) {
                        try await authoringPolicy.authorize(
                            Authoring.Request(
                                subject: authoringSubject,
                                feature: .workspace,
                                action: .enterAuthoring
                            )
                        )
                    }
                    guard let scope else {
                        try store.send(.enterAuthoringAuthorizationFailed(authoringSubject))
                        return
                    }
                    try store.send(.enterAuthoringAuthorized(authoringSubject, scope))
                }

            case let .loadDataSucceeded(loadedRoot):
                state.errorMessage = nil
                state.isLoading = false
                state.loadingPhase = .idle
                state.organizerID = loadedRoot.organizerID
                state.setLoadedRoot(
                    organizerID: loadedRoot.organizerID,
                    sourceBaselineIDs: loadedRoot.sourceBaselineIDs
                )
                state.refreshAuthoringMode()

            case .retryButtonTapped:
                guard !state.isLoading else { return }
                state.errorMessage = nil
                state.isLoading = true
                state.loadingPhase = .preparing

                loadData(configuration: state.configuration)

            case .task:
                guard !state.isLoading else { return }
                state.isLoading = true
                state.loadingPhase = .preparing
                loadData(configuration: state.configuration)

            }
        }
        .spawn(\.account) {
            Account()
        }
        .ifLet(\.organizationRoot) {
            OrganizationRoot()
        }
        .ifLet(\.teamWorkspaceDetail) {
            TeamWorkspaceDetail()
        }
        .onMount { state in
            guard !state.isLoading else { return }
            state.isLoading = true
            state.loadingPhase = .preparing
            loadData(configuration: state.configuration)
        }
    }


    func loadData(configuration: WhiteLabelAppConfiguration) {
        let database = self.database
        let developmentSourceOverride = self.developmentSourceOverride
        let identityResolver = self.identityResolver
        let sourceImport = self.sourceImport
        let sourceRegistry = self.sourceRegistry
        let storedAuthentication = self.storedAuthentication
        store.addTask {
            let _: Void? = await store.withErrorHandling(
                fallbackMessage: .storedAuthenticationLoadFailed,
                operation: .storedAuthenticationLoad
            ) {
                try await storedAuthentication.enforceFreshness()
            }

            let loadedRoot = await store.withErrorHandling(
                fallbackMessage: .whiteLabelLoadFailed,
                operation: .whiteLabelLoad
            ) {
                try store.modify {
                    $0.loadingPhase = Self.initialLoadingPhase(
                        configuration,
                        developmentSourceOverride: developmentSourceOverride
                    )
                }
                let resolvedSource = try await Self.resolveSource(
                    configuration,
                    developmentSourceOverride: developmentSourceOverride,
                    identityResolver: identityResolver,
                    sourceRegistry: sourceRegistry
                )
                try store.modify {
                    $0.loadingPhase = .importingSource
                }
                _ = try await sourceImport.ensureImported(
                    resolvedSource.organizerID,
                    resolvedSource.descriptor
                )
                try store.modify {
                    $0.loadingPhase = .openingEvent
                }
                let sourceBaselineIDs = try await Self.sourceBaselineIDs(
                    for: resolvedSource.organizerID,
                    in: database
                )
                return LoadedRoot(
                    organizerID: resolvedSource.organizerID,
                    sourceBaselineIDs: sourceBaselineIDs
                )
            } cleanup: {
                $0.isLoading = false
                $0.loadingPhase = .idle
            } parseError: {
                SourceImportError.parser
            }

            if let loadedRoot {
                try store.send(.loadDataSucceeded(loadedRoot))
                return
            }

            let cachedOrganizerID = try? await Self.cachedOrganizerID(
                for: configuration,
                database: database,
                developmentSourceOverride: developmentSourceOverride,
                identityResolver: identityResolver
            )
            let sourceBaselineIDs: [SourceBaselineRecord.ID]
            if let cachedOrganizerID {
                sourceBaselineIDs = (try? await Self.sourceBaselineIDs(
                    for: cachedOrganizerID,
                    in: database
                )) ?? []
            } else {
                sourceBaselineIDs = []
            }
            try store.modify {
                $0.isLoading = false
                $0.loadingPhase = .idle
                if let cachedOrganizerID {
                    $0.errorMessage = "Unable to refresh \(configuration.brand.displayName)."
                    $0.organizerID = cachedOrganizerID
                    $0.setLoadedRoot(
                        organizerID: cachedOrganizerID,
                        sourceBaselineIDs: sourceBaselineIDs
                    )
                    $0.refreshAuthoringMode()
                } else {
                    $0.errorMessage = UserFacingText.whiteLabelLoadFailed.localizedString
                }
            }
        }
    }

    private struct ResolvedSource {
        var organizerID: OMERecord.Organizer.ID
        var descriptor: WhiteLabelSourceDescriptor
    }

    private static func initialLoadingPhase(
        _ configuration: WhiteLabelAppConfiguration,
        developmentSourceOverride: WhiteLabelDevelopmentSourceOverride?
    ) -> State.LoadingPhase {
        if developmentSourceOverride != nil || configuration.organizerID != nil {
            return .locatingSource
        }
        return .resolvingOrganizer
    }

    private static func resolveSource(
        _ configuration: WhiteLabelAppConfiguration,
        developmentSourceOverride: WhiteLabelDevelopmentSourceOverride?,
        identityResolver: WhiteLabelOrganizerIdentityResolverClient,
        sourceRegistry: WhiteLabelSourceRegistryClient
    ) async throws -> ResolvedSource {
        let organizerID: OMERecord.Organizer.ID
        let descriptor: WhiteLabelSourceDescriptor

        if let override = developmentSourceOverride {
            guard developmentSourceOverridesAreEnabled else {
                throw WhiteLabelError.developmentSourceOverrideUnavailable
            }
            organizerID = override.organizerID
            descriptor = override.source
        } else if let configuredOrganizerID = configuration.organizerID {
            organizerID = configuredOrganizerID
            descriptor = try await sourceRegistry.source(configuredOrganizerID)
            try descriptor.validateProductionUse(organizerID: organizerID)
        } else if let handle = configuration.handle {
            organizerID = try await identityResolver.resolve(handle)
            descriptor = try await sourceRegistry.source(organizerID)
            try descriptor.validateProductionUse(organizerID: organizerID)
        } else {
            throw WhiteLabelError.missingOrganizerIdentity(configuration.brand.displayName)
        }

        return ResolvedSource(organizerID: organizerID, descriptor: descriptor)
    }

    private static func cachedOrganizerID(
        for configuration: WhiteLabelAppConfiguration,
        database: any DatabaseReader,
        developmentSourceOverride: WhiteLabelDevelopmentSourceOverride?,
        identityResolver: WhiteLabelOrganizerIdentityResolverClient
    ) async throws -> OMERecord.Organizer.ID? {
        let organizerID: OMERecord.Organizer.ID
        if let override = developmentSourceOverride {
            organizerID = override.organizerID
        } else if let configuredOrganizerID = configuration.organizerID {
            organizerID = configuredOrganizerID
        } else if let handle = configuration.handle {
            organizerID = try await identityResolver.resolve(handle)
        } else {
            return nil
        }
        return try await organizerExists(organizerID, in: database) ? organizerID : nil
    }

    private static func sourceBaselineIDs(
        for organizerID: OMERecord.Organizer.ID,
        in database: any DatabaseReader
    ) async throws -> [SourceBaselineRecord.ID] {
        try await database.read { db in
            let provenanceRecords = try EventSourceProvenanceRecord
                .fetchAll(db)
                .filter { $0.id.organizerID == organizerID }
            var seen: Set<SourceBaselineRecord.ID> = []
            return provenanceRecords.compactMap(\.sourceBaselineID).filter {
                seen.insert($0).inserted
            }
        }
    }

    private static var developmentSourceOverridesAreEnabled: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    private static func organizerExists(
        _ organizerID: OMERecord.Organizer.ID,
        in database: any DatabaseReader
    ) async throws -> Bool {
        try await database.read { db in
            let eventCount = try OMERecord.Event
                .where { $0.id.organizerID.eq(organizerID) }
                .fetchCount(db)
            guard eventCount == 0 else { return true }

            return try OMERecord.Organizer
                .where { $0.id.eq(organizerID) }
                .fetchOne(db) != nil
        }
    }
}

public struct WhiteLabelRootView: View {
    public init(store: StoreOf<WhiteLabelRoot>) {
        self.store = store
    }

    @Bindable var store: StoreOf<WhiteLabelRoot>

    public var body: some View {
        let accountStore = store.spawn(\.account)

        Group {
            if let teamWorkspaceDetailStore = store.spawn(\.teamWorkspaceDetail) {
                NavigationStack {
                    TeamWorkspaceDetailView(
                        store: teamWorkspaceDetailStore,
                        showsAuthoringControls: store.showsAuthoringControls
                    )
                    .whiteLabelRootActionsToolbar(store: store)
                }
            } else if let organizationRootStore = store.spawn(\.organizationRoot) {
                OrganizationRootView(
                    store: organizationRootStore,
                    whiteLabelRootStore: store
                )
            } else {
                NavigationStack {
                    LoadingView(store: store)
                        .whiteLabelRootActionsToolbar(store: store)
                }
            }
        }
        .sheet(isPresented: $store.isAccountManagementPresented) {
            WhiteLabelRootAccountManagementView(
                store: store,
                accountStore: accountStore
            )
        }
    }

    struct LoadingView: View {
        let store: StoreOf<WhiteLabelRoot>

        var body: some View {
            List {
                Header(configuration: store.configuration)

                if store.isLoading {
                    LoadingStatus(
                        displayName: store.configuration.brand.displayName,
                        phase: store.loadingPhase
                    )
                }

                if let errorMessage = store.errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Retry") {
                            store.send(.retryButtonTapped)
                        }
                    }
                }
            }
            .navigationTitle(store.configuration.brand.displayName)
        }
    }

    struct Header: View {
        let configuration: WhiteLabelAppConfiguration

        var body: some View {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: configuration.brand.systemImage)
                        .font(.title2)
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading) {
                        Text(configuration.brand.displayName)
                            .font(.headline)
                        if let handle = configuration.handle {
                            Text(handle)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    struct LoadingStatus: View {
        let displayName: String
        let phase: WhiteLabelRoot.State.LoadingPhase

        var body: some View {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    ProgressView()
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(phase.title(displayName: displayName))
                            .font(.headline)
                        Text(phase.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

struct WhiteLabelRootActionsMenu: View {
    let store: StoreOf<WhiteLabelRoot>

    var body: some View {
        Menu {
            if store.authoringSubject != nil,
               !store.showsAuthoringControls {
                Button {
                    store.send(.enterAuthoringButtonTapped)
                } label: {
                    Label(
                        store.isAuthoringAuthorizationInFlight
                            ? "Entering Authoring"
                            : "Enter Authoring",
                        systemImage: "square.and.pencil"
                    )
                }
                .disabled(store.isAuthoringAuthorizationInFlight)
            }

            if let teamWorkspaceDetailStore = store.spawn(\.teamWorkspaceDetail),
               store.showsAuthoringControls,
               teamWorkspaceDetailStore.canManageSource {
                Button {
                    teamWorkspaceDetailStore.send(.manageSourceButtonTapped)
                } label: {
                    Label(
                        teamWorkspaceDetailStore.isPreparingTeamWorkspaceEditor
                            ? "Preparing Workspace"
                            : "Workspace",
                        systemImage: EventFeature.workspace.systemImage
                    )
                }
                .disabled(teamWorkspaceDetailStore.isPreparingTeamWorkspaceEditor)
            }

            Button {
                store.send(.accountManagementButtonTapped)
            } label: {
                Label("Account", systemImage: "person.crop.circle")
            }
        } label: {
            Label("Actions", systemImage: "gearshape")
                .labelStyle(.iconOnly)
        }
    }
}

struct WhiteLabelRootAccountManagementView: View {
    let store: StoreOf<WhiteLabelRoot>
    let accountStore: StoreOf<Account>

    var body: some View {
        NavigationStack {
            Form {
                AccountView(store: accountStore)
            }
            #if os(macOS)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            #endif
            .navigationTitle("Account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        store.send(.accountManagementDoneButtonTapped)
                    } label: {
                        Label("Done", systemImage: "checkmark")
                            .labelStyle(.iconOnly)
                    }
                }
            }
        }
        .accountAuthenticationSheet(store: accountStore)
    }
}

extension View {
    func whiteLabelRootActionsToolbar(store: StoreOf<WhiteLabelRoot>) -> some View {
        whiteLabelRootActionsToolbar(store: Optional(store))
    }

    func whiteLabelRootActionsToolbar(store: StoreOf<WhiteLabelRoot>?) -> some View {
        toolbar {
            if let store {
                ToolbarItem(placement: .primaryAction) {
                    WhiteLabelRootActionsMenu(store: store)
                }
            }
        }
    }
}

private extension WhiteLabelRoot.State {
    mutating func refreshAuthoringMode() {
        @Dependency(\.authoringPolicy) var authoringPolicy

        guard let authoringSubject else {
            authoringMode = .attendee
            account.state.authRequirement = OpenMusicEventOAuth.baseAuthRequirement
            return
        }

        authoringMode = (try? authoringPolicy.mode(authoringSubject)) ?? .attendee
        account.state.authRequirement = (
            try? authoringPolicy.authenticate(authoringSubject)
        ) ?? OpenMusicEventOAuth.baseAuthRequirement
    }

    mutating func setLoadedRoot(
        organizerID: OMERecord.Organizer.ID,
        sourceBaselineIDs: [SourceBaselineRecord.ID]
    ) {
        if sourceBaselineIDs.count == 1, let sourceBaselineID = sourceBaselineIDs.first {
            authoringSubject = .sourceBaseline(sourceBaselineID)
            organizationRoot = nil
            if teamWorkspaceDetail?.state.sourceBaselineID != sourceBaselineID {
                teamWorkspaceDetail = Spawn(TeamWorkspaceDetail.State(sourceBaselineID: sourceBaselineID))
            }
        } else {
            authoringSubject = nil
            authoringMode = .attendee
            teamWorkspaceDetail = nil
            if organizationRoot?.state.organizerID != organizerID {
                organizationRoot = Spawn(OrganizationRoot.State(organizerID: organizerID))
            }
        }
    }
}

private extension WhiteLabelRoot.State.LoadingPhase {
    func title(displayName: String) -> String {
        switch self {
        case .idle:
            "Ready"
        case .preparing:
            "Preparing \(displayName)"
        case .resolvingOrganizer:
            "Finding \(displayName)"
        case .locatingSource:
            "Finding \(displayName) source"
        case .importingSource:
            "Downloading \(displayName) source"
        case .openingEvent:
            "Opening \(displayName)"
        }
    }

    var detail: String {
        switch self {
        case .idle:
            "The event source is ready."
        case .preparing:
            "Checking the local event cache."
        case .resolvingOrganizer:
            "Resolving the organizer account."
        case .locatingSource:
            "Looking up the configured event repository."
        case .importingSource:
            "Downloading and validating the event data."
        case .openingEvent:
            "Preparing the event workspace."
        }
    }
}

private extension UserFacingText {
    static let whiteLabelLoadFailed = Self(
        "Unable to load event source.",
        fallback: "Unable to load event source."
    )
}

private extension ErrorOperation {
    static let whiteLabelLoad = Self("white-label.load")
}

private extension WhiteLabelSourceDescriptor {
    func validateProductionUse(organizerID: OMERecord.Organizer.ID) throws {
        guard case let .source(source) = reference else { return }
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedSource.looksLikeLocalPathForWhiteLabelSource {
            throw WhiteLabelError.directSourceRequiresDevelopmentOverride(organizerID)
        }

        if case .local = try SourceRepositoryLocation(parsing: trimmedSource) {
            throw WhiteLabelError.directSourceRequiresDevelopmentOverride(organizerID)
        }
    }
}

private extension String {
    var looksLikeLocalPathForWhiteLabelSource: Bool {
        hasPrefix("/") || hasPrefix(".") || hasPrefix("~")
    }
}
