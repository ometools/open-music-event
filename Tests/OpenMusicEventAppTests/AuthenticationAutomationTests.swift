import CustomDump
import Dependencies
import Foundation
import HTTPClient
import HTTPTypes
@testable import OpenMusicEventApp
import Testing

@Suite
struct AuthenticationAutomationTests {
    @Test(arguments: [
        "https://pds1.ome-auth.test/oauth/token",
        "https://plc.ome-auth.test/did:plc:example",
        "https://ios-tester.pds1.ome-auth.test/.well-known/atproto-did",
    ])
    func privateServicesAreAllowed(url: String) {
        #expect(OpenMusicEventAuthenticationAutomation.permits(HTTPRequest(method: .get, url: URL(string: url)!)))
    }

    @Test(arguments: [
        "https://bsky.social/oauth/token",
        "https://plc.directory/did:plc:example",
        "https://ome-auth.test.example.org/",
        "http://pds1.ome-auth.test/",
        "https://not-ome-auth.test/",
    ])
    func requestsOutsideSandboxAreRejected(url: String) {
        #expect(!OpenMusicEventAuthenticationAutomation.permits(HTTPRequest(method: .get, url: URL(string: url)!)))
    }

    @Test
    func diagnosticsContainOnlyOperationAndStatus() {
        let request = HTTPRequest(method: .post, url: URL(string: "https://pds1.ome-auth.test/oauth/token?secret=hidden")!)
        expectNoDifference(
            OpenMusicEventAuthenticationAutomation.event(
                request: request,
                body: Data("grant_type=refresh_token&refresh_token=secret&client_id=private".utf8),
                status: 200
            ),
            "refresh status=200"
        )
    }

    @Test @MainActor
    func authenticationStartsWithoutImportingTheAttendeeFixture() {
        let entry = withDependencies {
            $0.openMusicEventUIAutomation = .authentication
        } operation: {
            OpenMusicEventApplicationEntryView()
        }
        expectNoDifference(entry.preparation, .ready)
    }
    #if !os(Android)
    @Test @MainActor
    func authenticationKeepsTheLiveClockAndForwardsRealTransportRequests() async throws {
        let database = try UIAutomationFixtureTests().preparedDatabase()
        let now = Date()
        let payload = Data("{\"ok\":true}".utf8)
        try await withDependencies {
            $0.context = .live
            $0.date = .constant(now)
            $0.dataForURL = { request, body in
                #expect(request.authority == "pds1.ome-auth.test")
                #expect(body == nil)
                return (payload, HTTPResponse(status: .ok))
            }
            OME.prepareDependencies(&$0, database: database, uiAutomation: .authentication)
        } operation: {
            @Dependency(\.date) var date
            @Dependency(\.dataForURL) var transport
            expectNoDifference(date.now, now)
            let (response, _) = try await transport(
                HTTPRequest(method: .get, url: URL(string: "https://pds1.ome-auth.test/xrpc/_health")!), nil
            )
            expectNoDifference(response, payload)
            await #expect(throws: (any Error).self) {
                _ = try await transport(
                    HTTPRequest(method: .get, url: URL(string: "https://bsky.social/xrpc/_health")!), nil
                )
            }
        }
    }
    #endif

}
