import ComposableArchitecture2
import Dependencies
import ErrorHandling
import Foundation
import OpenMusicEventAppEventViewer
import OpenMusicEventAuthentication
import OpenMusicEventComponents
import OpenMusicEventDatabase
import OpenMusicEventSource
import OpenMusicEventSourceClone
import OpenMusicEventSourceEditing
import OpenMusicEventViewers
import OpenMusicEventWhiteLabel
import SQLiteData
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

#if os(Android)
private typealias _SwiftUIForm = SkipSwiftUI.Form
#else
private typealias _SwiftUIForm = SwiftUI.Form
#endif

@Feature
public struct WhiteLabelRoot {
    public init() {}

    public typealias TeamWorkspace = OpenMusicEventWorkspaceAuthoring<TeamWorkspaceDetail>

    public struct State {
        public init(
            configuration: WhiteLabelAppConfiguration,
            loadedRootAtLaunch: LoadedRoot? = nil
        ) {
            self.configuration = configuration
            if let loadedRootAtLaunch {
                organizerID = loadedRootAtLaunch.organizerID
                setLoadedRoot(
                    organizerID: loadedRootAtLaunch.organizerID,
                    sourceBaselineIDs: loadedRootAtLaunch.sourceBaselineIDs
                )
            }
        }

        public var account = Spawn(Account.State())
        public var configuration: WhiteLabelAppConfiguration
        public var errorMessage: String?
        public var loadingPhase: LoadingPhase = .idle
        public var organizationRoot: Spawn<OrganizationRoot>?
        public var organizerID: OMERecord.Organizer.ID?
        public var teamWorkspaceDetail: Spawn<TeamWorkspace>?

        public var showsAuthoringControls: Bool {
            teamWorkspaceDetail?.state.content.authoring.grant?.access.canEditContent == true
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

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.whiteLabelDevelopmentSourceOverride) var developmentSourceOverride
    @Dependency(\.whiteLabelOrganizerIdentityResolver) var identityResolver
    @Dependency(\.whiteLabelSourceImport) var sourceImport
    @Dependency(\.whiteLabelSourceRegistry) var sourceRegistry

