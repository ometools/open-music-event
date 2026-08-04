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
    var openProposalData: Data?

    init(
        id: SourceWorkspace.ID,
        captureRequestID: String? = nil,
        capturedChangesData: Data? = nil,
        submissionData: Data? = nil,
        pushedSubmissionID: String? = nil,
        commitData: Data? = nil,
        recordedSubmissionID: String? = nil,
        mutationData: Data? = nil,
        proposalTimestamp: String? = nil,
        openProposalData: Data? = nil
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
        self.openProposalData = openProposalData
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
    }
}

/// The durable identity of the proposal branch currently owned by a source workspace.
/// Transient submission retry state remains private to the publication implementation.
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

/// The proposal branch currently owned by a source workspace.
///
/// This request observes the workspace publication table so database-backed viewers update when
/// publication creates, advances, merges, or removes the open proposal.
public struct SourceWorkspaceOpenProposalRequest: FetchKeyRequest {
    public init(workspaceID: SourceWorkspace.ID) {
        self.workspaceID = workspaceID
    }

    public let workspaceID: SourceWorkspace.ID

    public func fetch(_ db: Database) throws -> WorkspaceProposal? {
        try WorkspacePublicationRecord.find(workspaceID)
            .fetchOne(db)?
            .openProposalData
            .map { try decode(WorkspaceProposal.self, from: $0) }
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
    ) throws -> WorkspaceCommit? {
        let submissionID = submissionID.rawValue.uuidString.lowercased()
        return try database.read { db in
            guard let record = try WorkspacePublicationRecord.find(workspaceID).fetchOne(db),
                  record.pushedSubmissionID == submissionID,
                  let data = record.commitData
            else { return nil }
            return try decode(WorkspaceCommit.self, from: data)
        }
    }

    func savePushedCommit(
        _ commit: WorkspaceCommit,
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

    func mutation(
        workspaceID: SourceWorkspace.ID,
        submissionID: WorkspaceSubmissionID
    ) throws -> WorkspaceProposalMutation? {
        let submissionID = submissionID.rawValue.uuidString.lowercased()
        return try database.read { db in
            guard let record = try WorkspacePublicationRecord.find(workspaceID).fetchOne(db),
                  record.recordedSubmissionID == submissionID,
                  let data = record.mutationData
            else { return nil }
            return try decode(WorkspaceProposalMutation.self, from: data)
        }
    }

    func saveMutation(
        _ mutation: WorkspaceProposalMutation,
        workspaceID: SourceWorkspace.ID,
        submissionID: WorkspaceSubmissionID
    ) async throws {
        let data = try encode(mutation)
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
            try WorkspacePublicationRecord.find(workspaceID).fetchOne(db)?.openProposalData
        }
        .map { try decode(WorkspaceProposal.self, from: $0) }
    }

    func saveOpenProposal(
        _ proposal: WorkspaceProposal?,
        workspaceID: SourceWorkspace.ID
    ) async throws {
        let data = try proposal.map(encode)
        try await database.write { db in
            try ensureRecord(workspaceID, in: db)
            try WorkspacePublicationRecord.find(workspaceID).update {
                $0.openProposalData = #bind(data as Data?)
            }
            .execute(db)
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
