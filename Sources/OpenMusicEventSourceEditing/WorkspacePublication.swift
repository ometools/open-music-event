import ComposableWorkspace
import Foundation
import SQLiteData
import SourceEditing

/// Durable publication progress for one editable workspace.
///
/// The row deliberately stores only workflow facts. The writable event data remains in
/// `defaultDatabase`, and the comparison baseline remains the workspace-owned attached database.
@Table("workspacePublications")
struct WorkspacePublicationRecord: Equatable, Sendable, Identifiable {
    var id: EditingWorkspaceRecord.ID
    var editingLineData: Data
    var captureRequestID: String?
    var capturedChangesData: Data?
    var submissionData: Data?
    var pushedSubmissionID: String?
    var commitData: Data?
    var checkoutPath: String?
    var recordedSubmissionID: String?
    var mutationData: Data?
    var proposalTimestamp: String?

    init(
        id: EditingWorkspaceRecord.ID,
        editingLineData: Data,
        captureRequestID: String? = nil,
        capturedChangesData: Data? = nil,
        submissionData: Data? = nil,
        pushedSubmissionID: String? = nil,
        commitData: Data? = nil,
        checkoutPath: String? = nil,
        recordedSubmissionID: String? = nil,
        mutationData: Data? = nil,
        proposalTimestamp: String? = nil
    ) {
        self.id = id
        self.editingLineData = editingLineData
        self.captureRequestID = captureRequestID
        self.capturedChangesData = capturedChangesData
        self.submissionData = submissionData
        self.pushedSubmissionID = pushedSubmissionID
        self.commitData = commitData
        self.checkoutPath = checkoutPath
        self.recordedSubmissionID = recordedSubmissionID
        self.mutationData = mutationData
        self.proposalTimestamp = proposalTimestamp
    }
}

