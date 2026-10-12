import ATProto
import ATProtoAppView
import CustomDump
import Dependencies
import Foundation
import GRDB
import Hummingbird
import HummingbirdTesting
import OpenMusicEventLexicon
import OpenMusicEventSourceClone
import SQLiteData
import TangledLexicon
import Testing

@testable import OpenMusicEventAppViewServer

@Suite("Workspace proposal XRPC routes", AppViewTestTime(), .serialized)
struct WorkspaceProposalRouteTests {
  @Test
  func `lists and opens the unified server projection`() async throws {
    let database = try DatabaseQueue()
    let store = try OpenMusicEventAppViewStore(database: database)
    let configuration = try TangledWebhookConfiguration(watches: [Self.watch])
    try await Self.seedProposals(
      in: store,
      database: database,
      configuration: configuration
    )
    let app = try OpenMusicEventAppViewServer.application(
      configuration: AppViewConfiguration(tangledWebhook: configuration),
      store: store,
      tangledSourceUpdateProcessor: TangledSourceUpdateProcessor { _ in }
    )
    let source = Self.queryValue(Self.watch.canonicalSource.reference)

    try await app.test(.router) { client in
      let cursor = try await client.execute(
        uri: "/xrpc/app.openmusicevent.workspace.getProposals?source=\(source)&targetBranch=main&limit=1",
        method: .get
      ) { response in
        #expect(response.status == .ok)
        let page = try Self.decodePage(response.body)
        expectNoDifference(page.proposals.map(\.uri), [Self.webhookPullURI])
        expectNoDifference(page.proposals.map(\.status), [.open])
        expectNoDifference(page.proposals.map(\.renderStatus), [.ready])
        return try #require(page.cursor)
      }

      try await client.execute(
        uri: "/xrpc/app.openmusicevent.workspace.getProposals?source=\(source)&targetBranch=main&limit=1&cursor=\(Self.queryValue(cursor))",
        method: .get
      ) { response in
        #expect(response.status == .ok)
        let page = try Self.decodePage(response.body)
        expectNoDifference(page.proposals.map(\.uri), [Self.hydrantOnlyPullURI])
        expectNoDifference(page.cursor, nil)
      }

      try await client.execute(
        uri: "/xrpc/app.openmusicevent.workspace.getProposals?source=\(source)&targetBranch=main&includeRetained=true",
        method: .get
      ) { response in
        #expect(response.status == .ok)
        let page = try Self.decodePage(response.body)
        expectNoDifference(
          page.proposals.map(\.uri),
          [Self.mergedPullURI, Self.webhookPullURI, Self.hydrantOnlyPullURI]
        )
      }

      try await client.execute(
        uri: "/xrpc/app.openmusicevent.workspace.getProposal?uri=\(Self.queryValue(Self.webhookPullURI.description))",
        method: .get
      ) { response in
        #expect(response.status == .ok)
        let detail = try Self.decodeDetail(response.body)
        expectNoDifference(detail.uri, Self.webhookPullURI)
        expectNoDifference(detail.canonicalSource?.description, Self.watch.canonicalSource.reference)
        expectNoDifference(detail.title, "Hydrated artist detail previews")
        expectNoDifference(detail.status, .open)
        expectNoDifference(
          detail.updatedAt,
          ISO8601DateFormatter().date(from: "2026-08-24T22:00:00Z")
        )
        expectNoDifference(detail.recordAvailability, .present)
        expectNoDifference(detail.recordCID, Self.webhookPullCID)
        expectNoDifference(detail.statusRecordURI, Self.openStatusURI)
        expectNoDifference(detail.renderStatus, .ready)
        expectNoDifference(detail.presentation, .empty)
        expectNoDifference(detail.source?.revision, Self.revision)
      }

      try await client.execute(
        uri: "/xrpc/app.openmusicevent.workspace.getProposal?uri=\(Self.queryValue(Self.missingPullURI.description))",
        method: .get
      ) { response in
        #expect(response.status == .notFound)
        expectNoDifference(try Self.decodeError(response.body).error, "ProposalNotFound")
      }

      try await client.execute(
        uri: "/xrpc/app.openmusicevent.workspace.getProposal?uri=\(Self.queryValue(Self.deletedPullURI.description))",
        method: .get
      ) { response in
        #expect(response.status == .ok)
        let detail = try Self.decodeDetail(response.body)
        expectNoDifference(detail.uri, Self.deletedPullURI)
        expectNoDifference(detail.recordAvailability, .deleted)
        expectNoDifference(detail.title, nil)
        expectNoDifference(detail.targetBranch, nil)
        expectNoDifference(detail.canonicalSource, nil)
      }

      try await client.execute(
        uri: "/xrpc/app.openmusicevent.workspace.getProposals?source=\(source)&targetBranch=main&cursor=not-a-cursor",
        method: .get
      ) { response in
        #expect(response.status == .badRequest)
        expectNoDifference(try Self.decodeError(response.body).error, "InvalidCursor")
      }
    }
  }

