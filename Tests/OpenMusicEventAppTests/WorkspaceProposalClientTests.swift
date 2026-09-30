import ATProto
import CustomDump
import Dependencies
import Foundation
import HTTPClient
import OpenMusicEventLexicon
import Testing

@testable import OpenMusicEventSourceEditing

@Suite("Workspace proposal client")
struct WorkspaceProposalClientTests {
    @Test
    func readsEveryListPageAndDetailFromTheConfiguredAppView() async throws {
        let source = try #require(
            ATProto.URI("at://did:plc:owner/sh.tangled.repo/events")
        )
        let proposalURI = try #require(
            ATProto.URI("at://did:plc:author/sh.tangled.repo.pull/review-1")
        )
        let workspace = SourceWorkspace(
            organizerID: try #require(OME.Organizer.ID("did:plc:owner")),
            repository: "tangled.org/owner/events",
            branch: " refs/heads/main "
        )
        let requests = LockIsolated<[URL]>([])
        let client = WorkspaceProposalClient.openMusicEvent(
            appViewHost: "stg.openmusicevent.app"
        )

        let (proposals, detail) = try await withDependencies {
            $0[XRPC.Client.self] = .liveValue
            $0.httpClient = HTTPClient { request, _ in
                let url = try #require(request.url)
                requests.withValue { $0.append(url) }
                #expect(url.host == "stg.openmusicevent.app")

                switch url.path {
                case let path where path.hasSuffix(
                    "/app.openmusicevent.workspace.getProposals"
                ):
                    #expect(url.queryValue(named: "source") == source.description)
                    #expect(url.queryValue(named: "targetBranch") == "main")
                    #expect(url.queryValue(named: "includeRetained") == "false")
                    #expect(url.queryValue(named: "limit") == "100")
                    if url.queryValue(named: "cursor") == nil {
                        return Data(
                            """
                            {
                              "cursor": "page-2",
                              "proposals": [
                                {
                                  "uri": "at://did:plc:author/sh.tangled.repo.pull/review-1",
                                  "canonicalSource": "at://did:plc:owner/sh.tangled.repo/events",
                                  "title": "First proposal",
                                  "authorDID": "did:plc:author",
                                  "status": "sh.tangled.repo.pull.status.open",
                                  "targetBranch": "main",
                                  "createdAt": "2026-08-31T16:00:00Z",
                                  "updatedAt": "2026-08-31T16:01:00Z",
                                  "renderStatus": "app.openmusicevent.workspace.defs#ready"
                                }
                              ]
                            }
                            """.utf8
                        )
                    }
                    #expect(url.queryValue(named: "cursor") == "page-2")
                    return Data(
                        """
                        {
                          "proposals": [
                            {
                              "uri": "at://did:plc:other/sh.tangled.repo.pull/review-2",
                              "canonicalSource": "at://did:plc:owner/sh.tangled.repo/events",
                              "title": "Second proposal",
                              "authorDID": "did:plc:other",
                              "status": "sh.tangled.repo.pull.status.open",
                              "targetBranch": "main",
                              "createdAt": "2026-08-31T17:00:00Z",
                              "updatedAt": "2026-08-31T17:01:00Z",
                              "renderStatus": "app.openmusicevent.workspace.defs#pending"
                            }
                          ]
                        }
                        """.utf8
                    )

                case let path where path.hasSuffix(
                    "/app.openmusicevent.workspace.getProposal"
                ):
                    #expect(url.queryValue(named: "uri") == proposalURI.description)
                    return Data(
                        """
                        {
                          "uri": "at://did:plc:author/sh.tangled.repo.pull/review-1",
                          "canonicalSource": "at://did:plc:owner/sh.tangled.repo/events",
                          "title": "First proposal",
                          "authorDID": "did:plc:author",
                          "status": "sh.tangled.repo.pull.status.open",
                          "targetBranch": "main",
                          "source": {
                            "branch": "ome/proposal-first",
                            "revision": "source-revision"
                          },
                          "recordAvailability": "app.openmusicevent.workspace.defs#present",
                          "renderStatus": "app.openmusicevent.workspace.defs#ready",
                          "presentation": {
                            "formatVersion": 1,
                            "groups": []
                          }
                        }
                        """.utf8
                    )

                default:
                    Issue.record("Unexpected XRPC request: \(url)")
                    return Data(#"{}"#.utf8)
                }
            }
        } operation: {
            let proposals = try await client.list(
                OpenMusicEventWorkspaceProposalListRequest(workspace: workspace)
            )
            let detail = try await client.detail(proposalURI)
            return (proposals, detail)
        }

        expectNoDifference(
            proposals.map(\.uri.description),
            [
                "at://did:plc:author/sh.tangled.repo.pull/review-1",
                "at://did:plc:other/sh.tangled.repo.pull/review-2",
            ]
        )
        expectNoDifference(detail.uri, proposalURI)
        expectNoDifference(detail.source?.revision, "source-revision")
        #expect(detail.presentation?.groups.isEmpty == true)
        #expect(requests.withValue(\.count) == 3)
    }
}

private extension URL {
    func queryValue(named name: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
    }
}
