import ComposableArchitecture2
import Dependencies
import Foundation
import HTTPClient
import OpenMusicEventAppEventViewer
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceClone
import OpenMusicEventSourceEditing
import SQLiteData
import SwiftUI

public typealias OMERecord = OpenMusicEvent

public struct WhiteLabelAppConfiguration: Equatable, Sendable {
    public var brand: WhiteLabelBrand
    public var developmentOrganizerID: OMERecord.Organizer.ID?
    public var handle: String?
    public var organizerID: OMERecord.Organizer.ID?

    public init(
        brand: WhiteLabelBrand,
        organizerID: OMERecord.Organizer.ID? = nil,
        handle: String? = nil,
        developmentOrganizerID: OMERecord.Organizer.ID? = nil
    ) {
        self.brand = brand
        self.organizerID = organizerID
        self.handle = handle
        self.developmentOrganizerID = developmentOrganizerID
    }
}

public struct WhiteLabelBrand: Equatable, Sendable {
    public var displayName: String
    public var systemImage: String

    public init(
        displayName: String,
        systemImage: String = "music.note.list"
    ) {
        self.displayName = displayName
        self.systemImage = systemImage
    }
}

public struct WhiteLabelSourceDescriptor: Equatable, Sendable {
    public var reference: WhiteLabelSourceReference
    public var version: String?

    public init(
        reference: WhiteLabelSourceReference,
        version: String? = nil
    ) {
        self.reference = reference
        self.version = version
    }
}

public enum WhiteLabelSourceReference: Equatable, Sendable {
    case archiveURL(URL)
    case source(String)
}

public enum WickedWoodsWhiteLabel {
    public static let handle = "wickedwoods.ca"
    public static let temporaryDevelopmentOrganizerID = OMERecord.Organizer.ID("did:plc:wickedwoodsdev")!

    public static func configuration(
        organizerID: OMERecord.Organizer.ID? = nil
    ) -> WhiteLabelAppConfiguration {
        WhiteLabelAppConfiguration(
            brand: WhiteLabelBrand(displayName: "Wicked Woods"),
            organizerID: organizerID,
            handle: handle,
            developmentOrganizerID: organizerID == nil ? temporaryDevelopmentOrganizerID : nil
        )
    }

    public static func developmentSourceOverride(
        reference: WhiteLabelSourceReference,
        version: String? = nil
    ) -> WhiteLabelDevelopmentSourceOverride {
        WhiteLabelDevelopmentSourceOverride(
            organizerID: temporaryDevelopmentOrganizerID,
            source: WhiteLabelSourceDescriptor(reference: reference, version: version)
        )
    }
}

public struct WhiteLabelDevelopmentSourceOverride: Equatable, Sendable {
    public var organizerID: OMERecord.Organizer.ID
    public var source: WhiteLabelSourceDescriptor

    public init(
        organizerID: OMERecord.Organizer.ID,
        source: WhiteLabelSourceDescriptor
    ) {
        self.organizerID = organizerID
        self.source = source
    }
}

public struct WhiteLabelOrganizerIdentityResolverClient: Sendable {
    public var resolve: @Sendable (String) async throws -> OMERecord.Organizer.ID

    public init(
        resolve: @escaping @Sendable (String) async throws -> OMERecord.Organizer.ID
    ) {
        self.resolve = resolve
    }
}

public struct WhiteLabelSourceRegistryClient: Sendable {
    public var source: @Sendable (OMERecord.Organizer.ID) async throws -> WhiteLabelSourceDescriptor

    public init(
        source: @escaping @Sendable (OMERecord.Organizer.ID) async throws -> WhiteLabelSourceDescriptor
    ) {
        self.source = source
    }
}

public struct WhiteLabelSourceImportClient: Sendable {
    public var ensureImported: @Sendable (OMERecord.Organizer.ID, WhiteLabelSourceDescriptor) async throws -> [OMERecord.Event.ID]

    public init(
        ensureImported: @escaping @Sendable (OMERecord.Organizer.ID, WhiteLabelSourceDescriptor) async throws -> [OMERecord.Event.ID]
    ) {
        self.ensureImported = ensureImported
    }
}

public enum WhiteLabelError: Equatable, LocalizedError, Sendable {
    case developmentSourceOverrideUnavailable
    case directSourceRequiresDevelopmentOverride(OMERecord.Organizer.ID)
    case missingOrganizerIdentity(String)
    case organizerIdentityResolverUnconfigured(String)
    case sourceRegistryUnconfigured(OMERecord.Organizer.ID)

