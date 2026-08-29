import ComposableWorkspace
import Foundation
import SQLiteData
import SourceEditing

/// The pre-model publication table is retained only as migration input.
@Table("sourceWorkspacePublications")
struct LegacyWorkspacePublicationRecord: Equatable, Sendable, Identifiable {
    var id: SourceWorkspace.ID
    var captureRequestID: String? = nil
    var capturedChangesData: Data? = nil
    var submissionData: Data? = nil
    var pushedSubmissionID: String? = nil
    var commitData: Data? = nil
    var recordedSubmissionID: String? = nil
    var mutationData: Data? = nil
    var proposalTimestamp: String? = nil
    var preparedSubmissionID: String? = nil
    var preparedPublicationData: Data? = nil
    var publishedSubmissionID: String? = nil
    var publishedProposalData: Data? = nil
}

@Table("sourceWorkspaceOpenProposals")
struct LegacyWorkspaceOpenProposalRecord: Equatable, Sendable, Identifiable {
    var id: SourceWorkspace.ID
    var proposalData: Data
}

@Table("sourceWorkspaceContexts")
struct WorkspaceContextRecord: Equatable, Sendable, Identifiable {
    var id: SourceWorkspace.ID
    var contextData: Data
}

@Table("sourceWorkspaceProposalReceipts")
struct WorkspaceProposalReceiptRecord: Equatable, Sendable, Identifiable {
    var id: String
    var workspaceID: SourceWorkspace.ID
    var proposalData: Data
}

@Table("sourceWorkspaceProposalRepairs")
struct WorkspaceProposalRepairRecord: Equatable, Sendable, Identifiable {
    var id: SourceWorkspace.ID
    var proposalData: Data
    var patchData: Data
}

public struct SourceWorkspaceProposalRepair: Codable, Equatable, Sendable {
    public var proposal: WorkspaceProposal
    public var patch: SourcePatch

    public init(proposal: WorkspaceProposal, patch: SourcePatch) {
        self.proposal = proposal
        self.patch = patch
    }
}

/// OME-private transport recovery. This is deliberately not part of Workspace's product model.
struct WorkspacePublicationCheckpoint: Codable, Equatable, Sendable {
    var changes: SourcePatch
    var id: UUID
    var target: WorkspacePublicationTarget

    init(attempt: WorkspaceProposalAttempt<SourcePatch>, id: UUID = UUID()) {
        self.changes = attempt.changes
        self.id = id
        self.target = WorkspacePublicationTarget(attempt.target)
    }

    var attempt: WorkspaceProposalAttempt<SourcePatch> {
        WorkspaceProposalAttempt(changes: changes, target: target.attemptTarget)
    }

    func represents(_ attempt: WorkspaceProposalAttempt<SourcePatch>) -> Bool {
        changes == attempt.changes && target.attemptTarget == attempt.target
    }
}

enum WorkspacePublicationTarget: Codable, Equatable, Sendable {
    case createProposal(
        target: WorkspaceBranchReference,
        details: WorkspaceProposalDetails
    )
    case updateProposal(WorkspaceProposal)

    init(_ target: WorkspaceProposalAttemptTarget) {
        switch target {
        case let .createProposal(target, details):
            self = .createProposal(target: target, details: details)
        case let .updateProposal(proposal):
            self = .updateProposal(proposal)
        }
    }

    var attemptTarget: WorkspaceProposalAttemptTarget {
        switch self {
        case let .createProposal(target, details):
            .createProposal(target: target, details: details)
        case let .updateProposal(proposal):
            .updateProposal(proposal)
        }
    }
}

