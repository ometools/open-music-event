import AppViewIndex
import ATProto
import Crypto
import CustomDump
import Dependencies
import Foundation
import GRDB
import Gzip
import HTTPClient
import InlineSnapshotTesting
import OpenMusicEventLexicon
import OpenMusicEventSourceClone
import OpenMusicEventSourceEditing
import SQLiteData
import SnapshotTesting
import SourceEditing
import TangledLexicon
import Testing

@testable import OpenMusicEventAppViewServer

@Suite("Workspace proposal renderer")
struct WorkspaceProposalRendererTests {
    @Test
    func `renders an exact proposal patch through the shared source presentation`() async throws {
        let scratchRootURL = FileManager.default.temporaryDirectory
            .appending(
                path: "ome-workspace-proposal-render-test-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        let targetSourceURL = scratchRootURL.appending(
            path: "target-source",
            directoryHint: .isDirectory
        )
        let contributorPath = "events/server-render-2026/contributors/artist.md"
        let contributorURL = targetSourceURL.appending(path: contributorPath)
        try FileManager.default.createDirectory(
            at: contributorURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: scratchRootURL) }

        // The target artifact contains the currently published event and artist profile.
        try """
        name: Server Render Event
        startDate: "2026-08-28"
        endDate: "2026-08-30"
        status: scheduled
        mode: community.lexicon.calendar.event#inperson
        timeZone: America/Denver
        """
        .appending("\n")
        .write(
            to: targetSourceURL.appending(path: "events/server-render-2026/event.yml"),
            atomically: true,
            encoding: .utf8
        )
        let oldContributor = """
        ---
        name: Old Artist
        ---
        Old biography
        """
        .appending("\n")
        try oldContributor.write(to: contributorURL, atomically: true, encoding: .utf8)

        // Tangled supplies a Git format-patch envelope that replaces the contributor source file.
        let newContributor = """
        ---
        name: New Artist
        ---
        New biography
        """
        .appending("\n")
        let gitDiff = String(
            decoding: try SourcePatchGitPatchCodec().formatReviewPatch(
                SourcePatch(
                    fileChanges: [
                        SourcePatchFileChange(
                            path: contributorPath,
                            kind: .modified,
                            oldContents: Data(oldContributor.utf8),
                            newContents: Data(newContributor.utf8)
                        )
                    ]
                )
            ),
            as: UTF8.self
        )
        let patchData = Data(
            """
            From 9587815f1fd5678747a47c9d0499cd4a101deb09 Mon Sep 17 00:00:00 2001
            From: Workspace Author <workspace@example.com>
            Date: Mon, 31 Aug 2026 20:26:29 +0000
            Subject: [PATCH] Rename the artist

            ---
             \(contributorPath) | 1 +-
             1 file changed, 1 insertion(+), 1 deletion(-)

            \(gitDiff)
            -- 
            2.47.0

            """.utf8
        )

        // The server imports both exact sources and renders the same typed value as Workspace.
        let organizerID = try #require(OME.Organizer.ID("did:plc:server-renderer"))
        let presentation = try await WorkspaceProposalRenderer().render(
            workspace: SourceWorkspace(
                organizerID: organizerID,
                repository: "https://tangled.org/example/events",
                branch: "main"
            ),
            targetSourceURL: targetSourceURL,
            patchData: patchData
        )

