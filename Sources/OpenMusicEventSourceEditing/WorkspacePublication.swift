import ComposableWorkspace
import Foundation
import SQLiteData
import SourceEditing

@Table("sourceWorkspacePublications")
struct WorkspacePublicationRecord: Equatable, Sendable, Identifiable {
    var id: SourceWorkspace.ID
    var captureRequestID: String?
    var capturedChangesData: Data?
    var submissionData: Data?
    var pushedSubmissionID: String?
    var commitData: Data?
    var recordedSubmissionID: String?
    var mutationData: Data?
    var proposalTimestamp: String?

    init(
        id: SourceWorkspace.ID,
        captureRequestID: String? = nil,
        capturedChangesData: Data? = nil,
        submissionData: Data? = nil,
        pushedSubmissionID: String? = nil,
        commitData: Data? = nil,
        recordedSubmissionID: String? = nil,
        mutationData: Data? = nil,
        proposalTimestamp: String? = nil
    ) {
        self.id = id
        self.captureRequestID = captureRequestID
        self.capturedChangesData = capturedChangesData
        self.submissionData = submissionData
        self.pushedSubmissionID = pushedSubmissionID
        self.commitData = commitData
        self.recordedSubmissionID = recordedSubmissionID
        self.mutationData = mutationData
        self.proposalTimestamp = proposalTimestamp
    }
}

@Table("sourceWorkspaceOpenProposals")
struct WorkspaceOpenProposalRecord: Equatable, Sendable, Identifiable {
    var id: SourceWorkspace.ID
    var proposalData: Data
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
    }
}

/// Durable workspace state that is meaningful only while this device is authoring the source.
public enum SourceWorkspaceEditingState {
    /// Removes the writable baseline and all in-flight publication state in the caller's
    /// transaction. The reference database belongs to the source checkout and is not mutated here.
    public static func discard(
        _ workspaceID: SourceWorkspace.ID,
        in database: Database
    ) throws {
        try WorkspacePublicationRecord.find(workspaceID).delete().execute(database)
        try WorkspaceAuthoringActivationRecord.find(workspaceID).delete().execute(database)
        try SourceWorkspaceInstallationRecord.find(workspaceID).delete().execute(database)
        try WorkspaceRelationshipRecord
            .where { $0.id.workspaceID.eq(workspaceID) }
            .delete()
            .execute(database)
    }
}

/// The proposal currently tracked by a source workspace.
/// Transient publication retry state remains private to the publication implementation.
public struct SourceWorkspaceOpenProposalStore: Sendable {
    public init(database: any DatabaseWriter) {
        self.persistence = WorkspacePublicationPersistence(database: database)
    }

    private let persistence: WorkspacePublicationPersistence

    public func load(_ workspaceID: SourceWorkspace.ID) throws -> WorkspaceProposal? {
        try persistence.openProposal(workspaceID)
    }

    public func save(
        _ proposal: WorkspaceProposal?,
        workspaceID: SourceWorkspace.ID
    ) async throws {
        try await persistence.saveOpenProposal(proposal, workspaceID: workspaceID)
    }
}

/// The durable Git transport checkpoint for a workspace proposal publication.
///
/// `ComposableWorkspace` treats a proposal revision as opaque. OME still creates and pushes a
/// temporary Git commit to produce Tangled's patch blob, so that transport-specific state remains
/// durable here without leaking back into the workspace domain.
public struct SourceWorkspacePublicationCommit: Codable, Equatable, Sendable {
    public var parentRevision: WorkspaceRevision
    public var source: WorkspaceBranchReference

    public init(
        parentRevision: WorkspaceRevision,
        source: WorkspaceBranchReference
    ) {
        self.parentRevision = parentRevision
        self.source = source
    }
}

/// A durable publication that created a local commit but has not yet settled the workspace.
///
/// Source preparation uses this checkpoint to distinguish an interrupted publication from an
/// unexplained repository revision mismatch. The proposal commit remains reachable from its local
/// branch while preparation restores the settled editing revision.
public struct SourceWorkspacePublicationCheckpoint: Equatable, Sendable {
    public var submission: WorkspaceSubmission<SourcePatch>
    public var commit: SourceWorkspacePublicationCommit