  @Test
  func `reports unavailable Workspace storage through both queries`() async throws {
    let app = try OpenMusicEventAppViewServer.application()
    let source = Self.queryValue(Self.watch.canonicalSource.reference)

    try await app.test(.router) { client in
      try await client.execute(
        uri: "/xrpc/app.openmusicevent.workspace.getProposals?source=\(source)&targetBranch=main",
        method: .get
      ) { response in
        #expect(response.status == .serviceUnavailable)
        expectNoDifference(try Self.decodeError(response.body).error, "WorkspaceUnavailable")
      }

      try await client.execute(
        uri: "/xrpc/app.openmusicevent.workspace.getProposal?uri=\(Self.queryValue(Self.webhookPullURI.description))",
        method: .get
      ) { response in
        #expect(response.status == .serviceUnavailable)
        expectNoDifference(try Self.decodeError(response.body).error, "WorkspaceUnavailable")
      }
    }
  }
}

private extension WorkspaceProposalRouteTests {
  static let repositoryDID = DID("did:plc:workspace-repository")!
  static let authorDID = DID("did:plc:proposal-author")!
  static let webhookPullURI = ATProto.URI(
    "at://did:plc:proposal-author/sh.tangled.repo.pull/3webhook"
  )!
  static let hydrantOnlyPullURI = ATProto.URI(
    "at://did:plc:other-author/sh.tangled.repo.pull/3hydrant"
  )!
  static let mergedPullURI = ATProto.URI(
    "at://did:plc:merged-author/sh.tangled.repo.pull/3merged"
  )!
  static let deletedPullURI = ATProto.URI(
    "at://did:plc:deleted-author/sh.tangled.repo.pull/3deleted"
  )!
  static let missingPullURI = ATProto.URI(
    "at://did:plc:missing/sh.tangled.repo.pull/3missing"
  )!
  static let openStatusURI = ATProto.URI(
    "at://did:plc:proposal-author/sh.tangled.repo.pull.status/3status"
  )!
  static let webhookPullCID = ATProto.CID("bafyreipullwebhook")
  static let revision = "2222222222222222222222222222222222222222"
  static let watch = TangledWebhookWatch(
    repository: TangledRepositoryReference(
      host: "tangled.org",
      owner: "wickedwoods.ca",
      repository: "ome-workspace"
    ),
    hookID: 42,
    repositoryOwnerDID: DID("did:plc:workspace-owner")!,
    repositoryDID: repositoryDID,
    ref: "refs/heads/main",
    canonicalSource: CanonicalTangledSource(
      organizerID: OME.Organizer.ID("did:plc:wickedwoods")!,
      repositoryRecordKey: .init(rawValue: "wicked-woods-source")
    )
  )

