import ATProto
import CustomDump
import Dependencies
import Foundation
import Hummingbird
import HummingbirdTesting
import OpenMusicEventAppViewServer
import OpenMusicEventLexicon
import Testing
import XRPCClient
import XRPCHummingbird

struct CommsPostRouteTests {
    @Test
    func `accepts an exact announcement after authenticating its PDS service JWT`() async throws {
        let capture = CommsPostCapture()
        let fixture = try CommsServiceJWTFixture(capture: capture)
        let app = try OpenMusicEventAppViewServer.application(
            commsPostSubmission: fixture.submission
        )

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/xrpc/\(OME.Comms.SubmitPost.nsid)",
                method: .post,
                headers: [
                    .authorization: "Bearer \(fixture.token)",
                    .contentType: "application/json",
                ],
                body: ByteBuffer(string: Self.validAnnouncementInput)
            ) { response in
                #expect(response.status == .ok)
                expectNoDifference(
                    try decodeCommsPostOutput(response.body),
                    OME.Comms.SubmitPost.Output()
                )
            }
        }

        let values = await capture.values()
        expectNoDifference(
            values.input,
            OME.Comms.SubmitPost(
                uri: try #require(ATProto.URI(Self.announcementURI)),
                cid: Self.announcementCID
            )
        )
        expectNoDifference(
            values.authentication,
            XRPC.ServiceAuthentication(
                issuer: Self.issuer,
                audience: OME.Comms.SubmitPost.serviceReference,
                verificationMethod: DID.VerificationMethod.Identifier("#atproto")!,
                tokenID: XRPC.ServiceJWT.ID("comms-post")!
            )
        )
        let resolverCallCount = await fixture.resolver.callCount
        expectNoDifference(resolverCallCount, 1)
    }

    @Test
    func `rejects malformed service authentication before decoding the post`() async throws {
        let capture = CommsPostCapture()
        let fixture = try CommsServiceJWTFixture(capture: capture)
        let app = try OpenMusicEventAppViewServer.application(
            commsPostSubmission: fixture.submission
        )

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/xrpc/\(OME.Comms.SubmitPost.nsid)",
                method: .post,
                headers: [
                    .authorization: "Bearer not-a-jwt",
                    .contentType: "application/json",
                ],
                body: ByteBuffer(string: "not-json")
            ) { response in
                #expect(response.status == .unauthorized)
                expectNoDifference(
                    try decodeCommsPostError(response.body),
                    XRPC.ErrorResponse(error: "AuthenticationRequired")
                )
            }
        }

        #expect(await capture.values().input == nil)
        let resolverCallCount = await fixture.resolver.callCount
        expectNoDifference(resolverCallCount, 0)
    }

    @Test
    func `rejects an authenticated account submitting another account's post`() async throws {
        let capture = CommsPostCapture()
        let fixture = try CommsServiceJWTFixture(capture: capture)
        let app = try OpenMusicEventAppViewServer.application(
            commsPostSubmission: fixture.submission
        )

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/xrpc/\(OME.Comms.SubmitPost.nsid)",
                method: .post,
                headers: [
                    .authorization: "Bearer \(fixture.token)",
                    .contentType: "application/json",
                ],
                body: ByteBuffer(
                    string: Self.validAnnouncementInput.replacingOccurrences(
                        of: Self.issuer.description,
                        with: "did:plc:another-account"
                    )
                )
            ) { response in
                #expect(response.status == .forbidden)
                expectNoDifference(
                    try decodeCommsPostError(response.body),
                    XRPC.ErrorResponse(
                        error: "PostAuthorityMismatch",
                        message: "The authenticated account does not own the submitted post."
                    )
                )
            }
        }

        #expect(await capture.values().input == nil)
        let resolverCallCount = await fixture.resolver.callCount
        expectNoDifference(resolverCallCount, 1)
    }

    @Test
    func `rejects a non-announcement record after authentication`() async throws {
        let capture = CommsPostCapture()
        let fixture = try CommsServiceJWTFixture(capture: capture)
        let app = try OpenMusicEventAppViewServer.application(
            commsPostSubmission: fixture.submission
        )

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/xrpc/\(OME.Comms.SubmitPost.nsid)",
                method: .post,
                headers: [
                    .authorization: "Bearer \(fixture.token)",
                    .contentType: "application/json",
                ],
                body: ByteBuffer(
                    string: Self.validAnnouncementInput.replacingOccurrences(
                        of: OME.Announcement.nsid.rawValue,
                        with: "app.bsky.feed.post"
                    )
                )
            ) { response in
                #expect(response.status == .badRequest)
                expectNoDifference(
                    try decodeCommsPostError(response.body),
                    XRPC.ErrorResponse(
                        error: "UnsupportedPostCollection",
                        message: "The submitted post must be an OpenMusicEvent announcement record."
                    )
                )
            }
        }

        #expect(await capture.values().input == nil)
        let resolverCallCount = await fixture.resolver.callCount
        expectNoDifference(resolverCallCount, 1)
    }

    private static let issuer = DID("did:plc:fixture-service")!
    private static let announcementURI =
        "at://did:plc:fixture-service/app.openmusicevent.announcement/3abc"
    private static let announcementCID = ATProto.CID(
        "bafyreifiymllu4ykepilnm6j24fstwvp72rlbiojjkpmourcjyxykm7mzu"
    )
    private static let validAnnouncementInput =
        #"{"uri":"at://did:plc:fixture-service/app.openmusicevent.announcement/3abc","cid":"bafyreifiymllu4ykepilnm6j24fstwvp72rlbiojjkpmourcjyxykm7mzu"}"#
}

