import Dependencies
import FileTree
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceEditing
import Sharing
import SourceEditing
import SQLiteData

public struct SourceWorkspaceState: Equatable, Sendable {
    public enum Activity: Equatable, Sendable {
        case preparingForEditing
        case refreshing
    }

    public var activity: Activity?
    public var queuedOperationCount: Int

    public init(
        activity: Activity? = nil,
        queuedOperationCount: Int = 0
    ) {
        self.activity = activity
        self.queuedOperationCount = queuedOperationCount
    }
}

public struct SourceWorkspaceClient: Sendable {
    public var state: @Sendable (
        EditingWorkspaceRecord.ID
    ) -> SharedReader<SourceWorkspaceState>
    public var importSource: @Sendable (
        OpenMusicEventSourceValidationRequest
    ) async throws -> OpenMusicEventSourceValidationResult
    public var prepareForEditing: @Sendable (
        SourceBaselineRecord.ID
    ) async throws -> Void

    public init(
        state: @escaping @Sendable (
            EditingWorkspaceRecord.ID
        ) -> SharedReader<SourceWorkspaceState>,
        importSource: @escaping @Sendable (
            OpenMusicEventSourceValidationRequest
        ) async throws -> OpenMusicEventSourceValidationResult,
        prepareForEditing: @escaping @Sendable (
            SourceBaselineRecord.ID
        ) async throws -> Void
    ) {
        self.state = state
        self.importSource = importSource
        self.prepareForEditing = prepareForEditing
    }
}

extension SourceWorkspaceClient {
    static func coordinated(
        database: any DatabaseWriter,
        importSource: TangledSourceImportClient,
        prepareForEditing: SourceEditModePreparationClient
    ) -> Self {
        let stateStore = SourceWorkspaceStateStore()
        let operationQueue = SourceWorkspaceOperationQueue(stateStore: stateStore)

        return Self(
            state: { workspaceID in
                stateStore.reader(workspaceID)
            },
            importSource: { request in
                guard let sourceProvenance = try request.tangledSourceProvenance()
                else {
                    return try await importSource.importSource(request)
                }
                let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
                let workspaceID = EditingWorkspaceRecord.ID(
                    sourceBaselineID: sourceBaselineID
                )
                return try await operationQueue.run(
                    workspaceID,
                    activity: .refreshing
                ) {
                    try await Self.refresh(
                        request,
                        sourceProvenance: sourceProvenance,
                        sourceBaselineID: sourceBaselineID,
                        database: database,
                        fallback: importSource
                    )
                }
            },
            prepareForEditing: { sourceBaselineID in
                let workspaceID = EditingWorkspaceRecord.ID(
                    sourceBaselineID: sourceBaselineID
                )
                try await operationQueue.run(
                    workspaceID,
                    activity: .preparingForEditing
                ) {
                    try await prepareForEditing.prepare(sourceBaselineID)
                }
            }
        )
    }

    private static func refresh(
        _ request: OpenMusicEventSourceValidationRequest,
        sourceProvenance: OME.SourceDatabaseInsertion.SourceProvenance,
        sourceBaselineID: SourceBaselineRecord.ID,
        database: any DatabaseWriter,
        fallback: TangledSourceImportClient
    ) async throws -> OpenMusicEventSourceValidationResult {
        @Dependency(
            SourcePatchGeneratorKey<OpenMusicEventCalendarSourcePatchRequest>.self
        ) var sourcePatchGenerator
        @Dependency(\.sourcePatchApplier) var sourcePatchApplier
        @Dependency(\.sourceRepositoryStorage) var sourceRepositoryStorage
        @Dependency(\.sourceWorkingTreeMaterializer) var sourceWorkingTreeMaterializer
        @Dependency(\.uuid) var uuid

        let hasImportedBaseline = try await database.read { db in
            try SourceBaselineRecord
                .where { $0.id.eq(sourceBaselineID) }
                .fetchOne(db) != nil
        }
        guard hasImportedBaseline else {
            return try await fallback.importSource(request)
        }

        let storedRepositoryURL = try sourceRepositoryStorage
            .repositoryURL(sourceProvenance)
        guard FileManager.default.fileExists(atPath: storedRepositoryURL.path) else {
            return try await fallback.importSource(request)
        }

        let organizerID = try await organizerID(
            for: sourceBaselineID,
            in: database
        )
        let localPatch = try await sourcePatchGenerator.generate(
            OpenMusicEventCalendarSourcePatchRequest(
                calendarID: OME.Calendar.ID(
                    ownerID: organizerID,
                    calendarID: OME.Calendar.defaultID
                ),
                sourceBaselineID: sourceBaselineID
            )
        )

        let backendRepositoryURL = SourceRepositoryStorageClient
            .temporaryDownloadURL(uuid: uuid())
        defer { try? FileManager.default.removeItem(at: backendRepositoryURL) }

        var stagedRequest = request
        stagedRequest.organizerID = organizerID
        stagedRequest.outputURL = backendRepositoryURL
        var backendResult = try await OpenMusicEventSourceValidator(stagedRequest)
            .validate()

        let workingResult: OpenMusicEventSourceValidationResult
        if localPatch.isEmpty {
            workingResult = backendResult
        } else {
            let workingTree = try sourceWorkingTreeMaterializer.materialize(
                backendRepositoryURL,
                nil
            )
            defer {
                try? FileManager.default.removeItem(at: workingTree.workingRepositoryURL)
            }
            try sourcePatchApplier.apply(
                localPatch,
                workingTree.workingRepositoryURL
            )
            workingResult = try validationResult(
                repositoryURL: workingTree.workingRepositoryURL,
                organizerID: organizerID,
                sourceProvenance: sourceProvenance
            )
        }

        try await backendResult.insertion.migrateAndInsert(
            rebasedWorkingCopy: workingResult.insertion,
            into: database
        )
        backendResult.repositoryURL = try sourceRepositoryStorage.store(
            backendRepositoryURL,
            sourceProvenance
        )
        return backendResult
    }

