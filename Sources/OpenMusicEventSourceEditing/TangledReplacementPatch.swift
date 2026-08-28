import ComposableWorkspace
import Dependencies
import Foundation
import Gzip
import SourceControlClient

struct TangledReplacementPatch: Codable, Equatable, Sendable {
    var baseRevision: WorkspaceRevision
    var currentRevision: WorkspaceRevision
    var patchText: String
    var compressedBlob: Data

    var patchByteCount: Int {
        patchText.utf8.count
    }

    var compressedBlobByteCount: Int {
        compressedBlob.count
    }
}

struct TangledReplacementPatchLimits: Equatable, Sendable {
    var maxPatchBytes: Int
    var maxCompressedBlobBytes: Int

    /// Knot2's default decompressed and encoded patch ceilings.
    /// Operators can lower these values, so the server remains authoritative.
    static let tangled = Self(
        maxPatchBytes: 128 * 1_024 * 1_024,
        maxCompressedBlobBytes: 16 * 1_024 * 1_024
    )
}

enum TangledReplacementPatchError: Equatable, Error, Sendable {
    case invalidTextEncoding
    case patchTooLarge(byteCount: Int, limit: Int)
    case compressedBlobTooLarge(byteCount: Int, limit: Int)
}

struct TangledReplacementPatchGenerator: Sendable {
    var limits: TangledReplacementPatchLimits

    init(limits: TangledReplacementPatchLimits = .tangled) {
        self.limits = limits
    }

    func generate(
        repository: Repository,
        baseRevision: WorkspaceRevision,
        baseCommit: CommitID,
        currentRevision: WorkspaceRevision
    ) async throws -> TangledReplacementPatch {
        @Dependency(\.sourceControl) var sourceControl
        let patchData = try await sourceControl.emailPatch(
            EmailPatchRequest(
                repository: repository,
                commit: CommitID(rawValue: currentRevision.rawValue),
                baseCommit: baseCommit
            )
        )
        guard patchData.count <= limits.maxPatchBytes else {
            throw TangledReplacementPatchError.patchTooLarge(
                byteCount: patchData.count,
                limit: limits.maxPatchBytes
            )
        }
        guard let patchText = String(data: patchData, encoding: .utf8) else {
            throw TangledReplacementPatchError.invalidTextEncoding
        }
        let compressedBlob = try patchData.gzipped()
        guard compressedBlob.count <= limits.maxCompressedBlobBytes else {
            throw TangledReplacementPatchError.compressedBlobTooLarge(
                byteCount: compressedBlob.count,
                limit: limits.maxCompressedBlobBytes
            )
        }
        return TangledReplacementPatch(
            baseRevision: baseRevision,
            currentRevision: currentRevision,
            patchText: patchText,
            compressedBlob: compressedBlob
        )
    }
}
