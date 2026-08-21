import Hummingbird
import OpenMusicEventLexicon
import XRPCClient
import XRPCHummingbird

extension OpenMusicEventAppViewServer {
    static func installCommsPostRoutes<Context: RequestContext>(
        on router: Router<Context>,
        submission: CommsPostSubmission?
    ) {
        guard let submission else { return }

        router.register(
            OME.Comms.SubmitPost.self,
            authenticatingWith: submission.verifier
        ) { input, authentication, _ in
            guard input.uri.authority == .did(authentication.issuer) else {
                throw XRPC.ResponseError(
                    .forbidden,
                    error: "PostAuthorityMismatch",
                    message: "The authenticated account does not own the submitted post."
                )
            }
            guard input.uri.collection == OME.Announcement.nsid,
                  input.uri.rkey != nil
            else {
                throw XRPC.ResponseError(
                    .badRequest,
                    error: "UnsupportedPostCollection",
                    message: "The submitted post must be an OpenMusicEvent announcement record."
                )
            }

            return try await submission.submit(input, authentication)
        }
    }
}