    private static func organizerID(
        for sourceBaselineID: SourceBaselineRecord.ID,
        in database: any DatabaseReader
    ) async throws -> OME.Organizer.ID {
        let organizerID = try await database.read { db in
            try EventSourceProvenanceRecord
                .where { $0.sourceBaselineID.eq(sourceBaselineID) }
                .fetchOne(db)?
                .id
                .organizerID
        }
        guard let organizerID else {
            throw SourceWorkspaceError.sourceBaselineHasNoEvents(sourceBaselineID)
        }
        return organizerID
    }

    private static func validationResult(
        repositoryURL: URL,
        organizerID: OME.Organizer.ID,
        sourceProvenance: OME.SourceDatabaseInsertion.SourceProvenance
    ) throws -> OpenMusicEventSourceValidationResult {
        let sourceResult = try OpenMusicEventSourceRepositoryFileTree()
            .read(from: repositoryURL)
        let source = try sourceResult.output.requiredValue
        let insertion = try OME.SourceDatabaseInsertion(
            .init(
                source: source,
                organizerID: organizerID,
                sourceProvenance: sourceProvenance,
                sourceRootURL: repositoryURL
            )
        )
        return OpenMusicEventSourceValidationResult(
            repositoryURL: repositoryURL,
            organizerID: organizerID,
            insertion: insertion,
            summary: SourceValidationSummary(source: source, insertion: insertion)
        )
    }
}

private enum SourceWorkspaceError: Equatable, Error, Sendable {
    case sourceBaselineHasNoEvents(SourceBaselineRecord.ID)
    case unconfigured
}

private enum SourceWorkspaceClientKey: DependencyKey {
    static var liveValue: SourceWorkspaceClient { .unconfigured }
    static var testValue: SourceWorkspaceClient { .unconfigured }
}

public extension DependencyValues {
    var sourceWorkspace: SourceWorkspaceClient {
        get { self[SourceWorkspaceClientKey.self] }
        set { self[SourceWorkspaceClientKey.self] = newValue }
    }
}

private extension SourceWorkspaceClient {
    static var unconfigured: Self {
        Self(
            state: { _ in SharedReader(value: SourceWorkspaceState()) },
            importSource: { _ in throw SourceWorkspaceError.unconfigured },
            prepareForEditing: { _ in throw SourceWorkspaceError.unconfigured }
        )
    }
}

private final class SourceWorkspaceStateStore: @unchecked Sendable {
    private let lock = NSLock()
    private var states: [EditingWorkspaceRecord.ID: Shared<SourceWorkspaceState>] = [:]

    func reader(
        _ workspaceID: EditingWorkspaceRecord.ID
    ) -> SharedReader<SourceWorkspaceState> {
        SharedReader(shared(workspaceID))
    }

    func enqueue(_ workspaceID: EditingWorkspaceRecord.ID) {
        shared(workspaceID).withLock {
            $0.queuedOperationCount += 1
        }
    }

    func start(
        _ workspaceID: EditingWorkspaceRecord.ID,
        activity: SourceWorkspaceState.Activity
    ) {
        shared(workspaceID).withLock {
            $0.activity = activity
            $0.queuedOperationCount -= 1
        }
    }

    func finish(_ workspaceID: EditingWorkspaceRecord.ID) {
        shared(workspaceID).withLock {
            $0.activity = nil
        }
    }

    private func shared(
        _ workspaceID: EditingWorkspaceRecord.ID
    ) -> Shared<SourceWorkspaceState> {
        lock.lock()
        defer { lock.unlock() }
        if let state = states[workspaceID] {
            return state
        }
        let state = Shared(value: SourceWorkspaceState())
        states[workspaceID] = state
        return state
    }
}

private actor SourceWorkspaceOperationQueue {
    private struct Tail {
        var id: Int
        var task: Task<Void, Never>
    }

    private let stateStore: SourceWorkspaceStateStore
    private var nextID = 0
    private var tails: [EditingWorkspaceRecord.ID: Tail] = [:]

    init(stateStore: SourceWorkspaceStateStore) {
        self.stateStore = stateStore
    }

    func run<Value: Sendable>(
        _ workspaceID: EditingWorkspaceRecord.ID,
        activity: SourceWorkspaceState.Activity,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let predecessor = tails[workspaceID]?.task
        let stateStore = self.stateStore
        nextID += 1
        let id = nextID
        stateStore.enqueue(workspaceID)

        let task = Task<Value, Error> {
            await predecessor?.value
            stateStore.start(workspaceID, activity: activity)
            defer { stateStore.finish(workspaceID) }
            try Task.checkCancellation()
            return try await operation()
        }
        let tail = Tail(
            id: id,
            task: Task { _ = await task.result }
        )
        tails[workspaceID] = tail
        defer {
            if tails[workspaceID]?.id == id {
                tails[workspaceID] = nil
            }
        }
        return try await task.value
    }
}
