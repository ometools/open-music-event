import ATProtoOAuth
import Dependencies
import ErrorHandling
import GRDB
import OpenMusicEventAuthentication
import OpenMusicEventDatabase

public struct EventEditingAuthorizationClient: Sendable {
    public var authorizationStatus:
        @Sendable (OMERecord.Event.ID) throws -> OAuth.AuthorizationStatus
    public var authorize: @Sendable (OMERecord.Event.ID) async throws -> Void

    public init(
        authorizationStatus: @escaping @Sendable (
            OMERecord.Event.ID
        ) throws -> OAuth.AuthorizationStatus,
        authorize: @escaping @Sendable (OMERecord.Event.ID) async throws -> Void
    ) {
        self.authorizationStatus = authorizationStatus
        self.authorize = authorize
    }
}

public extension EventEditingAuthorizationClient {
    static let satisfied = Self(
        authorizationStatus: { _ in .satisfied(.placeholder) },
        authorize: { _ in }
    )

    static let live = Self(
        authorizationStatus: { eventID in
            @Dependency(\.defaultDatabase) var database
            @Dependency(\.getOptionalDefaultSession) var getOptionalDefaultSession
            @Dependency(\.oauthAppManifest) var appManifest

            return OAuth.authorizationStatus(
                for: try authRequirement(eventID: eventID, database: database),
                session: getOptionalDefaultSession(),
                manifest: appManifest
            )
        },
        authorize: { eventID in
            @Dependency(\.defaultDatabase) var database
            @Dependency(\.oauthAuthorizationBroker) var authorizationBroker

            try await authorizationBroker.authorize(
                authRequirement(eventID: eventID, database: database)
            )
        }
    )

    static func authRequirement(
        eventID: OMERecord.Event.ID,
        database: any DatabaseReader
    ) throws -> OAuth.AuthRequirement {
        let sourceProvenance = try database.read { db in
            try EventSourceProvenanceRecord
                .where { $0.id.eq(eventID) }
                .fetchOne(db)
        }

        switch sourceProvenance?.sourceKind {
        case .tangled:
            return OpenMusicEventOAuth.tangledWorkspaceManagementAuthRequirement
        case .local, nil:
            return OpenMusicEventOAuth.baseAuthRequirement
        }
    }
}

private enum EventEditingAuthorizationClientKey: DependencyKey {
    static let liveValue = EventEditingAuthorizationClient.live
    static let testValue = EventEditingAuthorizationClient.satisfied
}

public extension DependencyValues {
    var eventEditingAuthorization: EventEditingAuthorizationClient {
        get { self[EventEditingAuthorizationClientKey.self] }
        set { self[EventEditingAuthorizationClientKey.self] = newValue }
    }
}

public extension UserFacingText {
    static let eventEditingAuthorizationFailed = Self(
        "Unable to authorize editing.",
        fallback: "Unable to authorize editing."
    )
}

public extension ErrorOperation {
    static let eventEditingAuthorization = Self("event.editing.authorization")
}
