import ATProto
import ATProtoTypes
import ConcurrencyExtras
import CustomDump
import Dependencies
import Foundation
import HTTPClient
import HTTPTypes
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import Testing

@testable import OpenMusicEventApp

struct EventRecordClientTests {
    @Test(arguments: ["valid", "wrong-id", "changed-commit"])
    func downloadsCanonicalRecordsFromTheirPublisherPDS(scenario: String) async throws {
        let event = try Event(
            id: #require(Event.ID("at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah")),
            name: "Wicked Woods", createdAt: "2026-09-01T12:00:00Z",
            timeZone: #require(TimeZone(identifier: "America/Denver"))
        )
        let payload = try event.encodeLexicon()
        let requests = LockIsolated<[String]>([])
        let commitReads = LockIsolated(0)

        try await withDependencies {
            $0[ATProto.Repository.PDSHostResolver.self] = .init { repository in
                expectNoDifference(repository, event.id.authority)
                return "pds.ome-auth.test"
            }
            $0[XRPC.Client.self] = .liveValue
            $0.httpClient = .liveValue
            $0.requestInterceptors = []
            $0.dataForURL = { request, body in
                let url = try #require(request.url)
                #expect(url.host == "pds.ome-auth.test")
                #expect(url.scheme == "https")
                #expect(body == nil)
                requests.withValue { $0.append(url.path) }
                let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
                let values = Dictionary(uniqueKeysWithValues: (query.queryItems ?? []).map { ($0.name, $0.value ?? "") })
                let response: Lexicon.JSONValue
                switch url.lastPathComponent {
                case "com.atproto.sync.getLatestCommit":
                    #expect(values["did"] == "did:plc:organizer")
                    let count = commitReads.withValue { $0 += 1; return $0 }
                    response = .object([
                        "cid": .string("bafyreihdwdcefgh4dqkjv67uzcmw7ojee6xedzdetojuzjevtenxquvyku"),
                        "rev": .string(scenario == "changed-commit" && count == 2 ? "next-revision" : "original-revision"),
                    ])
                case "com.atproto.repo.getRecord":
                    #expect(values["repo"] == "did:plc:organizer")
                    #expect(values["collection"] == Event.lexiconID.rawValue)
                    #expect(values["rkey"] == "3mrdbziccpcah")
                    response = .object([
                        "uri": .string(scenario == "wrong-id"
                            ? "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcai"
                            : event.id.description),
                        "value": payload,
                    ])
                case "com.atproto.repo.listRecords":
                    #expect(values["repo"] == "did:plc:organizer")
                    #expect(["events.openmusic.eventPlace", "events.openmusic.contributor", "events.openmusic.programItem"]
                        .contains(values["collection"] ?? ""))
                    response = .object(["records": .array([])])
                default:
                    Issue.record("Unexpected protocol request: \(url.path)")
                    response = .object([:])
                }
                return (try JSONEncoder().encode(response), HTTPResponse(status: .ok))
            }
        } operation: {
            if scenario == "valid" {
                let graph = try await EventRecordClient.liveValue.load(event.id)
                expectNoDifference(graph, EventRecordGraph(event: event))
            } else {
                await #expect(throws: ValidationError.self) {
                    try await EventRecordClient.liveValue.load(event.id)
                }
            }
        }
        #expect(requests.value.contains("/xrpc/com.atproto.repo.getRecord"))
        #expect(commitReads.value == (scenario == "wrong-id" ? 1 : 2))
    }
}