    public init(
        submission: WorkspaceSubmission<SourcePatch>,
        commit: SourceWorkspacePublicationCommit
    ) {
        self.submission = submission
        self.commit = commit
    }
}

public struct SourceWorkspacePublicationCheckpointStore: Sendable {
    public init(database: any DatabaseWriter) {
        self.persistence = WorkspacePublicationPersistence(database: database)
    }

    private let persistence: WorkspacePublicationPersistence

    public func load(
        _ workspaceID: SourceWorkspace.ID
    ) throws -> SourceWorkspacePublicationCheckpoint? {
        guard let submission = try persistence.submission(workspaceID),
              let commit = try persistence.pushedCommit(
                workspaceID: workspaceID,
                submissionID: submission.id
              )
        else { return nil }
        return SourceWorkspacePublicationCheckpoint(
            submission: submission,
            commit: commit
        )
    }
}

/// The proposal currently tracked by a source workspace.
public struct SourceWorkspaceOpenProposalRequest: FetchKeyRequest {
    public init(workspaceID: SourceWorkspace.ID) {
        self.workspaceID = workspaceID
    }

    public let workspaceID: SourceWorkspace.ID

    public func fetch(_ db: Database) throws -> WorkspaceProposal? {
        try WorkspaceOpenProposalRecord.find(workspaceID)
            .fetchOne(db)
            .map { try decode(WorkspaceProposal.self, from: $0.proposalData) }
    }
}

struct WorkspacePublicationPersistence: Sendable {
    enum Error: Swift.Error {
        case workspaceNotPrepared(SourceWorkspace.ID)
    }

    let database: any DatabaseWriter

    func capture(
        workspaceID: SourceWorkspace.ID,
        requestID: WorkspaceSubmissionID
    ) throws -> SourcePatch? {
        let requestID = requestID.rawValue.uuidString.lowercased()
        return try database.read { db in
            guard let record = try WorkspacePublicationRecord.find(workspaceID).fetchOne(db),
                  record.captureRequestID == requestID,
                  let data = record.capturedChangesData
            else { return nil }
            return try decode(SourcePatch.self, from: data)
        }
    }

    func saveCapture(
        _ changes: SourcePatch,
        workspaceID: SourceWorkspace.ID,
        requestID: WorkspaceSubmissionID
    ) async throws {
        let data = try encode(changes)
        let requestID = requestID.rawValue.uuidString.lowercased()
        try await database.write { db in
            try ensureRecord(workspaceID, in: db)
            try WorkspacePublicationRecord.find(workspaceID).update {
                $0.captureRequestID = #bind(requestID as String?)
                $0.capturedChangesData = #bind(data as Data?)
            }
            .execute(db)
        }
    }

    func submission(
        _ workspaceID: SourceWorkspace.ID
    ) throws -> WorkspaceSubmission<SourcePatch>? {
        try database.read { db in
            try WorkspacePublicationRecord.find(workspaceID).fetchOne(db)?.submissionData
        }
        .map { try decode(WorkspaceSubmission<SourcePatch>.self, from: $0) }
    }

    func save(
        _ submission: WorkspaceSubmission<SourcePatch>,
        workspaceID: SourceWorkspace.ID
    ) async throws {
        let data = try encode(submission)
        try await database.write { db in
            try ensureRecord(workspaceID, in: db)
            try WorkspacePublicationRecord.find(workspaceID).update {
                $0.submissionData = #bind(data as Data?)
            }
            .execute(db)
        }
    }

    func pushedCommit(
        workspaceID: SourceWorkspace.ID,
        submissionID: WorkspaceSubmissionID
    ) throws -> SourceWorkspacePublicationCommit? {
        let submissionID = submissionID.rawValue.uuidString.lowercased()
        return try database.read { db in
            guard let record = try WorkspacePublicationRecord.find(workspaceID).fetchOne(db),
                  record.pushedSubmissionID == submissionID,
                  let data = record.commitData
            else { return nil }
            return try decode(SourceWorkspacePublicationCommit.self, from: data)
        }
    }