private struct CommsServiceJWTFixture {
    let resolver: CommsDIDResolver
    let submission: OpenMusicEventAppViewServer.CommsPostSubmission

    let token = XRPC.ServiceJWT(
        "eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6IiNhdHByb3RvIn0.eyJpc3MiOiJkaWQ6cGxjOmZpeHR1cmUtc2VydmljZSIsImF1ZCI6ImRpZDp3ZWI6b3Blbm11c2ljZXZlbnQuYXBwI29tZV9hcHB2aWV3IiwiZXhwIjoxODAwMDAwMDYwLCJpYXQiOjE4MDAwMDAwMDAsImx4bSI6ImFwcC5vcGVubXVzaWNldmVudC5jb21tcy5zdWJtaXRQb3N0IiwianRpIjoiY29tbXMtcG9zdCJ9.CLS_XKGMQtJzezOHWe908q1opmjiDgT8GWd8wCowZYA4gYaFnBwgtCipJ3xsYwfNr8GVUELYeaExFFWfMzWX5w"
    )!

    init(capture: CommsPostCapture) throws {
        let issuer = DID("did:plc:fixture-service")!
        let documentJSON = """
            {
              "id": "did:plc:fixture-service",
              "alsoKnownAs": [],
              "verificationMethod": [{
                "id": "#atproto",
                "controller": "did:plc:fixture-service",
                "type": "Multikey",
                "publicKeyMultibase": "zDnaepvkxAzoxFV64S6KJsuQLnUb4GheXYSnV8Q485B4zDqte"
              }],
              "service": []
            }
            """
        let document = try JSONDecoder().decode(
            DID.Document.self,
            from: Data(documentJSON.utf8)
        )
        let resolver = CommsDIDResolver(issuer: issuer, document: document)
        let replayStore = CommsServiceJWTReplayStore()
        self.resolver = resolver
        self.submission = withDependencies {
            $0.date.now = Date(timeIntervalSince1970: 1_800_000_000)
            $0.didClient = DID.Client { did in
                try await resolver.resolve(did)
            }
        } operation: {
            OpenMusicEventAppViewServer.CommsPostSubmission(
                registerReplay: { tokenID, expiresAt in
                    await replayStore.register(tokenID, expiresAt: expiresAt)
                },
                submit: { input, authentication in
                    await capture.submit(input, authentication: authentication)
                }
            )
        }
    }
}

private actor CommsDIDResolver {
    enum Error: Swift.Error {
        case unexpectedIssuer
    }

    let issuer: DID
    let document: DID.Document
    private(set) var callCount = 0

    init(issuer: DID, document: DID.Document) {
        self.issuer = issuer
        self.document = document
    }

    func resolve(_ did: DID) throws -> DID.Document {
        callCount += 1
        guard did == issuer else { throw Error.unexpectedIssuer }
        return document
    }
}

private actor CommsServiceJWTReplayStore {
    private var tokenIDs: Set<XRPC.ServiceJWT.ID> = []

    func register(
        _ tokenID: XRPC.ServiceJWT.ID,
        expiresAt _: Date
    ) -> XRPC.ServiceJWTVerifier.ReplayDecision {
        tokenIDs.insert(tokenID).inserted ? .accepted : .replayed
    }
}

private actor CommsPostCapture {
    private var input: OME.Comms.SubmitPost?
    private var authentication: XRPC.ServiceAuthentication?

    func submit(
        _ input: OME.Comms.SubmitPost,
        authentication: XRPC.ServiceAuthentication
    ) -> OME.Comms.SubmitPost.Output {
        self.input = input
        self.authentication = authentication
        return OME.Comms.SubmitPost.Output()
    }

    func values() -> (
        input: OME.Comms.SubmitPost?,
        authentication: XRPC.ServiceAuthentication?
    ) {
        (input, authentication)
    }
}

private func decodeCommsPostOutput(_ body: ByteBuffer) throws -> OME.Comms.SubmitPost.Output {
    try JSONDecoder().decode(
        OME.Comms.SubmitPost.Output.self,
        from: Data(body.readableBytesView)
    )
}

private func decodeCommsPostError(_ body: ByteBuffer) throws -> XRPC.ErrorResponse {
    try JSONDecoder().decode(
        XRPC.ErrorResponse.self,
        from: Data(body.readableBytesView)
    )
}