public enum WorkspacePublicationMigrations {
    public static func register(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("Create canonical OpenMusicEvent workspace publication schema") {
            db in
            try #sql("""
                CREATE TABLE IF NOT EXISTS "sourceWorkspacePublications" (
                  "id" TEXT PRIMARY KEY NOT NULL,
                  "captureRequestID" TEXT,
                  "capturedChangesData" BLOB,
                  "submissionData" BLOB,
                  "pushedSubmissionID" TEXT,
                  "commitData" BLOB,
                  "recordedSubmissionID" TEXT,
                  "mutationData" BLOB,
                  "proposalTimestamp" TEXT,
                  "openProposalData" BLOB
                ) STRICT
                """)
                .execute(db)
        }
        migrator.registerMigration("Persist canonical OpenMusicEvent open proposal") { db in
            guard try !db.columns(in: "sourceWorkspacePublications")
                .contains(where: { $0.name == "openProposalData" })
            else { return }
            try #sql(
                "ALTER TABLE \"sourceWorkspacePublications\" ADD COLUMN \"openProposalData\" BLOB"
            )
            .execute(db)
        }
        migrator.registerMigration("Keep source workspace proposals across authoring sessions") {
            db in
            try #sql("""
                CREATE TABLE "sourceWorkspaceOpenProposals" (
                  "id" TEXT PRIMARY KEY NOT NULL,
                  "proposalData" BLOB NOT NULL
                ) STRICT
                """)
                .execute(db)
            try #sql("""
                INSERT INTO "sourceWorkspaceOpenProposals" ("id", "proposalData")
                SELECT "id", "openProposalData"
                FROM "sourceWorkspacePublications"
                WHERE "openProposalData" IS NOT NULL
                ON CONFLICT ("id") DO UPDATE SET "proposalData" = excluded."proposalData"
                """)
                .execute(db)
        }
        migrator.registerMigration("Persist patch-only workspace proposal publication") { db in
            let columns = try db.columns(in: "sourceWorkspacePublications").map(\.name)
            if !columns.contains("preparedSubmissionID") {
                try #sql(
                    "ALTER TABLE \"sourceWorkspacePublications\" ADD COLUMN \"preparedSubmissionID\" TEXT"
                )
                .execute(db)
            }
            if !columns.contains("preparedPublicationData") {
                try #sql(
                    "ALTER TABLE \"sourceWorkspacePublications\" ADD COLUMN \"preparedPublicationData\" BLOB"
                )
                .execute(db)
            }
            if !columns.contains("publishedSubmissionID") {
                try #sql(
                    "ALTER TABLE \"sourceWorkspacePublications\" ADD COLUMN \"publishedSubmissionID\" TEXT"
                )
                .execute(db)
            }
            if !columns.contains("publishedProposalData") {
                try #sql(
                    "ALTER TABLE \"sourceWorkspacePublications\" ADD COLUMN \"publishedProposalData\" BLOB"
                )
                .execute(db)
            }
        }
        migrator.registerMigration("Model one exact source workspace context") { db in
            try #sql("""
                CREATE TABLE "sourceWorkspaceContexts" (
                  "id" TEXT PRIMARY KEY NOT NULL,
                  "contextData" BLOB NOT NULL
                ) STRICT
                """)
                .execute(db)
            try #sql("""
                CREATE TABLE "sourceWorkspaceProposalReceipts" (
                  "id" TEXT PRIMARY KEY NOT NULL,
                  "workspaceID" TEXT NOT NULL,
                  "proposalData" BLOB NOT NULL
                ) STRICT
                """)
                .execute(db)
            try #sql("""
                CREATE INDEX "sourceWorkspaceProposalReceipts_workspaceID"
                ON "sourceWorkspaceProposalReceipts" ("workspaceID")
                """)
                .execute(db)
            try #sql("""
                CREATE TABLE "sourceWorkspaceProposalRepairs" (
                  "id" TEXT PRIMARY KEY NOT NULL,
                  "proposalData" BLOB NOT NULL,
                  "patchData" BLOB NOT NULL
                ) STRICT
                """)
                .execute(db)

            let openProposals = Dictionary(
                uniqueKeysWithValues: try LegacyWorkspaceOpenProposalRecord.all
                    .fetchAll(db)
                    .map { ($0.id, $0.proposalData) }
            )
            let legacyPublications = try LegacyWorkspacePublicationRecord.all.fetchAll(db)
            var recordedProposals = openProposals
            for legacy in legacyPublications {
                guard let proposalData = legacy.publishedProposalData ?? legacy.mutationData,
                      let proposal = try? decode(WorkspaceProposal.self, from: proposalData)
                else { continue }
                let encodedProposal = try encode(proposal)
                recordedProposals[legacy.id] = encodedProposal
                try saveReceipt(proposal, workspaceID: legacy.id, in: db)

                let checkpoint = legacy.submissionData.flatMap {
                    try? decode(WorkspacePublicationCheckpoint.self, from: $0)
                }
                let patchData = try checkpoint.map { try encode($0.changes) }
                    ?? legacy.capturedChangesData
                if let patchData,
                   (try? decode(SourcePatch.self, from: patchData)) != nil {
                    try WorkspaceProposalRepairRecord.upsert {
                        WorkspaceProposalRepairRecord(
                            id: legacy.id,
                            proposalData: encodedProposal,
                            patchData: patchData
                        )
                    }
                    .execute(db)
                }
            }
            for selection in try SourceWorkspaceSelectionRecord.all.fetchAll(db) {
                let context: WorkspaceEditingContext
                let installation = try SourceWorkspaceInstallationRecord
                    .find(selection.id)
                    .fetchOne(db)
                if let proposalData = recordedProposals[selection.id],
                   let proposal = try? decode(WorkspaceProposal.self, from: proposalData),
                   installation?.revision == proposal.revision.rawValue {
                    context = .proposal(proposal)
                    try saveReceipt(proposal, workspaceID: selection.id, in: db)
                } else {
                    let workspace = try SourceWorkspace(id: selection.id)
                    let reference = WorkspaceBranchReference(
                        branch: WorkspaceBranch(rawValue: selection.branch),
                        revision: WorkspaceRevision(rawValue: selection.revision)
                    )
                    context = selection.branch == workspace.defaultBranch
                        ? .published(reference)
                        : .branch(reference)
                }
                let contextData = try encode(context)
                try WorkspaceContextRecord.upsert {
                    WorkspaceContextRecord(
                        id: selection.id,
                        contextData: contextData
                    )
                }
                .execute(db)
            }
        }
    }

    private static func saveReceipt(
        _ proposal: WorkspaceProposal,
        workspaceID: SourceWorkspace.ID,
        in db: Database
    ) throws {
        let proposalData = try encode(proposal)
        try WorkspaceProposalReceiptRecord.upsert {
            WorkspaceProposalReceiptRecord(
                id: proposal.id.rawValue,
                workspaceID: workspaceID,
                proposalData: proposalData
            )
        }
        .execute(db)
    }
}

public enum SourceWorkspaceEditingState {
    /// Removes rows that exist only while authoring is active.
    ///
    /// The exact selected context, its installed revision, publication receipts, and any
    /// post-record repair journal are durable workspace state. Restoring attendee data must not
    /// erase them: they are what lets the next authoring session mount the same coherent context.
    public static func deactivate(
        _ workspaceID: SourceWorkspace.ID,
        in database: Database
    ) throws {
        try WorkspaceAuthoringActivationRecord.find(workspaceID).delete().execute(database)
        try SourceWorkspaceInstallationRecord.find(workspaceID).delete().execute(database)
        try WorkspaceRelationshipRecord
            .where { $0.id.workspaceID.eq(workspaceID) }
            .delete()
            .execute(database)
    }
}

public struct SourceWorkspaceContextStore: Sendable {
    public init(database: any DatabaseWriter) {
        self.persistence = WorkspacePublicationPersistence(database: database)
    }

    private let persistence: WorkspacePublicationPersistence

    public func load(_ workspaceID: SourceWorkspace.ID) throws -> WorkspaceEditingContext? {
        try persistence.optionalContext(workspaceID)
    }

    public func save(
        _ context: WorkspaceEditingContext,
        workspaceID: SourceWorkspace.ID
    ) async throws {
        try await persistence.saveContext(context, workspaceID: workspaceID)
    }

    /// Advances the main database's workspace revision and exact mounted context atomically.
    public func saveProposalContext(
        _ proposal: WorkspaceProposal,
        workspaceID: SourceWorkspace.ID
    ) async throws {
        try await persistence.saveProposalContext(
            proposal,
            workspaceID: workspaceID
        )
    }
}

public struct SourceWorkspaceProposalReceiptsRequest: FetchKeyRequest {
    public init(workspaceID: SourceWorkspace.ID) {
        self.workspaceID = workspaceID
    }

    public let workspaceID: SourceWorkspace.ID

    public func fetch(_ db: Database) throws -> [WorkspaceProposal] {
        try WorkspaceProposalReceiptRecord
            .where { $0.workspaceID.eq(workspaceID) }
            .fetchAll(db)
            .map { try decode(WorkspaceProposal.self, from: $0.proposalData) }
    }
}

public struct SourceWorkspaceProposalReceiptStore: Sendable {
    public init(database: any DatabaseWriter) {
        self.database = database
    }

    private let database: any DatabaseWriter

    /// Removes delivery receipts once the server-owned proposal projection has observed them.
    public func acknowledge(_ proposalIDs: [WorkspaceProposalID]) async throws {
        guard !proposalIDs.isEmpty else { return }
        try await database.write { db in
            for proposalID in proposalIDs {
                try WorkspaceProposalReceiptRecord.find(proposalID.rawValue)
                    .delete()
                    .execute(db)
            }
        }
    }
}

public struct SourceWorkspaceProposalRepairRequest: FetchKeyRequest {
    public init(workspaceID: SourceWorkspace.ID) {
        self.workspaceID = workspaceID
    }

    public let workspaceID: SourceWorkspace.ID

    public func fetch(_ db: Database) throws -> SourceWorkspaceProposalRepair? {
        try WorkspaceProposalRepairRecord.find(workspaceID)
            .fetchOne(db)
            .map {
                SourceWorkspaceProposalRepair(
                    proposal: try decode(WorkspaceProposal.self, from: $0.proposalData),
                    patch: try decode(SourcePatch.self, from: $0.patchData)
                )
            }
    }
}

public struct SourceWorkspaceProposalRepairStore: Sendable {
    public init(database: any DatabaseWriter) {
        self.database = database
    }

    private let database: any DatabaseWriter

    public func load(
        _ workspaceID: SourceWorkspace.ID
    ) throws -> SourceWorkspaceProposalRepair? {
        try database.read { db in
            try SourceWorkspaceProposalRepairRequest(workspaceID: workspaceID).fetch(db)
        }
    }

    public func complete(_ workspaceID: SourceWorkspace.ID) async throws {
        try await WorkspacePublicationPersistence(database: database)
            .completeRepair(workspaceID: workspaceID)
    }
}

struct WorkspacePublicationPersistence: Sendable {
    enum Error: Swift.Error {
        case contextMissing(SourceWorkspace.ID)
    }

    let database: any DatabaseWriter

    func checkpoint(
        workspaceID: SourceWorkspace.ID,
        attempt: WorkspaceProposalAttempt<SourcePatch>
    ) async throws -> WorkspacePublicationCheckpoint {
        if let existing = try checkpoint(workspaceID), existing.represents(attempt) {
            return existing
        }
        let checkpoint = WorkspacePublicationCheckpoint(attempt: attempt)
        let data = try encode(checkpoint)
        try await database.write { db in
            try ensureLegacyRecord(workspaceID, in: db)
            try LegacyWorkspacePublicationRecord.find(workspaceID).update {
                $0.submissionData = #bind(data as Data?)
                $0.preparedSubmissionID = #bind(nil as String?)
                $0.preparedPublicationData = #bind(nil as Data?)
                $0.publishedSubmissionID = #bind(nil as String?)
                $0.publishedProposalData = #bind(nil as Data?)
            }
            .execute(db)
        }
        return checkpoint
    }

    func checkpoint(
        _ workspaceID: SourceWorkspace.ID
    ) throws -> WorkspacePublicationCheckpoint? {
        try database.read { db in
            try LegacyWorkspacePublicationRecord.find(workspaceID).fetchOne(db)?.submissionData
        }
        .flatMap { try? decode(WorkspacePublicationCheckpoint.self, from: $0) }
    }

    func preparedPublication(
        workspaceID: SourceWorkspace.ID,
        checkpointID: UUID
    ) throws -> TangledPatchOnlyProposalPublicationRequest? {
        let id = checkpointID.uuidString.lowercased()
        return try database.read { db in
            guard let record = try LegacyWorkspacePublicationRecord.find(workspaceID).fetchOne(db),
                  record.preparedSubmissionID == id,
                  let data = record.preparedPublicationData
            else { return nil }
            return try decode(TangledPatchOnlyProposalPublicationRequest.self, from: data)
        }
    }

    func savePreparedPublication(
        _ request: TangledPatchOnlyProposalPublicationRequest,
        workspaceID: SourceWorkspace.ID,
        checkpointID: UUID
    ) async throws {
        let data = try encode(request)
        let id = checkpointID.uuidString.lowercased()
        try await database.write { db in
            try ensureLegacyRecord(workspaceID, in: db)
            try LegacyWorkspacePublicationRecord.find(workspaceID).update {
                $0.preparedSubmissionID = #bind(id as String?)
                $0.preparedPublicationData = #bind(data as Data?)
            }
            .execute(db)
        }
    }

    func publishedProposal(
        workspaceID: SourceWorkspace.ID,
        checkpointID: UUID
    ) throws -> WorkspaceProposal? {
        let id = checkpointID.uuidString.lowercased()
        return try database.read { db in
            guard let record = try LegacyWorkspacePublicationRecord.find(workspaceID).fetchOne(db),
                  record.publishedSubmissionID == id,
                  let data = record.publishedProposalData
            else { return nil }
            return try decode(WorkspaceProposal.self, from: data)
        }
    }

    /// Atomically records the remote commit point and the local repair checkpoint.
    func savePublishedProposal(
        _ proposal: WorkspaceProposal,
        checkpoint: WorkspacePublicationCheckpoint,
        workspaceID: SourceWorkspace.ID
    ) async throws {
        let proposalData = try encode(proposal)
        let patchData = try encode(checkpoint.changes)
        let checkpointID = checkpoint.id.uuidString.lowercased()
        try await database.write { db in
            try ensureLegacyRecord(workspaceID, in: db)
            try LegacyWorkspacePublicationRecord.find(workspaceID).update {
                $0.publishedSubmissionID = #bind(checkpointID as String?)
                $0.publishedProposalData = #bind(proposalData as Data?)
            }
            .execute(db)
            try WorkspaceProposalReceiptRecord.upsert {
                WorkspaceProposalReceiptRecord(
                    id: proposal.id.rawValue,
                    workspaceID: workspaceID,
                    proposalData: proposalData
                )
            }
            .execute(db)
            try WorkspaceProposalRepairRecord.upsert {
                WorkspaceProposalRepairRecord(
                    id: workspaceID,
                    proposalData: proposalData,
                    patchData: patchData
                )
            }
            .execute(db)
        }
    }

    func optionalContext(_ workspaceID: SourceWorkspace.ID) throws -> WorkspaceEditingContext? {
        try database.read { db in
            try WorkspaceContextRecord.find(workspaceID).fetchOne(db)?.contextData
        }
        .map { try decode(WorkspaceEditingContext.self, from: $0) }
    }

    func context(_ workspaceID: SourceWorkspace.ID) throws -> WorkspaceEditingContext {
        guard let context = try optionalContext(workspaceID) else {
            throw Error.contextMissing(workspaceID)
        }
        return context
    }

    func saveContext(
        _ context: WorkspaceEditingContext,
        workspaceID: SourceWorkspace.ID
    ) async throws {
        let data = try encode(context)
        try await database.write { db in
            try WorkspaceContextRecord.upsert {
                WorkspaceContextRecord(id: workspaceID, contextData: data)
            }
            .execute(db)
        }
    }

    func saveProposalContext(
        _ proposal: WorkspaceProposal,
        workspaceID: SourceWorkspace.ID
    ) async throws {
        let contextData = try encode(WorkspaceEditingContext.proposal(proposal))
        try await database.write { db in
            try SourceWorkspaceInstallationRecord.upsert {
                SourceWorkspaceInstallationRecord(
                    id: workspaceID,
                    revision: proposal.revision.rawValue
                )
            }
            .execute(db)
            try SourceWorkspaceSelectionRecord.upsert {
                SourceWorkspaceSelectionRecord(
                    id: workspaceID,
                    branch: proposal.target.branch.rawValue,
                    revision: proposal.revision.rawValue
                )
            }
            .execute(db)
            try WorkspaceContextRecord.upsert {
                WorkspaceContextRecord(id: workspaceID, contextData: contextData)
            }
            .execute(db)
        }
    }

    func saveReceiptAndRepair(
        proposal: WorkspaceProposal,
        patch: SourcePatch,
        workspaceID: SourceWorkspace.ID
    ) async throws {
        let proposalData = try encode(proposal)
        let patchData = try encode(patch)
        try await database.write { db in
            try WorkspaceProposalReceiptRecord.upsert {
                WorkspaceProposalReceiptRecord(
                    id: proposal.id.rawValue,
                    workspaceID: workspaceID,
                    proposalData: proposalData
                )
            }
            .execute(db)
            try WorkspaceProposalRepairRecord.upsert {
                WorkspaceProposalRepairRecord(
                    id: workspaceID,
                    proposalData: proposalData,
                    patchData: patchData
                )
            }
            .execute(db)
        }
    }

    func completeRepair(workspaceID: SourceWorkspace.ID) async throws {
        try await database.write { db in
            try WorkspaceProposalRepairRecord.find(workspaceID).delete().execute(db)
            try LegacyWorkspacePublicationRecord.find(workspaceID).update {
                $0.captureRequestID = #bind(nil as String?)
                $0.capturedChangesData = #bind(nil as Data?)
                $0.submissionData = #bind(nil as Data?)
                $0.pushedSubmissionID = #bind(nil as String?)
                $0.commitData = #bind(nil as Data?)
                $0.recordedSubmissionID = #bind(nil as String?)
                $0.mutationData = #bind(nil as Data?)
                $0.proposalTimestamp = #bind(nil as String?)
                $0.preparedSubmissionID = #bind(nil as String?)
                $0.preparedPublicationData = #bind(nil as Data?)
                $0.publishedSubmissionID = #bind(nil as String?)
                $0.publishedProposalData = #bind(nil as Data?)
            }
            .execute(db)
        }
    }

    private func ensureLegacyRecord(
        _ workspaceID: SourceWorkspace.ID,
        in db: Database
    ) throws {
        guard try LegacyWorkspacePublicationRecord.find(workspaceID).fetchCount(db) == 0 else {
            return
        }
        try LegacyWorkspacePublicationRecord.insert {
            LegacyWorkspacePublicationRecord(id: workspaceID)
        }
        .execute(db)
    }
}

func encode<Value: Encodable>(_ value: Value) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(value)
}

func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
    try JSONDecoder().decode(type, from: data)
}