    func savePushedCommit(
        _ commit: SourceWorkspacePublicationCommit,
        workspaceID: SourceWorkspace.ID,
        submissionID: WorkspaceSubmissionID
    ) async throws {
        let data = try encode(commit)
        let submissionID = submissionID.rawValue.uuidString.lowercased()
        try await database.write { db in
            try ensureRecord(workspaceID, in: db)
            try WorkspacePublicationRecord.find(workspaceID).update {
                $0.pushedSubmissionID = #bind(submissionID as String?)
                $0.commitData = #bind(data as Data?)
            }
            .execute(db)
        }
    }

    func publishedProposal(
        workspaceID: SourceWorkspace.ID,
        submissionID: WorkspaceSubmissionID
    ) throws -> WorkspaceProposal? {
        let submissionID = submissionID.rawValue.uuidString.lowercased()
        return try database.read { db in
            guard let record = try WorkspacePublicationRecord.find(workspaceID).fetchOne(db),
                  record.recordedSubmissionID == submissionID,
                  let data = record.mutationData
            else { return nil }
            return try? decode(WorkspaceProposal.self, from: data)
        }
    }

    func savePublishedProposal(
        _ proposal: WorkspaceProposal,
        workspaceID: SourceWorkspace.ID,
        submissionID: WorkspaceSubmissionID
    ) async throws {
        let data = try encode(proposal)
        let submissionID = submissionID.rawValue.uuidString.lowercased()
        try await database.write { db in
            try ensureRecord(workspaceID, in: db)
            try WorkspacePublicationRecord.find(workspaceID).update {
                $0.recordedSubmissionID = #bind(submissionID as String?)
                $0.mutationData = #bind(data as Data?)
            }
            .execute(db)
        }
    }

    func proposalTimestamp(
        workspaceID: SourceWorkspace.ID,
        submissionID: WorkspaceSubmissionID,
        makeTimestamp: @escaping @Sendable () -> String
    ) async throws -> String {
        let submissionID = submissionID.rawValue.uuidString.lowercased()
        return try await database.write { db in
            guard let record = try WorkspacePublicationRecord.find(workspaceID).fetchOne(db)
            else { throw Error.workspaceNotPrepared(workspaceID) }
            if record.recordedSubmissionID == submissionID,
               let timestamp = record.proposalTimestamp {
                return timestamp
            }
            let timestamp = makeTimestamp()
            try WorkspacePublicationRecord.find(workspaceID).update {
                $0.recordedSubmissionID = #bind(submissionID as String?)
                $0.proposalTimestamp = #bind(timestamp as String?)
            }
            .execute(db)
            return timestamp
        }
    }

    func removeSubmission(
        workspaceID: SourceWorkspace.ID,
        submissionID: WorkspaceSubmissionID
    ) async throws {
        _ = submissionID
        try await database.write { db in
            try WorkspacePublicationRecord.find(workspaceID).update {
                $0.captureRequestID = #bind(nil as String?)
                $0.capturedChangesData = #bind(nil as Data?)
                $0.submissionData = #bind(nil as Data?)
                $0.pushedSubmissionID = #bind(nil as String?)
                $0.commitData = #bind(nil as Data?)
                $0.recordedSubmissionID = #bind(nil as String?)
                $0.mutationData = #bind(nil as Data?)
                $0.proposalTimestamp = #bind(nil as String?)
            }
            .execute(db)
        }
    }

    func openProposal(_ workspaceID: SourceWorkspace.ID) throws -> WorkspaceProposal? {
        try database.read { db in
            try WorkspaceOpenProposalRecord.find(workspaceID).fetchOne(db)?.proposalData
        }
        .map { try decode(WorkspaceProposal.self, from: $0) }
    }

    func saveOpenProposal(
        _ proposal: WorkspaceProposal?,
        workspaceID: SourceWorkspace.ID
    ) async throws {
        let data = try proposal.map(encode)
        try await database.write { db in
            if let data {
                try WorkspaceOpenProposalRecord.upsert {
                    WorkspaceOpenProposalRecord(id: workspaceID, proposalData: data)
                }
                .execute(db)
            } else {
                try WorkspaceOpenProposalRecord.find(workspaceID).delete().execute(db)
            }
        }
    }

    func ensureRecord(_ workspaceID: SourceWorkspace.ID, in db: Database) throws {
        guard try WorkspacePublicationRecord.find(workspaceID).fetchCount(db) == 0 else {
            return
        }
        try WorkspacePublicationRecord.insert {
            WorkspacePublicationRecord(id: workspaceID)
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
