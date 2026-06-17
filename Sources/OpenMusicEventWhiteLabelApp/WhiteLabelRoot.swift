import ComposableArchitecture2
import Dependencies
import Foundation
import HTTPClient
import OpenMusicEventApp
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceClone
import OpenMusicEventSourceEditing
import OpenMusicEventWhiteLabel
import SourceEditing
import SQLiteData
import SwiftUI

public typealias OMERecord = OpenMusicEventLexicon.OpenMusicEvent

public enum WhiteLabelDependencies {
    public static func prepare(_ dependencies: inout DependencyValues) throws {
        try OpenMusicEventAppDependencies.prepareDatabase(&dependencies)
        dependencies.tangledSourceCheckout = .archive
        dependencies.whiteLabelSourceImport = .live
        dependencies[SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self] = .openMusicEvent
        dependencies.sourcePatchPublisher = .preparedWorkingTree
        dependencies.sourceReferenceDatabaseMigrator = .openMusicEvent
    }
}

public extension WhiteLabelSourceImportClient {
    static var live: Self {
        Self { organizerID, descriptor in
            @Dependency(\.defaultDatabase) var database
            @Dependency(\.httpClient) var httpClient
            @Dependency(\.tangledSourceArchiveExtractor) var archiveExtractor
            @Dependency(\.uuid) var uuid

            let cachedEventIDs = try await events(for: organizerID, in: database)
            guard cachedEventIDs.isEmpty else { return cachedEventIDs }

            let request: OpenMusicEventSourceValidationRequest
            let cleanupURL: URL?

            switch descriptor.reference {
            case let .archiveURL(url):
                let outputURL = SourceRepositoryStorageClient
                    .temporaryDownloadURL(uuid: uuid())
                let archiveData: Data = try await withDependencies {
                    $0.logBody = false
                } operation: {
                    try await httpClient.get(url, decodingTo: Data.self)
                }
                try await archiveExtractor.extract(archiveData, outputURL)
                request = OpenMusicEventSourceValidationRequest(
                    source: outputURL.path(),
                    organizerID: organizerID
                )
                cleanupURL = outputURL

            case let .source(source):
                request = OpenMusicEventSourceValidationRequest(
                    source: source,
                    organizerID: organizerID
                )
                cleanupURL = nil
            }

            defer {
                if let cleanupURL {
                    try? FileManager.default.removeItem(at: cleanupURL)
                }
            }

            let result = try await OpenMusicEventSourceValidator(request)
                .validateAndInsertIntoDefaultDatabase()
            return result.insertedEventIDs
        }
    }

    private static func events(
        for organizerID: OMERecord.Organizer.ID,
        in database: any DatabaseReader
    ) async throws -> [OMERecord.Event.ID] {
        try await database.read { db in
            try OMERecord.Event
                .where { $0.id.organizerID.eq(organizerID) }
                .fetchAll(db)
                .map(\.id)
        }
    }
}

@Feature
public struct WhiteLabelRoot {
    public init() {}

    public struct State {
        public init(configuration: WhiteLabelAppConfiguration) {
            self.configuration = configuration
        }

        public var configuration: WhiteLabelAppConfiguration
        public var errorMessage: String?
        public var isLoading = false
        public var organizationRoot: Spawn<OrganizationRoot>?
        public var organizerID: OMERecord.Organizer.ID?
    }

    public enum Action {
        case retryButtonTapped
        case task
    }

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.whiteLabelDevelopmentSourceOverride) var developmentSourceOverride
    @Dependency(\.whiteLabelOrganizerIdentityResolver) var identityResolver
    @Dependency(\.whiteLabelSourceImport) var sourceImport
    @Dependency(\.whiteLabelSourceRegistry) var sourceRegistry

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .retryButtonTapped, .task:
                guard !state.isLoading else { return }
                state.errorMessage = nil
                state.isLoading = true

                let configuration = state.configuration
                let database = self.database
                let developmentSourceOverride = self.developmentSourceOverride
                let identityResolver = self.identityResolver
                let sourceImport = self.sourceImport
                let sourceRegistry = self.sourceRegistry
                store.addTask {
                    do {
                        let organizerID = try await Self.load(
                            configuration,
                            developmentSourceOverride: developmentSourceOverride,
                            identityResolver: identityResolver,
                            sourceImport: sourceImport,
                            sourceRegistry: sourceRegistry
                        )
                        try store.modify {
                            $0.errorMessage = nil
                            $0.isLoading = false
                            $0.organizerID = organizerID
                            $0.setOrganizationRoot(organizerID: organizerID)
                        }
                    } catch {
                        let cachedOrganizerID = try? await Self.cachedOrganizerID(
                            for: configuration,
                            database: database,
                            developmentSourceOverride: developmentSourceOverride,
                            identityResolver: identityResolver
                        )
                        try store.modify {
                            $0.isLoading = false
                            if let cachedOrganizerID {
                                $0.errorMessage = "Unable to refresh \(configuration.brand.displayName)."
                                $0.organizerID = cachedOrganizerID
                                $0.setOrganizationRoot(organizerID: cachedOrganizerID)
                            } else {
                                $0.errorMessage = error.localizedDescription
                            }
                        }
                    }
                }
            }
        }
        .ifLet(\.organizationRoot) {
            OrganizationRoot()
        }
    }

    private static func load(
        _ configuration: WhiteLabelAppConfiguration,
        developmentSourceOverride: WhiteLabelDevelopmentSourceOverride?,
        identityResolver: WhiteLabelOrganizerIdentityResolverClient,
        sourceImport: WhiteLabelSourceImportClient,
        sourceRegistry: WhiteLabelSourceRegistryClient
    ) async throws -> OMERecord.Organizer.ID {
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

        _ = try await sourceImport.ensureImported(organizerID, descriptor)
        return organizerID
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
        content
            .task {
                await store.send(.task)?.value
            }
    }

    @ViewBuilder
    private var content: some View {
        if let organizationRootStore = store.spawn(\.organizationRoot) {
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
                ProgressView()
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

private extension WhiteLabelRoot.State {
    mutating func setOrganizationRoot(organizerID: OMERecord.Organizer.ID) {
        if organizationRoot?.state.organizerID != organizerID {
            organizationRoot = Spawn(OrganizationRoot.State(organizerID: organizerID))
        }
    }
}

private extension WhiteLabelSourceDescriptor {
    func validateProductionUse(organizerID: OMERecord.Organizer.ID) throws {
        if case let .source(source) = reference,
           case .local = try SourceRepositoryLocation(parsing: source)
        {
            throw WhiteLabelError.directSourceRequiresDevelopmentOverride(organizerID)
        }
    }
}