    public var errorDescription: String? {
        switch self {
        case .developmentSourceOverrideUnavailable:
            "Development source overrides are only available in debug and test builds."
        case let .directSourceRequiresDevelopmentOverride(organizerID):
            "Direct source loading for \(organizerID) must use the development source override."
        case let .missingOrganizerIdentity(displayName):
            "\(displayName) does not have an organizer account DID yet."
        case let .organizerIdentityResolverUnconfigured(handle):
            "No organizer DID resolver is configured for \(handle)."
        case let .sourceRegistryUnconfigured(organizerID):
            "No white-label source is registered for \(organizerID)."
        }
    }
}

public enum WhiteLabelDatabaseMigrations {
    public static func register(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("Create OpenMusicEvent white-label app schema") { db in
            try #sql("""
                CREATE TABLE IF NOT EXISTS "organizerPreferences" (
                  "organizerID" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
                  "isFollowing" INTEGER NOT NULL DEFAULT 0
                ) STRICT
                """)
                .execute(db)

            try #sql("""
                CREATE TABLE IF NOT EXISTS "contributorPreferences" (
                  "organizerID" TEXT NOT NULL,
                  "eventID" TEXT NOT NULL,
                  "contributorID" TEXT NOT NULL,
                  "isFavorite" INTEGER NOT NULL DEFAULT 0,
                  PRIMARY KEY ("organizerID", "eventID", "contributorID") ON CONFLICT REPLACE
                ) STRICT
                """)
                .execute(db)

            try #sql("""
                CREATE TABLE IF NOT EXISTS "performancePreferences" (
                  "organizerID" TEXT NOT NULL,
                  "eventID" TEXT NOT NULL,
                  "performanceID" TEXT NOT NULL,
                  "interested" INTEGER NOT NULL DEFAULT 0,
                  "seen" INTEGER NOT NULL DEFAULT 0,
                  PRIMARY KEY ("organizerID", "eventID", "performanceID") ON CONFLICT REPLACE
                ) STRICT
                """)
                .execute(db)

            try #sql("""
                CREATE TABLE IF NOT EXISTS "channelPreferences" (
                  "organizerID" TEXT NOT NULL,
                  "eventID" TEXT NOT NULL,
                  "channelID" TEXT NOT NULL,
                  "notificationState" TEXT NOT NULL,
                  PRIMARY KEY ("organizerID", "eventID", "channelID") ON CONFLICT REPLACE
                ) STRICT
                """)
                .execute(db)

            try #sql("""
                CREATE TABLE IF NOT EXISTS "posterPreferences" (
                  "organizerID" TEXT NOT NULL,
                  "eventID" TEXT NOT NULL,
                  "posterID" TEXT NOT NULL,
                  "isRead" INTEGER NOT NULL DEFAULT 0,
                  "isFavorite" INTEGER NOT NULL DEFAULT 0,
                  PRIMARY KEY ("organizerID", "eventID", "posterID") ON CONFLICT REPLACE
                ) STRICT
                """)
                .execute(db)

            try #sql("""
                CREATE TABLE IF NOT EXISTS "externalAssetPreferences" (
                  "assetURL" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
                  "platform" TEXT,
                  "cachedTitle" TEXT,
                  "cachedDescription" TEXT,
                  "cachedThumbnailURL" TEXT,
                  "cachedDurationSeconds" INTEGER,
                  "lastMetadataFetchAttemptAt" TEXT,
                  "isWatched" INTEGER NOT NULL DEFAULT 0,
                  "isFavorite" INTEGER NOT NULL DEFAULT 0,
                  "lastAccessedAt" TEXT,
                  "playbackPositionSeconds" INTEGER
                ) STRICT
                """)
                .execute(db)

            try #sql("""
                CREATE TABLE IF NOT EXISTS "eventViewerState" (
                  "organizerID" TEXT NOT NULL,
                  "eventID" TEXT NOT NULL,
                  "selectedScheduleID" TEXT,
                  PRIMARY KEY ("organizerID", "eventID") ON CONFLICT REPLACE
                ) STRICT
                """)
                .execute(db)

            try #sql("""
                CREATE TABLE IF NOT EXISTS "scheduleViewerState" (
                  "organizerID" TEXT NOT NULL,
                  "eventID" TEXT NOT NULL,
                  "category" TEXT,
                  "selectedStageID" TEXT,
                  "showStageNameLabels" INTEGER NOT NULL DEFAULT 0,
                  "filteringFavorites" INTEGER NOT NULL DEFAULT 0,
                  "filteringInterested" INTEGER NOT NULL DEFAULT 0,
                  "scheduleKind" TEXT NOT NULL DEFAULT 'singleStageAtOnce',
                  PRIMARY KEY ("organizerID", "eventID", "category")
                ) STRICT
                """)
                .execute(db)
        }
    }
}

private enum WhiteLabelDevelopmentSourceOverrideKey: DependencyKey {
    static var liveValue: WhiteLabelDevelopmentSourceOverride? { nil }
    static var testValue: WhiteLabelDevelopmentSourceOverride? { nil }
}

private enum WhiteLabelOrganizerIdentityResolverClientKey: DependencyKey {
    static var liveValue: WhiteLabelOrganizerIdentityResolverClient {
        WhiteLabelOrganizerIdentityResolverClient { handle in
            throw WhiteLabelError.organizerIdentityResolverUnconfigured(handle)
        }
    }

    static var testValue: WhiteLabelOrganizerIdentityResolverClient {
        liveValue
    }
}

private enum WhiteLabelSourceRegistryClientKey: DependencyKey {
    static var liveValue: WhiteLabelSourceRegistryClient {
        WhiteLabelSourceRegistryClient { organizerID in
            throw WhiteLabelError.sourceRegistryUnconfigured(organizerID)
        }
    }

    static var testValue: WhiteLabelSourceRegistryClient {
        liveValue
    }
}

private enum WhiteLabelSourceImportClientKey: DependencyKey {
    static var liveValue: WhiteLabelSourceImportClient {
        .live
    }

    static var testValue: WhiteLabelSourceImportClient {
        WhiteLabelSourceImportClient { _, _ in [] }
    }
}

public extension DependencyValues {
    var whiteLabelDevelopmentSourceOverride: WhiteLabelDevelopmentSourceOverride? {
        get { self[WhiteLabelDevelopmentSourceOverrideKey.self] }
        set { self[WhiteLabelDevelopmentSourceOverrideKey.self] = newValue }
    }

    var whiteLabelOrganizerIdentityResolver: WhiteLabelOrganizerIdentityResolverClient {
        get { self[WhiteLabelOrganizerIdentityResolverClientKey.self] }
        set { self[WhiteLabelOrganizerIdentityResolverClientKey.self] = newValue }
    }

    var whiteLabelSourceImport: WhiteLabelSourceImportClient {
        get { self[WhiteLabelSourceImportClientKey.self] }
        set { self[WhiteLabelSourceImportClientKey.self] = newValue }
    }

    var whiteLabelSourceRegistry: WhiteLabelSourceRegistryClient {
        get { self[WhiteLabelSourceRegistryClientKey.self] }
        set { self[WhiteLabelSourceRegistryClientKey.self] = newValue }
    }
}

public extension WhiteLabelSourceRegistryClient {
    static func codeBacked(
        _ sources: [OMERecord.Organizer.ID: WhiteLabelSourceDescriptor]
    ) -> Self {
        Self { organizerID in
            guard let source = sources[organizerID] else {
                throw WhiteLabelError.sourceRegistryUnconfigured(organizerID)
            }
            return source
        }
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

public struct WhiteLabelEventRow: Equatable, Identifiable, Sendable {
    public var id: OMERecord.Event.ID
    public var endDate: LocalDate?
    public var name: String
    public var startDate: LocalDate?

    public init(
        id: OMERecord.Event.ID,
        name: String,
        startDate: LocalDate?,
        endDate: LocalDate?
    ) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
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
        public var eventViewer: Spawn<EventViewer>?
        public var events: [WhiteLabelEventRow] = []
        public var isLoading = false
        public var organizerID: OMERecord.Organizer.ID?
    }

    public enum Action {
        case eventButtonTapped(OMERecord.Event.ID)
        case eventViewerDismissed
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
            case .eventButtonTapped(let eventID):
                store.withDependencies {
                    state.eventViewer = Spawn(EventViewer.State(eventID: eventID))
                }

            case .eventViewerDismissed:
                state.eventViewer = nil

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
                        let result = try await Self.load(
                            configuration,
                            database: database,
                            developmentSourceOverride: developmentSourceOverride,
                            identityResolver: identityResolver,
                            sourceImport: sourceImport,
                            sourceRegistry: sourceRegistry
                        )
                        try store.modify {
                            $0.errorMessage = nil
                            $0.events = result.events
                            $0.isLoading = false
                            $0.organizerID = result.organizerID
                        }
                    } catch {
                        let cached = (try? await Self.cachedEvents(
                            for: configuration,
                            database: database,
                            developmentSourceOverride: developmentSourceOverride,
                            identityResolver: identityResolver
                        )) ?? []
                        try store.modify {
                            $0.events = cached
                            $0.errorMessage = cached.isEmpty
                                ? error.localizedDescription
                                : "Unable to refresh \(configuration.brand.displayName)."
                            $0.isLoading = false
                        }
                    }
                }
            }
        }
        .ifLet(\.eventViewer) {
            EventViewer()
        }
    }

    private static func load(
        _ configuration: WhiteLabelAppConfiguration,
        database: any DatabaseReader,
        developmentSourceOverride: WhiteLabelDevelopmentSourceOverride?,
        identityResolver: WhiteLabelOrganizerIdentityResolverClient,
        sourceImport: WhiteLabelSourceImportClient,
        sourceRegistry: WhiteLabelSourceRegistryClient
    ) async throws -> (organizerID: OMERecord.Organizer.ID, events: [WhiteLabelEventRow]) {
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
        return (
            organizerID,
            try await events(for: organizerID, in: database)
        )
    }

    private static func cachedEvents(
        for configuration: WhiteLabelAppConfiguration,
        database: any DatabaseReader,
        developmentSourceOverride: WhiteLabelDevelopmentSourceOverride?,
        identityResolver: WhiteLabelOrganizerIdentityResolverClient
    ) async throws -> [WhiteLabelEventRow] {
        if let override = developmentSourceOverride {
            return try await events(for: override.organizerID, in: database)
        }
        let organizerID: OMERecord.Organizer.ID
        if let configuredOrganizerID = configuration.organizerID {
            organizerID = configuredOrganizerID
        } else if let handle = configuration.handle {
            organizerID = try await identityResolver.resolve(handle)
        } else {
            return []
        }
        return try await events(for: organizerID, in: database)
    }

    private static var developmentSourceOverridesAreEnabled: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    private static func events(
        for organizerID: OMERecord.Organizer.ID,
        in database: any DatabaseReader
    ) async throws -> [WhiteLabelEventRow] {
        try await database.read { db in
            try OMERecord.Event
                .where { $0.id.organizerID.eq(organizerID) }
                .fetchAll(db)
                .map {
                    WhiteLabelEventRow(
                        id: $0.id,
                        name: $0.name,
                        startDate: $0.startDate,
                        endDate: $0.endDate
                    )
                }
                .sortedForWhiteLabelHome()
        }
    }
}

public struct WhiteLabelRootView: View {
    public init(store: StoreOf<WhiteLabelRoot>) {
        self.store = store
    }

    @Bindable var store: StoreOf<WhiteLabelRoot>

    public var body: some View {
        NavigationStack {
            List {
                header

                if store.isLoading && store.events.isEmpty {
                    ProgressView()
                }

                if let errorMessage = store.errorMessage, store.events.isEmpty {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Retry") {
                            store.send(.retryButtonTapped)
                        }
                    }
                }

                if !store.events.isEmpty {
                    Section("Events") {
                        ForEach(store.events) { event in
                            Button {
                                store.send(.eventButtonTapped(event.id))
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(event.name)
                                        .foregroundStyle(.primary)
                                    if let dateSummary = event.dateSummary {
                                        Text(dateSummary)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .accessibilityIdentifier("whiteLabel.event.\(event.id.eventID.rawValue.rawValue)")
                        }
                    }
                }

                if let errorMessage = store.errorMessage, !store.events.isEmpty {
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
            .task {
                await store.send(.task)?.value
            }
            .sheet(
                isPresented: eventViewerIsPresented,
                onDismiss: {
                    store.send(.eventViewerDismissed)
                }
            ) {
                if let eventViewerStore = store.spawn(\.eventViewer) {
                    EventViewerView(store: eventViewerStore)
                }
            }
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

    private var eventViewerIsPresented: Binding<Bool> {
        Binding(
            get: { store.eventViewer != nil },
            set: { isPresented in
                if !isPresented {
                    store.send(.eventViewerDismissed)
                }
            }
        )
    }
}

private extension Array where Element == WhiteLabelEventRow {
    func sortedForWhiteLabelHome() -> [WhiteLabelEventRow] {
        sorted { lhs, rhs in
            switch (lhs.startDate, rhs.startDate) {
            case let (lhs?, rhs?):
                lhs > rhs
            case (.some, nil):
                true
            case (nil, .some):
                false
            case (nil, nil):
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }
    }
}

private extension WhiteLabelSourceDescriptor {
    func validateProductionUse(organizerID: OMERecord.Organizer.ID) throws {
        if case .source = reference {
            throw WhiteLabelError.directSourceRequiresDevelopmentOverride(organizerID)
        }
    }
}

private extension WhiteLabelEventRow {
    var dateSummary: String? {
        switch (startDate, endDate) {
        case let (start?, end?) where start != end:
            "\(start.description) - \(end.description)"
        case let (start?, _):
            start.description
        case let (nil, end?):
            end.description
        case (nil, nil):
            nil
        }
    }
}
