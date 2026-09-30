import ATProto

public extension OpenMusicEvent {
    enum Comms {}
}

public extension OpenMusicEvent.Comms {
    struct SubmitPost: XRPC.Procedure, Codable, Equatable, Sendable {
        public static let nsid = ATProto.NSID("app.openmusicevent.comms.submitPost")
        public static let serviceReference = ATProto.ServiceReference(
            "did:web:openmusicevent.app#ome_appview"
        )!
        public static let authorizationPolicy = XRPC.AuthorizationPolicy.required(
            ATProto.OAuth.AuthRequirement(
                permissions: [.rpc(nsid, audience: serviceReference.description)]
            )
        )
        public static let routing = XRPC.Routing(
            authenticated: .serviceProxy(serviceReference.description)
        )

        public init(uri: ATProto.URI, cid: ATProto.CID) {
            self.uri = uri
            self.cid = cid
        }

        public var uri: ATProto.URI
        public var cid: ATProto.CID

        public var input: Self { self }

        public typealias Input = Self
        public typealias Parameters = Never

        public struct Output: Codable, Equatable, Sendable {
            public init() {}
        }
    }
}