        expectNoDifference(presentation.totalCount, 1)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        assertInlineSnapshot(
            of: String(decoding: try encoder.encode(presentation), as: UTF8.self),
            as: .lines
        ) {
            #"""
            {
              "formatVersion" : 1,
              "groups" : [
                {
                  "displayName" : "Contributor",
                  "id" : "app.openmusicevent.contributor",
                  "records" : [
                    {
                      "changedFields" : [
                        "bio",
                        "name"
                      ],
                      "id" : "app.openmusicevent.contributor:contributorID=\"artist\",eventID=\"events-server-render-2026\",organizerID=\"did:plc:server-renderer\"",
                      "sourceFiles" : [
                        "events/server-render-2026/contributors/artist.md"
                      ],
                      "title" : "New Artist",
                      "transition" : {
                        "after" : {
                          "$type" : "app.openmusicevent.contributor",
                          "bio" : "New biography\n",
                          "id" : {
                            "contributorID" : "artist",
                            "eventID" : "events-server-render-2026",
                            "organizerID" : "did:plc:server-renderer"
                          },
                          "name" : "New Artist"
                        },
                        "before" : {
                          "$type" : "app.openmusicevent.contributor",
                          "bio" : "Old biography\n",
                          "id" : {
                            "contributorID" : "artist",
                            "eventID" : "events-server-render-2026",
                            "organizerID" : "did:plc:server-renderer"
                          },
                          "name" : "Old Artist"
                        },
                        "kind" : "modified"
                      }
                    }
                  ]
                }
              ]
            }
            """#
        }
    }

    @Test
    func `a proposal renders from its record without a webhook`() async throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        let targetRevision = "1111111111111111111111111111111111111111"
        let previousRevision = "0000000000000000000000000000000000000000"
        let authorDID = try #require(DID("did:plc:proposal-author"))
        let authorHandle = Atmosphere.Account.Handle("proposal-author.example")
        let proposalURI = try #require(
            ATProto.URI("at://did:plc:proposal-author/sh.tangled.repo.pull/server-render")
        )
        let proposalRevision = ATProto.CID("bafyreiserverrenderproposal")
        let patchBlobCID = ATProto.CID("bafkreiserverrenderpatch")
        let watch = TangledWebhookWatch(
            repository: TangledRepositoryReference(
                host: "tangled.org",
                owner: "wickedwoods.ca",
                repository: "ome-workspace"
            ),
            hookID: 42,
            repositoryOwnerDID: try #require(DID("did:plc:workspace-owner")),
            repositoryDID: try #require(DID("did:plc:workspace-repository")),
            ref: "refs/heads/main",
            canonicalSource: CanonicalTangledSource(
                organizerID: try #require(OME.Organizer.ID("did:plc:wickedwoods")),
                repositoryRecordKey: .init(rawValue: "wicked-woods-source")
            )
        )
        let configuration = try TangledWebhookConfiguration(watches: [watch])
        let scratchRootURL = FileManager.default.temporaryDirectory
            .appending(
                path: "ome-workspace-proposal-service-test-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        let targetSourceURL = scratchRootURL.appending(
            path: "target-source",
            directoryHint: .isDirectory
        )
        let contributorPath = "events/server-render-2026/contributors/artist.md"
        let contributorURL = targetSourceURL.appending(path: contributorPath)
        try FileManager.default.createDirectory(
            at: contributorURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: scratchRootURL) }

        // The published target artifact contains the source the proposal was made against.
        try """
        name: Server Render Event
        startDate: "2026-08-28"
        endDate: "2026-08-30"
        status: scheduled
        mode: community.lexicon.calendar.event#inperson
        timeZone: America/Denver
        """
        .appending("\n")
        .write(
            to: targetSourceURL.appending(path: "events/server-render-2026/event.yml"),
            atomically: true,
            encoding: .utf8
        )
        let oldContributor = """
        ---
        name: Old Artist
        ---
        Old biography
        """
        .appending("\n")
        try oldContributor.write(to: contributorURL, atomically: true, encoding: .utf8)
        let newContributor = """
        ---
        name: New Artist
        ---
        New biography
        """
        .appending("\n")
        let patchData = try SourcePatchGitPatchCodec().formatReviewPatch(
            SourcePatch(
                fileChanges: [
                    SourcePatchFileChange(
                        path: contributorPath,
                        kind: .modified,
                        oldContents: Data(oldContributor.utf8),
                        newContents: Data(newContributor.utf8)
                    )
                ]
            )
        )
        let patchBlobData = try patchData.gzipped()

        // AppView already has the exact published target revision available for installation.
        let archiveData = Data("published target archive".utf8)
        let artifact = PublishedSourceArtifact(
            url: try #require(
                URL(string: "https://resources.openmusicevent.app/wickedwoods.ca/ome-workspace/archive/\(targetRevision).tar.gz")
            ),
            reference: "https://resources.openmusicevent.app/wickedwoods.ca/ome-workspace",
            objectKey: "wickedwoods.ca/ome-workspace/archive/\(targetRevision).tar.gz",
            revision: targetRevision,
            checksumSHA256: Data(SHA256.hash(data: archiveData)).base64EncodedString(),
            byteCount: archiveData.count,
            publishedAt: Date(timeIntervalSince1970: 1_787_600_000)
        )
        _ = try await store.apply(
            .empty(revision: targetRevision),
            replacing: .empty(revision: previousRevision),
            publishedArtifact: artifact,
            for: TangledSourceUpdate(
                watchID: watch.id,
                deliveryID: .init(rawValue: "target-source-delivery"),
                repositoryOwnerDID: watch.repositoryOwnerDID,
                ref: watch.ref,
                before: previousRevision,
                after: targetRevision,
                receivedAt: Date(timeIntervalSince1970: 1_787_600_000),
                canonicalSource: watch.canonicalSource,
                repository: watch.repository
            )
        )

        // Hydrant creates the durable proposal directly from the public pull record.
        let pull = TangledPullRecord(
            target: TangledPullRecord.Target(repo: watch.repositoryDID, branch: "main"),
            title: "Render artist detail previews",
            body: "Carries the old and new artist values.",
            rounds: [
                TangledPullRecord.Round(
                    patchBlob: ATProto.Blob(
                        ref: patchBlobCID,
                        mimeType: "application/gzip",
                        size: patchBlobData.count
                    ),
                    createdAt: "2026-08-24T20:00:00Z"
                )
            ],
            source: nil,
            createdAt: "2026-08-24T20:00:00Z"
        )
        let indexer = store.appViewRecordIndexer(
            tangledWebhookConfiguration: configuration
        )
        _ = try withDependencies {
            $0.defaultDatabase = database
        } operation: {
            try indexer.apply(
                .put(
                    try AppView.RecordVersion(
                        collection: TangledNSID.pull,
                        uri: proposalURI,
                        cid: proposalRevision,
                        value: JSONEncoder().encode(pull),
                        sequence: 400
                    )
                )
            )
        }
        let awaitingRender = try #require(
            try await store.workspaceProposal(id: proposalURI)
        )
        expectNoDifference(awaitingRender.webhook, nil)
        expectNoDifference(awaitingRender.renderState, .awaitingInput)

        // The server reads the round blob from the author's PDS and renders it against the target.
        let processor = WorkspaceProposalRenderProcessor(
            configuration: configuration,
            store: store
        )
        let candidates = try await processor.candidates()
        expectNoDifference(candidates.map(\.id), [proposalURI])
        try await withDependencies {
            $0.uuid = .incrementing
            $0[Atmosphere.Account.Client.self] = Atmosphere.Account.Client(
                resolveHandle: { handle in
                    Issue.record("Did not expect handle resolution for \(handle.rawValue)")
                    return (
                        Atmosphere.Account(id: .init(authorDID), handle: authorHandle),
                        try didDocument(
                            did: authorDID,
                            handle: authorHandle,
                            pdsHost: "proposal-author.pds.example"
                        )
                    )
                },
                resolveDID: { did in
                    expectNoDifference(did, authorDID)
                    return (
                        Atmosphere.Account(id: .init(authorDID), handle: authorHandle),
                        try didDocument(
                            did: authorDID,
                            handle: authorHandle,
                            pdsHost: "proposal-author.pds.example"
                        )
                    )
                }
            )
            $0.httpClient = HTTPClient { request, _ in
                expectNoDifference(request.method, .get)
                let components = try #require(
                    request.url.flatMap {
                        URLComponents(url: $0, resolvingAgainstBaseURL: false)
                    }
                )
                expectNoDifference(components.scheme, "https")
                expectNoDifference(components.host, "proposal-author.pds.example")
                expectNoDifference(components.path, "/xrpc/com.atproto.sync.getBlob")
                expectNoDifference(
                    components.queryItems,
                    [
                        URLQueryItem(name: "did", value: authorDID.description),
                        URLQueryItem(name: "cid", value: patchBlobCID.rawValue),
                    ]
                )
                return patchBlobData
            }
            $0.tangledSourceCheckout = TangledSourceCheckoutClient { request in
                expectNoDifference(request.repository, watch.repository)
                expectNoDifference(request.ref, targetRevision)
                expectNoDifference(
                    request.archive,
                    SourceArchiveReference(
                        url: artifact.url,
                        checksumSHA256: artifact.checksumSHA256,
                        byteCount: artifact.byteCount
                    )
                )
                try FileManager.default.copyItem(at: targetSourceURL, to: request.outputURL)
                return TangledSourceCheckout(repositoryURL: request.outputURL)
            }
        } operation: {
            try await processor.process(try #require(candidates.first))
        }

        // The XRPC-owned detail is ready with the same typed source presentation as Workspace.
        let rendered = try #require(try await store.workspaceProposal(id: proposalURI))
        let presentation: OME.WorkspaceProposal.Presentation
        switch rendered.renderState {
        case let .ready(value):
            presentation = value
        case .awaitingInput, .pending:
            Issue.record("The server should persist a completed proposal presentation.")
            return
        }
        expectNoDifference(rendered.renderInput?.proposalRevision, proposalRevision)
        expectNoDifference(rendered.renderInput?.targetRevision, targetRevision)
        expectNoDifference(rendered.renderInput?.roundNumber, 0)
        expectNoDifference(
            rendered.renderInput?.patchDigest,
            Data(SHA256.hash(data: patchData)).base64EncodedString()
        )
        expectNoDifference(presentation.totalCount, 1)
        let renderedRecord = try #require(presentation.groups.first?.records.first)
        expectNoDifference(renderedRecord.title, "New Artist")
        expectNoDifference(renderedRecord.changedFields, ["bio", "name"])

        let detail = try #require(
            try await store.workspaceProposalDetail(
                id: proposalURI,
                tangledWebhookConfiguration: configuration
            )
        )
        expectNoDifference(detail.renderStatus, .ready)
        expectNoDifference(detail.presentation, presentation)
    }
}

private func didDocument(
    did: DID,
    handle: Atmosphere.Account.Handle,
    pdsHost: String
) throws -> DID.Document {
    try JSONDecoder().decode(
        DID.Document.self,
        from: Data(
            """
            {
              "id": "\(did.description)",
              "alsoKnownAs": ["at://\(handle.rawValue)"],
              "verificationMethod": [],
              "service": [
                {
                  "id": "#atproto_pds",
                  "type": "AtprotoPersonalDataServer",
                  "serviceEndpoint": "https://\(pdsHost)"
                }
              ]
            }
            """
            .utf8
        )
    )
}
