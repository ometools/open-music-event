import ATProto
import ComposableWorkspace
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSourceEditing

enum WorkspaceProposalObservation {
    enum Result: Equatable, Sendable {
        case deleted
        case pending(OME.WorkspaceProposal.Detail?)
        case ready(OME.WorkspaceProposal.Detail)
    }

    enum Error: Equatable, Swift.Error, Sendable {
        case canonicalSourceMismatch(expected: ATProto.URI, actual: ATProto.URI?)
        case invalidURI(String)
        case proposalURIMismatch(expected: ATProto.URI, actual: ATProto.URI)
        case targetBranchMismatch(expected: String, actual: String?)
        case unsupportedPresentationVersion(expected: Int, actual: Int)
        case missingPresentation(ATProto.URI)
    }

    static func validate(
        _ proposals: [OME.WorkspaceProposal.ListItem],
        request: OpenMusicEventWorkspaceProposalListRequest
    ) throws {
        for proposal in proposals {
            guard proposal.canonicalSource == request.source else {
                throw Error.canonicalSourceMismatch(
                    expected: request.source,
                    actual: proposal.canonicalSource
                )
            }
            let targetBranch = SourceWorkspace.normalizedBranch(proposal.targetBranch)
            guard targetBranch == request.targetBranch else {
                throw Error.targetBranchMismatch(
                    expected: request.targetBranch,
                    actual: proposal.targetBranch
                )
            }
        }
    }

    static func observe(
        _ proposal: OME.WorkspaceProposal.Detail,
        proposalURI: ATProto.URI,
        request: OpenMusicEventWorkspaceProposalListRequest,
        expectedProposal: WorkspaceProposal?
    ) throws -> Result {
        if let expectedProposal {
            guard let receiptURI = ATProto.URI(expectedProposal.id.rawValue) else {
                throw Error.invalidURI(expectedProposal.id.rawValue)
            }
            guard receiptURI == proposalURI else {
                throw Error.proposalURIMismatch(expected: proposalURI, actual: receiptURI)
            }
        }
        guard proposal.uri == proposalURI else {
            throw Error.proposalURIMismatch(expected: proposalURI, actual: proposal.uri)
        }
        guard proposal.recordAvailability != .deleted else { return .deleted }
        guard proposal.canonicalSource == request.source else {
            throw Error.canonicalSourceMismatch(
                expected: request.source,
                actual: proposal.canonicalSource
            )
        }
        let targetBranch = proposal.targetBranch.map(SourceWorkspace.normalizedBranch)
        guard targetBranch == request.targetBranch else {
            throw Error.targetBranchMismatch(
                expected: request.targetBranch,
                actual: proposal.targetBranch
            )
        }
        guard proposal.recordAvailability == .present else {
            return .pending(proposal)
        }
        if let expectedProposal,
           proposal.source?.revision != expectedProposal.revision.rawValue {
            return .pending(proposal)
        }
        guard proposal.renderStatus == .ready else {
            return .pending(proposal)
        }
        guard let presentation = proposal.presentation else {
            throw Error.missingPresentation(proposal.uri)
        }
        guard presentation.formatVersion == OME.WorkspaceProposal.Presentation.currentFormatVersion
        else {
            throw Error.unsupportedPresentationVersion(
                expected: OME.WorkspaceProposal.Presentation.currentFormatVersion,
                actual: presentation.formatVersion
            )
        }
        return .ready(proposal)
    }
}

extension WorkspaceProposalObservation.Error: CustomStringConvertible {
    var description: String {
        switch self {
        case let .canonicalSourceMismatch(expected, actual):
            "Proposal source mismatch. Expected \(expected); received \(actual?.description ?? "missing")."
        case let .invalidURI(value):
            "Invalid proposal URI: \(value)."
        case let .proposalURIMismatch(expected, actual):
            "Proposal URI mismatch. Expected \(expected); received \(actual)."
        case let .targetBranchMismatch(expected, actual):
            "Proposal target branch mismatch. Expected \(expected); received \(actual ?? "missing")."
        case let .unsupportedPresentationVersion(expected, actual):
            "Unsupported proposal presentation version. Expected \(expected); received \(actual)."
        case let .missingPresentation(uri):
            "Proposal \(uri) is marked ready without a presentation."
        }
    }
}
