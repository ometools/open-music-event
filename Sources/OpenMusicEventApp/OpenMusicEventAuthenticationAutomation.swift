import OpenMusicEventOAuthClient
import SkipFuse
import ATProto
import ATProtoOAuth
import Dependencies
import Foundation
import HTTPClient
import HTTPTypes
import OpenMusicEventAuthentication
import TCATProtoAuthentication
#if canImport(OSLog)
import OSLog
#endif

/// Build-time profiles keep the attendee's frozen clock out of live OAuth tests.
public enum OpenMusicEventUIAutomation: String, Sendable, Equatable {
    case normal
    case attendee
    case authentication

    public static func buildProfile(_ name: String, legacyAttendee: Bool) -> Self {
        #if DEBUG
        if name == "authentication" { return .authentication }
        if name == "attendee" || legacyAttendee { return .attendee }
        #endif
        return .normal
    }
}

enum OpenMusicEventAuthenticationAutomation {
    static let domain = "ome-auth.test"
    static let pdsHost = "pds1.ome-auth.test"
    static let client = OpenMusicEventOAuthClient.privateAuthentication
    static let metadataURL = client.metadataURL

    static func prepareSignUp(_ dependencies: inout DependencyValues) {
        dependencies.openMusicEventSignUpServerConfiguration = OAuthSignUpServerConfiguration(
            defaultServerHost: pdsHost,
            options: [OAuthSignUpServerOption(
                id: "private-pds",
                title: "Private Test PDS",
                subtitle: pdsHost,
                availability: .available(serverHost: pdsHost)
            )],
            allowsCustomServerHost: false
        )
    }

    static func prepareDependencies(_ dependencies: inout DependencyValues) {
        let appID = OAuth.App.ID(metadataURL)
        dependencies.oauthAppConfiguration.appID = appID
        dependencies.oauthAppConfiguration.redirectURI = .init(client.redirectURL)
        dependencies.oauthAppManifest = OAuth.AppManifest(
            appID: appID,
            appName: "OME Private Authentication Tests",
            redirectURIs: [.init(client.redirectURL)],
            basePermissions: [.atproto]
        )
        dependencies.didResolvers.resolve["plc"] = { did in
            @Dependency(\.httpClient) var httpClient
            return try await httpClient.get(URL(string: "https://plc.ome-auth.test/\(did)")!)
        }
        dependencies.actorTypeaheadSearch = .init { _ in [] }

        // Runtime construction prepares dependencies twice. Install one forwarding observer.
        guard !dependencies[AuthenticationTransportInstalled.self] else { return }
        dependencies[AuthenticationTransportInstalled.self] = true
        let liveTransport = dependencies.dataForURL
        dependencies.dataForURL = { request, body in
            guard permits(request) else { throw PrivateNetworkError.outsideSandbox }
            let (data, response) = try await liveTransport(request, body)
            if let event = event(request: request, body: body, status: response.status.code) {
                // Never emit request/response bodies, auth headers, codes, or token values.
                #if os(Android)
                Logger(subsystem: "app.openmusicevent", category: "auth-e2e")
                    .notice("OME_AUTH_E2E \(event)")
                #elseif canImport(OSLog)
                Logger(subsystem: "app.openmusicevent", category: "auth-e2e")
                    .notice("OME_AUTH_E2E \(event, privacy: .public)")
                #else
                print("OME_AUTH_E2E \(event)")
                #endif
            }
            return (data, response)
        }
    }

    static func permits(_ request: HTTPRequest) -> Bool {
        guard request.scheme == "https", let authority = request.authority else { return false }
        return authority == domain || authority.hasSuffix(".\(domain)")
    }

    static func event(request: HTTPRequest, body: Data?, status: Int) -> String? {
        let path = request.path?.split(separator: "?", maxSplits: 1).first.map(String.init)
        if path == "/xrpc/com.atproto.server.getSession" {
            return "getSession status=\(status)"
        }
        if path == "/oauth/token" {
            let form = String(data: body ?? Data(), encoding: .utf8) ?? ""
            let refresh = form.split(separator: "&").contains("grant_type=refresh_token")
            return "\(refresh ? "refresh" : "exchange") status=\(status)"
        }
        return nil
    }

    private enum PrivateNetworkError: Error { case outsideSandbox }
    private enum AuthenticationTransportInstalled: DependencyKey {
        static let liveValue = false
    }
}
