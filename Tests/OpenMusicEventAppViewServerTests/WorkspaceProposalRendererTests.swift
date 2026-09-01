import AppViewIndex
import ATProto
import Crypto
import CustomDump
import Dependencies
import Foundation
import GRDB
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

        // Tangled supplies a patch that replaces the complete contributor source file.
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
    func `a created proposal renders after its record and target source arrive`() async throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        let targetRevision = "1111111111111111111111111111111111111111"
        let previousRevision = "0000000000000000000000000000000000000000"
        let proposalURI = try #require(
            ATProto.URI("at://did:plc:proposal-author/sh.tangled.repo.pull/server-render")
        )
        let proposalRevision = ATProto.CID("bafyreiserverrenderproposal")
        let patchURL = try #require(
            URL(string: "https://tangled.org/wickedwoods.ca/ome-workspace/pulls/4/round/0.patch")
        )
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

        // The verified webhook creates the durable proposal row first.
        _ = try await store.recordWorkspaceProposal(
            id: proposalURI,
            webhook: TangledWorkspaceProposal.WebhookObservation(
                deliveryID: .init(rawValue: "proposal-created-delivery"),
                watchID: watch.id,
                value: TangledPullCreated.Webhook(
                    canonicalSource: watch.canonicalSource.reference,
                    repository: TangledPullCreated.Webhook.Repository(
                        host: watch.repository.host,
                        port: watch.repository.port,
                        owner: watch.repository.owner,
                        ownerDID: watch.repositoryOwnerDID,
                        name: watch.repository.repository
                    ),
                    pullNumber: 4,
                    authorDID: try #require(DID("did:plc:proposal-author")),
                    title: "Render artist detail previews",
                    body: "Carries the old and new artist values.",
                    targetBranch: "main",
                    source: nil,
                    roundNumber: 0,
                    state: "open",
                    pageURL: try #require(
                        URL(string: "https://tangled.org/wickedwoods.ca/ome-workspace/pulls/4")
                    ),
                    patchURL: patchURL,
                    createdAt: "2026-08-24T20:00:00Z"
                ),
                observedAt: Date(timeIntervalSince1970: 1_787_600_000)
            )
        )

        // Hydrant can arrive later and supplies the content-addressed pull revision.
        let pull = TangledPullRecord(
            target: TangledPullRecord.Target(repo: watch.repositoryDID, branch: "main"),
            title: "Render artist detail previews",
            body: "Carries the old and new artist values.",
            rounds: [
                TangledPullRecord.Round(
                    patchBlob: ATProto.Blob(
                        ref: "bafkreiserverrenderpatch",
                        mimeType: "application/gzip",
                        size: patchData.count
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
        expectNoDifference(awaitingRender.renderState, .awaitingInput)

        // The server checks out the exact artifact, downloads the exact round, and renders it.
        let processor = WorkspaceProposalRenderProcessor(
            configuration: configuration,
            store: store
        )
        let candidates = try await processor.candidates()
        expectNoDifference(candidates.map(\.id), [proposalURI])
        try await withDependencies {
            $0.uuid = .incrementing
            $0.httpClient = HTTPClient { request, _ in
                expectNoDifference(request.method, .get)
                expectNoDifference(request.url?.absoluteString, patchURL.absoluteString)
                return patchData
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
