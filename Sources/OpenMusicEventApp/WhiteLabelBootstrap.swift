import ComposableArchitecture2
import Dependencies
import ErrorHandling
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventSource
import OpenMusicEventSourceClone
import OpenMusicEventSourceEditing
import OpenMusicEventWhiteLabel
import SQLiteData
import SwiftUI

@Feature
public struct WhiteLabelBootstrap {
    public init() {}

    public struct State {
        public init(configuration: WhiteLabelAppConfiguration) {
            self.configuration = configuration
        }

        public var configuration: WhiteLabelAppConfiguration
        public var errorMessage: String?
        public var isLoading = false
        public var loadingPhase: LoadingPhase = .idle
        public var organizationRoot: Spawn<OrganizationRoot>?
        public var organizerID: OMERecord.Organizer.ID?
        public var sourceDetail: Spawn<SourceDetail>?

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
        case retryButtonTapped
        case task
    }

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.openMusicEventStoredAuthentication) var storedAuthentication
    @Dependency(\.whiteLabelDevelopmentSourceOverride) var developmentSourceOverride
    @Dependency(\.whiteLabelOrganizerIdentityResolver) var identityResolver
    @Dependency(\.whiteLabelSourceImport) var sourceImport
    @Dependency(\.whiteLabelSourceRegistry) var sourceRegistry

    public var body: some Feature {
        let _ = Self._logChanges()

        Update { state, action in
            switch action {
            case .retryButtonTapped, .task:
                guard !state.isLoading else { return }
                state.errorMessage = nil
                state.isLoading = true
                state.loadingPhase = .preparing

                let configuration = state.configuration
                let database = self.database
                let developmentSourceOverride = self.developmentSourceOverride
                let identityResolver = self.identityResolver
                let sourceImport = self.sourceImport
                let sourceRegistry = self.sourceRegistry
                let storedAuthentication = self.storedAuthentication
                store.addTask {
                    let updateLoadingPhase: (State.LoadingPhase) async -> Void = { phase in
                        _ = try? store.modify {
                            $0.loadingPhase = phase
                        }
                    }

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
                        await updateLoadingPhase(Self.initialLoadingPhase(
                            configuration,
                            developmentSourceOverride: developmentSourceOverride
                        ))
                        let resolvedSource = try await Self.resolveSource(
                            configuration,
                            developmentSourceOverride: developmentSourceOverride,
                            identityResolver: identityResolver,
                            sourceRegistry: sourceRegistry
                        )
                        await updateLoadingPhase(.importingSource)
                        _ = try await sourceImport.ensureImported(
                            resolvedSource.organizerID,
                            resolvedSource.descriptor
                        )
                        await updateLoadingPhase(.openingEvent)
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
                        try store.modify {
                            $0.errorMessage = nil
                            $0.isLoading = false
                            $0.loadingPhase = .idle
                            $0.organizerID = loadedRoot.organizerID
                            $0.setLoadedRoot(
                                organizerID: loadedRoot.organizerID,
                                sourceBaselineIDs: loadedRoot.sourceBaselineIDs
                            )
                        }
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
                        } else {
                            $0.errorMessage = UserFacingText.whiteLabelLoadFailed.localizedString
                        }
                    }
                }
            }
        }
        .ifLet(\.organizationRoot) {
            OrganizationRoot()
        }
        .ifLet(\.sourceDetail) {
            SourceDetail()
        }
    }

    private struct ResolvedSource {
        var organizerID: OMERecord.Organizer.ID
        var descriptor: WhiteLabelSourceDescriptor
    }

    private struct LoadedRoot {
        var organizerID: OMERecord.Organizer.ID
        var sourceBaselineIDs: [SourceBaselineRecord.ID]
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
                .where { $0.id.organizerID.eq(organizerID) }
                .fetchAll(db)
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

public struct WhiteLabelBootstrapView: View {
    public init(store: StoreOf<WhiteLabelBootstrap>) {
        self.store = store
    }

    @Bindable var store: StoreOf<WhiteLabelBootstrap>

    public var body: some View {
        content
            .task {
                await store.send(.task)?.value
            }
    }

    @ViewBuilder
    private var content: some View {
        if let sourceDetailStore = store.spawn(\.sourceDetail) {
            NavigationStack {
                SourceDetailView(store: sourceDetailStore)
            }
        } else if let organizationRootStore = store.spawn(\.organizationRoot) {
            OrganizationRootView(store: organizationRootStore)
        } else {
            NavigationStack {
                loadingView
            }
        }
    }

    private var loadingView: some View {
        List {
            header

            if store.isLoading {
                loadingStatus
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

    private var loadingStatus: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                ProgressView()
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.loadingPhase.title(displayName: store.configuration.brand.displayName))
                        .font(.headline)
                    Text(store.loadingPhase.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var header: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: store.configuration.brand.systemImage)
                    .font(.title2)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading) {
                    Text(store.configuration.brand.displayName)
                        .font(.headline)
                    if let handle = store.configuration.handle {
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

private extension WhiteLabelBootstrap.State {
    mutating func setLoadedRoot(
        organizerID: OMERecord.Organizer.ID,
        sourceBaselineIDs: [SourceBaselineRecord.ID]
    ) {
        if sourceBaselineIDs.count == 1, let sourceBaselineID = sourceBaselineIDs.first {
            organizationRoot = nil
            if sourceDetail?.state.sourceBaselineID != sourceBaselineID {
                sourceDetail = Spawn(SourceDetail.State(sourceBaselineID: sourceBaselineID))
            }
        } else {
            sourceDetail = nil
            if organizationRoot?.state.organizerID != organizerID {
                organizationRoot = Spawn(OrganizationRoot.State(organizerID: organizerID))
            }
        }
    }
}

private extension WhiteLabelBootstrap.State.LoadingPhase {
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