public enum WorkspacePublicationMigrations {
    public static func register(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("Create OpenMusicEvent workspace publication schema") { db in
            try #sql("""
                CREATE TABLE IF NOT EXISTS "workspacePublications" (
                  "id" TEXT PRIMARY KEY NOT NULL
                    REFERENCES "editingWorkspaces"("id") ON DELETE CASCADE,
                  "editingLineData" BLOB NOT NULL,
                  "captureRequestID" TEXT,
                  "capturedChangesData" BLOB,
                  "submissionData" BLOB,
                  "pushedSubmissionID" TEXT,
                  "commitData" BLOB,
                  "checkoutPath" TEXT,
                  "recordedSubmissionID" TEXT,
                  "mutationData" BLOB,
                  "proposalTimestamp" TEXT
                ) STRICT
                """)
                .execute(db)
        }
    }
}

struct WorkspacePublicationPersistence: Sendable {
    enum Error: Swift.Error {
        case workspaceNotPrepared(EditingWorkspaceRecord.ID)
    }

    let database: any DatabaseWriter

    func line(_ workspaceID: EditingWorkspaceRecord.ID) throws -> WorkspaceEditingLine? {
        try database.read { db in
            try WorkspacePublicationRecord.find(workspaceID).fetchOne(db)
        }
        .map { try decode(WorkspaceEditingLine.self, from: $0.editingLineData) }
    }

    func establish(
        _ line: WorkspaceEditingLine,
        for workspaceID: EditingWorkspaceRecord.ID
    ) async throws -> WorkspaceEditingLine {
        let data = try encode(line)
        return try await database.write { db in
            if let existing = try WorkspacePublicationRecord.find(workspaceID).fetchOne(db) {
                return try decode(WorkspaceEditingLine.self, from: existing.editingLineData)
            }
            try WorkspacePublicationRecord.insert {
                WorkspacePublicationRecord(id: workspaceID, editingLineData: data)
            }
            .execute(db)
            return line
        }
    }

    func capture(
        workspaceID: EditingWorkspaceRecord.ID,
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
        workspaceID: EditingWorkspaceRecord.ID,
        requestID: WorkspaceSubmissionID
    ) async throws {
        let data = try encode(changes)
        let requestID = requestID.rawValue.uuidString.lowercased()
        try await database.write { db in
            try WorkspacePublicationRecord.find(workspaceID).update {
                $0.captureRequestID = #bind(requestID as String?)
                $0.capturedChangesData = #bind(data as Data?)
            }
            .execute(db)
        }
    }

    func submission(
        _ workspaceID: EditingWorkspaceRecord.ID
    ) throws -> WorkspaceSubmission<SourcePatch>? {
        try database.read { db in
            try WorkspacePublicationRecord.find(workspaceID).fetchOne(db)?.submissionData
        }
        .map { try decode(WorkspaceSubmission<SourcePatch>.self, from: $0) }
    }

    func save(
        _ submission: WorkspaceSubmission<SourcePatch>,
        workspaceID: EditingWorkspaceRecord.ID
    ) async throws {
        let data = try encode(submission)
        try await database.write { db in
            try WorkspacePublicationRecord.find(workspaceID).update {
                $0.submissionData = #bind(data as Data?)
            }
            .execute(db)
        }
    }

    func pushedCommit(
        workspaceID: EditingWorkspaceRecord.ID,
        submissionID: WorkspaceSubmissionID
    ) throws -> (WorkspaceCommit, URL)? {
        let submissionID = submissionID.rawValue.uuidString.lowercased()
        return try database.read { db in
            guard let record = try WorkspacePublicationRecord.find(workspaceID).fetchOne(db),
                  record.pushedSubmissionID == submissionID,
                  let data = record.commitData,
                  let path = record.checkoutPath
            else { return nil }
            return (
                try decode(WorkspaceCommit.self, from: data),
                URL(filePath: path, directoryHint: .isDirectory)
            )
        }
    }

    func savePushedCommit(
        _ commit: WorkspaceCommit,
        checkoutURL: URL,
        workspaceID: EditingWorkspaceRecord.ID,
        submissionID: WorkspaceSubmissionID
    ) async throws {
        let data = try encode(commit)
        let submissionID = submissionID.rawValue.uuidString.lowercased()
        try await database.write { db in
            try WorkspacePublicationRecord.find(workspaceID).update {
                $0.pushedSubmissionID = #bind(submissionID as String?)
                $0.commitData = #bind(data as Data?)
                $0.checkoutPath = #bind(checkoutURL.standardizedFileURL.path as String?)
            }
            .execute(db)
        }
    }

    func mutation(
        workspaceID: EditingWorkspaceRecord.ID,
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
        workspaceID: EditingWorkspaceRecord.ID,
        submissionID: WorkspaceSubmissionID
    ) async throws {
        let data = try encode(mutation)
        let submissionID = submissionID.rawValue.uuidString.lowercased()
        try await database.write { db in
            try WorkspacePublicationRecord.find(workspaceID).update {
                $0.recordedSubmissionID = #bind(submissionID as String?)
                $0.mutationData = #bind(data as Data?)
            }
            .execute(db)
        }
    }

    func proposalTimestamp(
        workspaceID: EditingWorkspaceRecord.ID,
        submissionID: WorkspaceSubmissionID,
        makeTimestamp: @Sendable () -> String
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

    func advance(
        to line: WorkspaceEditingLine,
        workspaceID: EditingWorkspaceRecord.ID
    ) async throws {
        let data = try encode(line)
        try await database.write { db in
            try WorkspacePublicationRecord.find(workspaceID).update {
                $0.editingLineData = #bind(data)
            }
            .execute(db)
        }
    }

    func removeSubmission(
        workspaceID: EditingWorkspaceRecord.ID,
        submissionID: WorkspaceSubmissionID
    ) async throws {
        let submissionID = submissionID.rawValue.uuidString.lowercased()
        let checkoutPath: String? = try await database.read { db -> String? in
            let record = try WorkspacePublicationRecord.find(workspaceID).fetchOne(db)
            guard record?.pushedSubmissionID == submissionID else { return nil }
            return record?.checkoutPath
        }
        if let checkoutPath {
            try? FileManager.default.removeItem(
                at: URL(filePath: checkoutPath, directoryHint: .isDirectory)
            )
        }
        try await database.write { db in
            try WorkspacePublicationRecord.find(workspaceID).update {
                $0.captureRequestID = #bind(nil as String?)
                $0.capturedChangesData = #bind(nil as Data?)
                $0.submissionData = #bind(nil as Data?)
                $0.pushedSubmissionID = #bind(nil as String?)
                $0.commitData = #bind(nil as Data?)
                $0.checkoutPath = #bind(nil as String?)
                $0.recordedSubmissionID = #bind(nil as String?)
                $0.mutationData = #bind(nil as Data?)
                $0.proposalTimestamp = #bind(nil as String?)
            }
            .execute(db)
        }
    }
}

private func encode<Value: Encodable>(_ value: Value) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(value)
}

private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
    try JSONDecoder().decode(type, from: data)
}
