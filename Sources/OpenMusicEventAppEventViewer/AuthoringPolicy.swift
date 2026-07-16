import ATProto
import ATProtoOAuth
import Dependencies
import ErrorHandling
import OpenMusicEventAuthentication
import OpenMusicEventDatabase
import OpenMusicEventSourceEditing
import SwiftUI

public enum Authoring {
    public struct Scope: Equatable, Sendable {
        public init() {}

        public static let all = Self()
    }

    public enum Mode: Equatable, Sendable {
        case attendee
        case authoring(Scope)

        public var isAuthoring: Bool {
            guard case .authoring = self else { return false }
            return true
        }
    }

    public struct Request: Equatable, Sendable {
        public init(
            subject: Subject,
            feature: Feature,
            action: Action,
            identity: Identity? = nil
        ) {
            self.action = action
            self.feature = feature
            self.identity = identity
            self.subject = subject
        }

        public var action: Action
        public var feature: Feature
        public var identity: Identity?
        public var subject: Subject
    }

    public enum Subject: Equatable, Sendable {
        case event(OMERecord.Event.ID)
        case sourceBaseline(SourceBaselineRecord.ID)
    }

    public enum Feature: Equatable, Sendable {
        case contactInfo
        case contributors
        case event
        case location
        case posters
        case publish
        case schedule
        case settings
        case stages
        case workspace
    }

    public enum Action: Equatable, Sendable {
        case create
        case delete
        case enterAuthoring
        case manageWorkspace
        case publish
        case update
    }

    public typealias Identity = Atmosphere.Account.ID
}

public struct AuthoringPolicyClient: Sendable {
    public var authenticate: @Sendable (Authoring.Subject) throws -> OAuth.AuthRequirement
    public var authorize: @Sendable (Authoring.Request) async throws -> Authoring.Scope
    public var mode: @Sendable (Authoring.Subject) throws -> Authoring.Mode

    public init(
        authenticate: @escaping @Sendable (Authoring.Subject) throws -> OAuth.AuthRequirement,
        authorize: @escaping @Sendable (Authoring.Request) async throws -> Authoring.Scope,
        mode: @escaping @Sendable (Authoring.Subject) throws -> Authoring.Mode
    ) {
        self.authenticate = authenticate
        self.authorize = authorize
        self.mode = mode
    }
}

public extension AuthoringPolicyClient {
    static let authoring = Self(
        authenticate: { subject in try authRequirement(for: subject) },
        authorize: { _ in .all },
        mode: { _ in .authoring(.all) }
    )

    static let attendee = Self(
        authenticate: { subject in try authRequirement(for: subject) },
        authorize: { request in
            throw OAuth.AuthorizationRequired.signIn(
                try Self.authRequirement(for: request.subject)
            )
        },
        mode: { _ in .attendee }
    )

    static let live = Self(
        authenticate: { _ in OpenMusicEventOAuth.baseAuthRequirement },
        authorize: { _ in .all },
        mode: { _ in .authoring(.all) }
    )

    static let loginRequired = Self(
        authenticate: { _ in OpenMusicEventOAuth.baseAuthRequirement },
        authorize: { _ in
            @Dependency(\.oauthAuthorizationBroker) var authorizationBroker

            try await authorizationBroker.authorize(
                OpenMusicEventOAuth.baseAuthRequirement
            )
            return .all
        },
        mode: { _ in
            @Dependency(\.getOptionalDefaultSession) var getOptionalDefaultSession
            @Dependency(\.oauthAppManifest) var appManifest

            switch OAuth.authorizationStatus(
                for: OpenMusicEventOAuth.baseAuthRequirement,
                session: getOptionalDefaultSession(),
                manifest: appManifest
            ) {
            case .satisfied:
                return .authoring(.all)

            case .impossible, .signInRequired, .upgradeAvailable, .wrongAccount:
                return .attendee
            }
        }
    )

    static func authRequirement(
        for _: Authoring.Subject
    ) throws -> OAuth.AuthRequirement {
        OpenMusicEventOAuth.baseAuthRequirement
    }
}

private enum AuthoringPolicyClientKey: DependencyKey {
    static let liveValue = AuthoringPolicyClient.live
    static let testValue = AuthoringPolicyClient.authoring
}

public extension DependencyValues {
    var authoringPolicy: AuthoringPolicyClient {
        get { self[AuthoringPolicyClientKey.self] }
        set { self[AuthoringPolicyClientKey.self] = newValue }
    }
}

public extension UserFacingText {
    static let authoringAuthorizationFailed = Self(
        "Unable to authorize editing.",
        fallback: "Unable to authorize editing."
    )
}

public extension ErrorOperation {
    static let authoringAuthorization = Self("authoring.authorization")
}