    public var body: some Feature {
//        let _ = Self._logChanges()

        Update { state, action in
            switch action {
            case let .loadDataSucceeded(loadedRoot):
                state.errorMessage = nil
                state.loadingPhase = .idle
                state.organizerID = loadedRoot.organizerID
                state.setLoadedRoot(
                    organizerID: loadedRoot.organizerID,
                    sourceBaselineIDs: loadedRoot.sourceBaselineIDs
                )
            case .retryButtonTapped:
                guard state.loadingPhase == .idle else { return }
                state.errorMessage = nil
                state.loadingPhase = .preparing

                loadData(configuration: state.configuration)

            case .task:
                guard state.loadingPhase == .idle else { return }
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
            TeamWorkspace(storage: OpenMusicEventOAuth.storage) {
                OpenMusicEventAuthoringWorkspace {
                    TeamWorkspaceDetail()
                }
            }
            .openMusicEventWorkspaceLifecycle()
        }
        .onMount { state in
            guard state.loadingPhase == .idle else { return }
            #if os(Android)
            guard state.organizerID == nil else { return }
            #endif
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
        store.addTask {
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
                $0.loadingPhase = .idle
                if let cachedOrganizerID {
                    $0.errorMessage = "Unable to refresh \(configuration.brand.displayName)."
                    $0.organizerID = cachedOrganizerID
                    $0.setLoadedRoot(
                        organizerID: cachedOrganizerID,
                        sourceBaselineIDs: sourceBaselineIDs
                    )
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

    static func loadedRootAtLaunch(
        for configuration: WhiteLabelAppConfiguration,
        database: any DatabaseReader
    ) throws -> LoadedRoot? {
        guard let organizerID = configuration.organizerID else { return nil }
        return try database.read { db in
            let eventCount = try OMERecord.Event
                .where { $0.id.organizerID.eq(organizerID) }
                .fetchCount(db)
            guard eventCount > 0 else { return nil }

            let provenanceRecords = try EventSourceProvenanceRecord
                .fetchAll(db)
                .filter { $0.id.organizerID == organizerID }
            var seen: Set<SourceBaselineRecord.ID> = []
            let sourceBaselineIDs = provenanceRecords.compactMap(\.sourceBaselineID).filter {
                seen.insert($0).inserted
            }
            return LoadedRoot(
                organizerID: organizerID,
                sourceBaselineIDs: sourceBaselineIDs
            )
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
            return try OMERecord.Event
                .where { $0.id.organizerID.eq(organizerID) }
                .fetchCount(db)
                > 0
        }
    }
}

public struct WhiteLabelRootView: View {
    public init(store: StoreOf<WhiteLabelRoot>) {
        self.store = store
        self.accountStore = store.spawn(\.account)
    }

    @Bindable var store: StoreOf<WhiteLabelRoot>
    @Bindable var accountStore: StoreOf<Account>

    public var body: some View {
        Group {
            if let authorizationStore = store.spawn(\.teamWorkspaceDetail) {
                #if os(Android)
                let workspaceAuthoringStore = authorizationStore.scope(\.content, action: \.content)
                let authoringStore = workspaceAuthoringStore.scope(
                    \.authoring,
                    action: \.authoring
                )
                let workspaceStore = authoringStore.scope(
                    \.content,
                    action: \.content
                )
                let teamWorkspaceDetailStore = workspaceStore.scope(
                    \.content,
                    action: \.content
                )
                NavigationStack {
                    TeamWorkspaceDetailView(
                        store: teamWorkspaceDetailStore,
                        showsAuthoringControls: authoringStore.grant?.access.canEditContent == true
                    )
                    .openMusicEventWorkspacePhase(workspaceStore.phase)
                    .whiteLabelRootToolbar(store: store)
                }
                #else
                OpenMusicEventAuthorizationView(store: authorizationStore) { workspaceAuthoringStore in
                    let authoringStore = workspaceAuthoringStore.scope(
                        \.authoring,
                        action: \.authoring
                    )
                    let workspaceStore = authoringStore.scope(
                        \.content,
                        action: \.content
                    )
                    let teamWorkspaceDetailStore = workspaceStore.scope(
                        \.content,
                        action: \.content
                    )
                    NavigationStack {
                        TeamWorkspaceDetailView(
                            store: teamWorkspaceDetailStore,
                            showsAuthoringControls: authoringStore.grant?.access.canEditContent == true
                        )
                        .openMusicEventWorkspacePhase(workspaceStore.phase)
                        .whiteLabelRootToolbar(store: store)
                    }
                }
                #endif
            } else if let organizationRootStore = store.spawn(\.organizationRoot) {
                OrganizationRootView(
                    store: organizationRootStore,
                    whiteLabelRootStore: store
                )
            } else {
                NavigationStack {
                    LoadingView(store: store)
                        .whiteLabelRootToolbar(store: store)
                }
            }
        }
        .sheet(
            item: $accountStore.presentation,
            onDismiss: { accountStore.send(.accountPresentationDismissed) }
        ) { _ in
            AccountPresentationView(store: accountStore)
        }
    }

    struct LoadingView: View {
        let store: StoreOf<WhiteLabelRoot>

        var body: some View {
            Group {
                if store.loadingPhase != .idle,
                   let loadingImage = store.configuration.brand.loadingImage {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(
                            loadingImage.name,
                            bundle: Bundle(url: loadingImage.bundleURL)
                        )
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 320, maxHeight: 240)
                        .accessibilityHidden(true)
                        ProgressView()
                            .accessibilityLabel(
                                Text(
                                    store.loadingPhase.title(
                                        displayName: store.configuration.brand.displayName
                                    )
                                )
                            )
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    List {
                        Header(configuration: store.configuration)

                        if store.loadingPhase != .idle {
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
                    MappedSystemImage(systemName: configuration.brand.systemImage)
                        .frame(width: 24, height: 24)
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
    typealias AuthoringFeature = OpenMusicEventAuthoringWorkspace<
        TeamWorkspaceDetail
    >.AuthoringFeature

    let store: StoreOf<AuthoringFeature>

    var body: some View {
        Menu {
            if store.canEnter {
                Button {
                    store.send(.enterButtonTapped)
                } label: {
                    Label {
                        Text("Enter Authoring")
                    } icon: {
                        if store.entry.isRunning {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.pencil")
                        }
                    }
                }
                .disabled(store.entry.isRunning)
            } else if store.grant?.access.canEditContent == true {
                let workspaceStore = store.scope(\.content, action: \.content)
                let teamWorkspaceDetailStore = workspaceStore.scope(
                    \.content,
                    action: \.content
                )
                Button {
                    teamWorkspaceDetailStore.send(.manageSourceButtonTapped)
                } label: {
                    Label(
                        "Workspace",
                        mappedSystemImage: EventFeature.workspace.systemImage
                    )
                }
            }
        } label: {
            Label("Actions", systemImage: "gearshape")
                .labelStyle(.iconOnly)
        }
    }
}

extension View {
    func whiteLabelRootToolbar(store: StoreOf<WhiteLabelRoot>) -> some View {
        whiteLabelRootToolbar(store: Optional(store))
    }

    func whiteLabelRootToolbar(store: StoreOf<WhiteLabelRoot>?) -> some View {
        toolbar {
            if let store {
                #if os(macOS) && !SKIP
                ToolbarItem(placement: .automatic) {
                    AccountPicker(store: store.spawn(\.account))
                }
                #else
                ToolbarItem(placement: .topBarLeading) {
                    AccountPicker(store: store.spawn(\.account))
                }
                #endif

                if let authorizationStore = store.spawn(\.teamWorkspaceDetail) {
                    let workspaceAuthoringStore = authorizationStore.scope(
                        \.content,
                        action: \.content
                    )
                    let authoringStore = workspaceAuthoringStore.scope(
                        \.authoring,
                        action: \.authoring
                    )
                    if authoringStore.canEnter
                        || authoringStore.grant?.access.canEditContent == true
                    {
                        ToolbarItem(placement: .primaryAction) {
                            WhiteLabelRootActionsMenu(store: authoringStore)
                        }
                    }
                }
            }
        }
    }
}

private extension WhiteLabelRoot.State {
    mutating func setLoadedRoot(
        organizerID: OMERecord.Organizer.ID,
        sourceBaselineIDs: [SourceBaselineRecord.ID]
    ) {
        if sourceBaselineIDs.count == 1, let sourceBaselineID = sourceBaselineIDs.first {
            organizationRoot = nil
            if teamWorkspaceDetail?.state.content.authoring.content.content
                .sourceBaselineID != sourceBaselineID
            {
                teamWorkspaceDetail = Spawn(
                    WhiteLabelRoot.TeamWorkspace.State(
                        storage: OpenMusicEventOAuth.storage
                    ) {
                        let workspaceID = EditingWorkspaceRecord.ID(
                            sourceBaselineID: sourceBaselineID
                        )
                        return OpenMusicEventAuthoringWorkspace<TeamWorkspaceDetail>.state(
                            workspaceID: workspaceID
                        ) {
                            TeamWorkspaceDetail.State(
                                sourceBaselineID: sourceBaselineID
                            )
                        }
                    }
                )
            }
        } else {
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