  static func seedProposals(
    in store: OpenMusicEventAppViewStore,
    database: DatabaseQueue,
    configuration: TangledWebhookConfiguration
  ) async throws {
    _ = try await store.recordWorkspaceProposal(
      id: webhookPullURI,
      webhook: webhookObservation(
        id: "webhook",
        title: "Webhook artist detail previews",
        state: "open",
        createdAt: "2026-08-24T20:00:00Z"
      )
    )
    _ = try await store.recordWorkspaceProposal(
      id: mergedPullURI,
      webhook: webhookObservation(
        id: "merged",
        title: "Merged proposal",
        state: "merged",
        createdAt: "2026-08-24T23:00:00Z"
      )
    )

    let indexer = store.appViewRecordIndexer(
      tangledWebhookConfiguration: configuration
    )
    try withDependencies {
      $0.defaultDatabase = database
    } operation: {
      _ = try indexer.apply(
        .put(
          try AppView.RecordVersion(
            collection: TangledNSID.pull,
            uri: webhookPullURI,
            cid: webhookPullCID,
            value: JSONEncoder().encode(
              pullRecord(
                title: "Hydrated artist detail previews",
                authorDID: authorDID,
                createdAt: "2026-08-24T20:00:00Z"
              )
            ),
            sequence: 100
          )
        )
      )
      _ = try indexer.apply(
        .put(
          try AppView.RecordVersion(
            collection: TangledNSID.pullStatus,
            uri: openStatusURI,
            cid: ATProto.CID("bafyreistatusopen"),
            value: JSONEncoder().encode(
              TangledPullStatusRecord(
                pull: webhookPullURI,
                status: .open,
                createdAt: "2026-08-24T22:00:00Z"
              )
            ),
            sequence: 101
          )
        )
      )
      _ = try indexer.apply(
        .put(
          try AppView.RecordVersion(
            collection: TangledNSID.pull,
            uri: hydrantOnlyPullURI,
            cid: ATProto.CID("bafyreipullhydrant"),
            value: JSONEncoder().encode(
              pullRecord(
                title: "Hydrant-only proposal",
                authorDID: DID("did:plc:other-author")!,
                // This is 21:30Z. Typed Date ordering keeps it behind the 22:00Z status even
                // though the unparsed timestamp starts with a lexicographically larger hour.
                createdAt: "2026-08-24T23:30:00+02:00"
              )
            ),
            sequence: 102
          )
        )
      )
      _ = try indexer.apply(
        .put(
          try AppView.RecordVersion(
            collection: TangledNSID.pull,
            uri: deletedPullURI,
            cid: ATProto.CID("bafyreipulldeleted"),
            value: JSONEncoder().encode(
              pullRecord(
                title: "Later deleted proposal",
                authorDID: DID("did:plc:deleted-author")!,
                createdAt: "2026-08-24T18:00:00Z"
              )
            ),
            sequence: 103
          )
        )
      )
      _ = try indexer.apply(
        .delete(
          try AppView.RecordDeletion(
            collection: TangledNSID.pull,
            uri: deletedPullURI,
            sequence: 104
          )
        )
      )
    }

    let renderInput = TangledWorkspaceProposal.RenderInput(
      proposalRevision: webhookPullCID,
      targetRevision: revision,
      roundNumber: 0,
      patchDigest: "patch-digest",
      rendererVersion: 1
    )
    _ = try await store.prepareWorkspaceProposalRender(
      id: webhookPullURI,
      input: renderInput
    )
    let completion = try await store.completeWorkspaceProposalRender(
      id: webhookPullURI,
      expectedInput: renderInput,
      presentation: .empty
    )
    expectNoDifference(completion, .accepted)
  }

  static func webhookObservation(
    id: String,
    title: String,
    state: String,
    createdAt: String
  ) -> TangledWorkspaceProposal.WebhookObservation {
    TangledWorkspaceProposal.WebhookObservation(
      deliveryID: .init(rawValue: "delivery-\(id)"),
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
        pullNumber: id == "merged" ? 5 : 4,
        authorDID: id == "merged" ? DID("did:plc:merged-author")! : authorDID,
        title: title,
        body: "Carries the old and new artist values.",
        targetBranch: "main",
        source: TangledPullCreated.Webhook.Source(
          branch: "artist-preview",
          revision: revision,
          repositoryDID: nil
        ),
        roundNumber: 0,
        state: state,
        pageURL: URL(string: "https://tangled.org/workspace/pulls/\(id)")!,
        patchURL: URL(string: "https://tangled.org/workspace/pulls/\(id)/round/0.patch")!,
        createdAt: createdAt
      ),
      observedAt: Date(timeIntervalSince1970: 1_787_600_000)
    )
  }

  static func pullRecord(
    title: String,
    authorDID: DID,
    createdAt: String
  ) -> TangledPullRecord {
    TangledPullRecord(
      target: TangledPullRecord.Target(repo: repositoryDID, branch: "main"),
      title: title,
      body: "Carries the old and new artist values.",
      rounds: [
        TangledPullRecord.Round(
          patchBlob: ATProto.Blob(
            ref: "bafkreipatch",
            mimeType: "application/gzip",
            size: 123
          ),
          createdAt: createdAt
        )
      ],
      source: TangledPullRecord.Source(branch: "artist-preview", repo: authorDID),
      createdAt: createdAt
    )
  }

  static func queryValue(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
  }

  static func decodePage(_ body: ByteBuffer) throws -> OME.WorkspaceProposal.Page {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(
      OME.WorkspaceProposal.Page.self,
      from: Data(body.readableBytesView)
    )
  }

  static func decodeDetail(_ body: ByteBuffer) throws -> OME.WorkspaceProposal.Detail {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(
      OME.WorkspaceProposal.Detail.self,
      from: Data(body.readableBytesView)
    )
  }

  static func decodeError(_ body: ByteBuffer) throws -> XRPC.ErrorResponse {
    try JSONDecoder().decode(XRPC.ErrorResponse.self, from: Data(body.readableBytesView))
  }
}
