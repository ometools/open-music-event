import Hummingbird
import OpenMusicEventLexicon
import XRPCClient
import XRPCHummingbird

extension OpenMusicEventAppViewServer {
  static func installWorkspaceProposalRoutes<Context: RequestContext>(
    on router: Router<Context>,
    store: OpenMusicEventAppViewStore?,
    tangledWebhookConfiguration: TangledWebhookConfiguration?
  ) {
    router.register(OME.WorkspaceProposal.GetProposals.self) { parameters, _ in
      guard let store else {
        throw workspaceUnavailable()
      }
      do {
        return try await store.workspaceProposalPage(
          source: parameters.source,
          targetBranch: parameters.targetBranch,
          includeRetained: parameters.includeRetained,
          cursor: parameters.cursor,
          limit: parameters.limit,
          tangledWebhookConfiguration: tangledWebhookConfiguration
        )
      } catch OpenMusicEventAppViewStoreError.invalidCursor {
        throw XRPC.ResponseError(
          .badRequest,
          error: "InvalidCursor",
          message: "The XRPC cursor is invalid."
        )
      }
    }

    router.register(OME.WorkspaceProposal.GetProposal.self) { parameters, _ in
      guard let store else {
        throw workspaceUnavailable()
      }
      guard let proposal = try await store.workspaceProposalDetail(
        id: parameters.uri,
        tangledWebhookConfiguration: tangledWebhookConfiguration
      ) else {
        throw XRPC.ResponseError(
          .notFound,
          error: "ProposalNotFound",
          message: "The requested Workspace proposal is not available."
        )
      }
      return proposal
    }
  }
}

private func workspaceUnavailable() -> XRPC.ResponseError {
  XRPC.ResponseError(
    .serviceUnavailable,
    error: "WorkspaceUnavailable",
    message: "Workspace proposal storage is not configured."
  )
}
