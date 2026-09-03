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

/// Retained only so an explicit workspace reset can clear rows written by older versions.
@Table("sourceWorkspaceContexts")
struct LegacyWorkspaceContextRecord: Equatable, Sendable, Identifiable {
    var id: SourceWorkspace.ID
    var contextData: Data
}

/// Retained only so an explicit workspace reset can clear obsolete repair state.
@Table("sourceWorkspaceProposalRepairs")
struct LegacyWorkspaceProposalRepairRecord: Equatable, Sendable, Identifiable {
    var id: SourceWorkspace.ID
    var proposalData: Data
    var patchData: Data
}

@Table("sourceWorkspaceProposalReceipts")
struct WorkspaceProposalReceiptRecord: Equatable, Sendable, Identifiable {
    var id: String
    var workspaceID: SourceWorkspace.ID
    var proposalData: Data
}

/// OME-private transport recovery. This is deliberately not part of Workspace's product model.
struct WorkspacePublicationCheckpoint: Codable, Equatable, Sendable {
    var changes: SourcePatch
    var details: WorkspaceProposalDetails
    var id: UUID
    var target: WorkspaceBranchReference

    init(attempt: WorkspaceProposalAttempt<SourcePatch>, id: UUID = UUID()) {
        self.changes = attempt.changes
        self.details = attempt.details
        self.id = id
        self.target = attempt.target
    }

    func represents(_ attempt: WorkspaceProposalAttempt<SourcePatch>) -> Bool {
        return changes == attempt.changes
            && target == attempt.target
            && details == attempt.details
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

            for legacy in try LegacyWorkspaceOpenProposalRecord.all.fetchAll(db) {
                guard let proposal = try? decode(WorkspaceProposal.self, from: legacy.proposalData)
                else { continue }
                try saveReceipt(proposal, workspaceID: legacy.id, in: db)
            }
            for legacy in try LegacyWorkspacePublicationRecord.all.fetchAll(db) {
                guard let proposalData = legacy.publishedProposalData ?? legacy.mutationData,
                      let proposal = try? decode(WorkspaceProposal.self, from: proposalData)
                else { continue }
                try saveReceipt(proposal, workspaceID: legacy.id, in: db)
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
    /// The selected branch baseline and publication delivery receipts remain durable.
    /// Proposals are independent records and are never part of workspace editing state.
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

public struct SourceWorkspaceBaselineStore: Sendable {
    public init(database: any DatabaseWriter) {
        self.persistence = WorkspacePublicationPersistence(database: database)
    }

    private let persistence: WorkspacePublicationPersistence

    public func load(_ workspaceID: SourceWorkspace.ID) throws -> WorkspaceBranchReference? {
        try persistence.optionalBaseline(workspaceID)
    }

    public func save(
        _ baseline: WorkspaceBranchReference,
        workspaceID: SourceWorkspace.ID
    ) async throws {
        try await persistence.saveBaseline(
            baseline,
            workspaceID: workspaceID
        )
    }

    public func install(
        _ baseline: WorkspaceBranchReference,
        workspaceID: SourceWorkspace.ID
    ) async throws {
        try await persistence.installBaseline(
            baseline,
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

struct WorkspacePublicationPersistence: Sendable {
    enum Error: Swift.Error {
        case baselineMissing(SourceWorkspace.ID)
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

    /// Repoints a frozen attempt at a newly reconciled base and invalidates bytes prepared for the
    /// old base. The attempt identity and receipt ID remain stable for retry recovery.
    func reconcileCheckpoint(
        workspaceID: SourceWorkspace.ID,
        attempt: WorkspaceProposalAttempt<SourcePatch>,
        target: WorkspaceBranchReference
    ) async throws {
        guard var checkpoint = try checkpoint(workspaceID), checkpoint.represents(attempt) else {
            return
        }
        checkpoint.target = target
        let data = try encode(checkpoint)
        try await database.write { db in
            try LegacyWorkspacePublicationRecord.find(workspaceID).update {
                $0.submissionData = #bind(data as Data?)
                $0.preparedSubmissionID = #bind(nil as String?)
                $0.preparedPublicationData = #bind(nil as Data?)
            }
            .execute(db)
        }
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

    /// Records the remote commit point for retry and projection delivery.
    ///
    /// Publishing a proposal does not install it as the workspace baseline. The writable database
    /// remains compared with the exact branch revision from which the proposal was created.
    func savePublishedProposal(
        _ proposal: WorkspaceProposal,
        checkpoint: WorkspacePublicationCheckpoint,
        workspaceID: SourceWorkspace.ID
    ) async throws {
        let proposalData = try encode(proposal)
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
        }
    }

    func optionalBaseline(
        _ workspaceID: SourceWorkspace.ID
    ) throws -> WorkspaceBranchReference? {
        try database.read { db in
            try SourceWorkspaceSelectionRecord.find(workspaceID).fetchOne(db)
        }
        .map { selection in
            WorkspaceBranchReference(
                branch: WorkspaceBranch(rawValue: selection.branch),
                revision: WorkspaceRevision(rawValue: selection.revision)
            )
        }
    }

    func baseline(_ workspaceID: SourceWorkspace.ID) throws -> WorkspaceBranchReference {
        guard let baseline = try optionalBaseline(workspaceID) else {
            throw Error.baselineMissing(workspaceID)
        }
        return baseline
    }

    func saveBaseline(
        _ baseline: WorkspaceBranchReference,
        workspaceID: SourceWorkspace.ID
    ) async throws {
        try await database.write { db in
            try SourceWorkspaceSelectionRecord.upsert {
                SourceWorkspaceSelectionRecord(
                    id: workspaceID,
                    branch: baseline.branch.rawValue,
                    revision: baseline.revision.rawValue
                )
            }
            .execute(db)
        }
    }

    func installBaseline(
        _ baseline: WorkspaceBranchReference,
        workspaceID: SourceWorkspace.ID
    ) async throws {
        try await database.write { db in
            try SourceWorkspaceInstallationRecord.upsert {
                SourceWorkspaceInstallationRecord(
                    id: workspaceID,
                    revision: baseline.revision.rawValue
                )
            }
            .execute(db)
            try SourceWorkspaceSelectionRecord.upsert {
                SourceWorkspaceSelectionRecord(
                    id: workspaceID,
                    branch: baseline.branch.rawValue,
                    revision: baseline.revision.rawValue
                )
            }
            .execute(db)
        }
    }

    func completePublication(workspaceID: SourceWorkspace.ID) async throws {
        try await database.write { db in
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
