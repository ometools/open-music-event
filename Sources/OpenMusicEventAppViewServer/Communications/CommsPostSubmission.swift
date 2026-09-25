import ATProto
import Dependencies
import OpenMusicEventLexicon
import ATProtoHTTP

public extension OpenMusicEventAppViewServer {
    struct CommsPostSubmission: Sendable {
        public typealias Submit = @Sendable (
            _ input: OME.Comms.SubmitPost,
            _ authentication: XRPC.ServiceAuthentication
        ) async throws -> OME.Comms.SubmitPost.Output

        /// The verifier must be configured for `OME.Comms.SubmitPost.serviceReference` and backed
        /// by a replay registry shared by every server instance that can receive the request.
        public init(
            verifier: XRPC.ServiceJWTVerifier,
            submit: @escaping Submit
        ) {
            self.verifier = verifier
            self.submit = submit
        }

        public init(
            registerReplay: @escaping XRPC.ServiceJWTVerifier.RegisterReplay,
            submit: @escaping Submit
        ) {
            @Dependency(\.date.now) var now
            @Dependency(\.didClient) var didClient

            self.init(
                verifier: XRPC.ServiceJWTVerifier(
                    audience: OME.Comms.SubmitPost.serviceReference,
                    validityPolicy: .init(acceptsLegacyBareDIDAudience: false),
                    now: { now },
                    resolveDID: { did in
                        try await didClient.fetchDocument(did)
                    },
                    registerReplay: registerReplay
                ),
                submit: submit
            )
        }

        public var verifier: XRPC.ServiceJWTVerifier
        public var submit: Submit
    }
}
