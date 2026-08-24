import ATProto
import CustomDump
import Dependencies
import Foundation
import GRDB
import HTTPClient
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import OpenMusicEventLexicon
import OpenMusicEventSourceClone
import SQLiteData
import Testing

@testable import OpenMusicEventAppViewServer

@Suite(.serialized)
struct TangledWorkspaceProposalTests {
  @Test
  func `a pull-created webhook becomes one URI-keyed Workspace proposal`() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = try OpenMusicEventAppViewStore(
      databaseURL: directory.appending(path: "appview.sqlite"),
      webhookSecretProtection: try WebhookSecretProtection(keyData: Self.protectionKey)
    )
    try await store.replaceWebhookSecret(
      Self.secret,
      source: .tangled,
      watchID: Self.watch.id
    )
    let pullPageRequests = PullPageRequests(
      response: Data(
        """
        <main data-aturi="\(Self.pullURI.description)"></main>
        """.utf8
      )
    )
    let payload = Self.pullCreatedPayload()

    let proposal = try await withDependencies {
      $0.date.now = Self.receivedAt
      $0.httpClient = .liveValue
      $0.requestInterceptors = []
      $0.responseInterceptors = []
      $0.errorInterceptors = []
      $0.dataForURL = { request, body in
        await pullPageRequests.record(request, body: body)
      }
    } operation: {
      let app = try OpenMusicEventAppViewServer.application(
        configuration: AppViewConfiguration(
          port: 0,
          tangledWebhook: try TangledWebhookConfiguration(watches: [Self.watch])
        ),
        store: store,
        tangledSourceUpdateProcessor: TangledSourceUpdateProcessor { _ in }
      )
      return try await app.test(.live) { client in
        // Tangled announces the new pull before its AT record reaches Jetstream.
        try await client.execute(
          uri: TangledWebhookEndpoint.path,
          method: .post,
          headers: Self.headers(authenticating: payload),
          body: ByteBuffer(data: payload)
        ) { response in
          #expect(response.status == .accepted)
        }

        // The durable processor resolves the exact AT URI and creates the readable row.
        let proposal = try await Self.waitForProposal(in: store)

        // Tangled can replay the same delivery without creating another proposal.
        try await client.execute(
          uri: TangledWebhookEndpoint.path,
          method: .post,
          headers: Self.headers(authenticating: payload),
          body: ByteBuffer(data: payload)
        ) { response in
          #expect(response.status == .accepted)
        }
        let pendingPulls = try await store.pendingTangledPullCreatedDeliveries()
        expectNoDifference(pendingPulls, [])
        return proposal
      }
    }

    expectNoDifference(
      proposal,
      TangledWorkspaceProposal(
        id: Self.pullURI,
        discoveryDeliveryID: .init(rawValue: Self.deliveryID),
        watchID: Self.watch.id,
        webhook: TangledPullCreated.Webhook(
          canonicalSource: Self.watch.canonicalSource.reference,
          repository: TangledPullCreated.Webhook.Repository(
            host: Self.repository.host,
            port: Self.repository.port,
            owner: Self.repository.owner,
            ownerDID: try #require(DID(Self.repositoryOwnerDID)),
            name: Self.repository.repository
          ),
          pullNumber: 4,
          authorDID: try #require(DID(Self.pullAuthorDID)),
          title: "Add artist detail previews",
          body: "Carries the old and new artist values.",
          targetBranch: "main",
          source: TangledPullCreated.Webhook.Source(
            branch: "artist-preview",
            revision: "2222222222222222222222222222222222222222",
            repositoryDID: nil
          ),
          roundNumber: 0,
          state: "open",
          pageURL: Self.pageURL,
          patchURL: Self.patchURL,
          createdAt: "2026-08-24T20:00:00Z"
        ),
        observedAt: Self.receivedAt
      )
    )
    let pullPageRequestCount = await pullPageRequests.requestCount
    let inboxCount = try await Self.inboxCount(in: store)
    let proposalCount = try await Self.proposalCount(in: store)
    expectNoDifference(pullPageRequestCount, 1)
    expectNoDifference(inboxCount, 1)
    expectNoDifference(proposalCount, 1)
  }

  @Test
  func `an unresolved pull remains in the durable inbox without a proposal`() async throws {
    let database = try DatabaseQueue()
    let store = try OpenMusicEventAppViewStore(database: database)
    let configuration = try TangledWebhookConfiguration(watches: [Self.watch])
    let receiver = TangledWebhookServer(
      configuration: configuration,
      inbox: store,
      secret: { _ in Self.secret }
    )
    let payload = Self.pullCreatedPayload()

    // The verified provider event is durable before Tangled's pull page can be resolved.
    _ = try await receiver.receive(
      TangledWebhookRequest(
        event: "pull_request:created",
        hookID: "\(Self.watch.hookID)",
        deliveryID: Self.deliveryID,
        repository: Self.repositoryFullName,
        signature: TangledWebhookSignature.value(
          authenticating: payload,
          secret: Self.secret
        ),
        payload: payload
      ),
      receivedAt: Self.receivedAt
    )
    let processor = TangledWorkspaceProposalProcessor(
      configuration: configuration,
      store: store,
      resolver: TangledPullURIResolver { _ in
        throw TangledPullURIResolutionError.missingURI
      }
    )
    let pull = try #require(try await processor.pendingPulls().first)

    await #expect(throws: TangledPullURIResolutionError.missingURI) {
      try await processor.process(pull)
    }
    let pendingPullCount = try await processor.pendingPulls().count
    let inboxCount = try await Self.inboxCount(in: store)
    let proposalCount = try await Self.proposalCount(in: store)
    expectNoDifference(pendingPullCount, 1)
    expectNoDifference(inboxCount, 1)
    expectNoDifference(proposalCount, 0)
  }

  @Test
  func `the pull page must contain one pull URI owned by the proposal author`() throws {
    let authorDID = try #require(DID(Self.pullAuthorDID))
    let validHTML =
      #"<main data-aturi="at://did:plc:proposal-author/sh.tangled.repo.pull/3mq4ybvnfc522"></main>"#
    expectNoDifference(
      try TangledPullURIResolver.pullURI(
        in: validHTML,
        expectedAuthorDID: authorDID
      ),
      Self.pullURI
    )

    let invalidResponses: [(String, TangledPullURIResolutionError)] = [
      ("<main></main>", .missingURI),
      (
        validHTML + validHTML,
        .multipleURIs
      ),
      (
        #"<main data-aturi="at://did:plc:proposal-author/sh.tangled.repo.pull.status/3mq4ybvnfc522"></main>"#,
        .unsupportedURI(
          "at://did:plc:proposal-author/sh.tangled.repo.pull.status/3mq4ybvnfc522"
        )
      ),
      (
        #"<main data-aturi="at://did:plc:someone-else/sh.tangled.repo.pull/3mq4ybvnfc522"></main>"#,
        .authorMismatch(
          "at://did:plc:someone-else/sh.tangled.repo.pull/3mq4ybvnfc522"
        )
      ),
    ]
    for (html, expectedError) in invalidResponses {
      expectNoDifference(
        #expect(throws: TangledPullURIResolutionError.self) {
          try TangledPullURIResolver.pullURI(
            in: html,
            expectedAuthorDID: authorDID
          )
        },
        expectedError
      )
    }
  }

  @Test
  func `a pull page outside the watched repository is rejected before persistence`() async throws {
    let database = try DatabaseQueue()
    let store = try OpenMusicEventAppViewStore(database: database)
    let receiver = TangledWebhookServer(
      configuration: try TangledWebhookConfiguration(watches: [Self.watch]),
      inbox: store,
      secret: { _ in Self.secret }
    )
    let payload = Self.pullCreatedPayload(
      pageURL: URL(string: "https://attacker.example/pull")!
    )

    await #expect(throws: TangledWebhookReceiveError.repositoryMismatch) {
      try await receiver.receive(
        TangledWebhookRequest(
          event: "pull_request:created",
          hookID: "\(Self.watch.hookID)",
          deliveryID: Self.deliveryID,
          repository: Self.repositoryFullName,
          signature: TangledWebhookSignature.value(
            authenticating: payload,
            secret: Self.secret
          ),
          payload: payload
        ),
        receivedAt: Self.receivedAt
      )
    }
    let inboxCount = try await Self.inboxCount(in: store)
    expectNoDifference(inboxCount, 0)
  }
}

extension TangledWorkspaceProposalTests {
  fileprivate static let repositoryOwnerDID = "did:plc:workspace-owner"
  fileprivate static let repository = TangledRepositoryReference(
    host: "tangled.org",
    owner: "wickedwoods.ca",
    repository: "ome-workspace"
  )
  fileprivate static let repositoryFullName = "\(repositoryOwnerDID)/\(repository.repository)"
  fileprivate static let pullAuthorDID = "did:plc:proposal-author"
  fileprivate static let pageURL = URL(
    string: "https://tangled.org/wickedwoods.ca/ome-workspace/pulls/4"
  )!
  fileprivate static let patchURL = URL(
    string: "https://tangled.org/wickedwoods.ca/ome-workspace/pulls/4/round/0.patch"
  )!
  fileprivate static let pullURI = ATProto.URI(
    "at://did:plc:proposal-author/sh.tangled.repo.pull/3mq4ybvnfc522"
  )!
  fileprivate static let deliveryID = "a8a19b48-61c5-4a34-9c21-6ee0c4515c69"
  fileprivate static let receivedAt = Date(timeIntervalSince1970: 1_787_600_000)
  fileprivate static let secret = Data("fixture-pull-webhook-secret".utf8)
  fileprivate static let protectionKey = Data(repeating: 0x2A, count: 32)
  fileprivate static let watch = TangledWebhookWatch(
    repository: repository,
    hookID: 42,
    repositoryOwnerDID: DID(repositoryOwnerDID)!,
    ref: "refs/heads/main",
    canonicalSource: CanonicalTangledSource(
      organizerID: OME.Organizer.ID("did:plc:wickedwoods")!,
      repositoryRecordKey: .init(rawValue: "wicked-woods-source")
    )
  )

  fileprivate static func pullCreatedPayload(pageURL: URL = pageURL) -> Data {
    Data(
      """
      {
        "action": "created",
        "pull_request": {
          "number": 4,
          "title": "Add artist detail previews",
          "body": "Carries the old and new artist values.",
          "state": "open",
          "target_branch": "main",
          "source": {
            "branch": "artist-preview",
            "sha": "2222222222222222222222222222222222222222"
          },
          "round_number": 0,
          "owner": { "did": "\(pullAuthorDID)" },
          "html_url": "\(pageURL.absoluteString)",
          "patch_url": "\(patchURL.absoluteString)",
          "created_at": "2026-08-24T20:00:00Z"
        },
        "repository": {
          "full_name": "\(repositoryFullName)",
          "owner": { "did": "\(repositoryOwnerDID)" }
        },
        "sender": { "did": "\(pullAuthorDID)" }
      }
      """.utf8
    )
  }

  fileprivate static func headers(authenticating payload: Data) -> HTTPFields {
    [
      .contentType: "application/json",
      .init("X-Tangled-Event")!: "pull_request:created",
      .init("X-Tangled-Hook-ID")!: "\(watch.hookID)",
      .init("X-Tangled-Delivery")!: deliveryID,
      .init("X-Tangled-Repo")!: repositoryFullName,
      .init("X-Tangled-Signature-256")!: TangledWebhookSignature.value(
        authenticating: payload,
        secret: secret
      ),
    ]
  }

  fileprivate static func waitForProposal(
    in store: OpenMusicEventAppViewStore
  ) async throws -> TangledWorkspaceProposal {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(5))
    while clock.now < deadline {
      if let proposal = try await store.workspaceProposal(id: pullURI) {
        return proposal
      }
      try await clock.sleep(for: .milliseconds(10))
    }
    throw TangledWorkspaceProposalTestError.timedOut
  }

  fileprivate static func inboxCount(
    in store: OpenMusicEventAppViewStore
  ) async throws -> Int {
    try await store.database.read { database in
      try WebhookInboxDeliveryRow.fetchCount(database)
    }
  }

  fileprivate static func proposalCount(
    in store: OpenMusicEventAppViewStore
  ) async throws -> Int {
    try await store.database.read { database in
      try TangledWorkspaceProposalRow.fetchCount(database)
    }
  }
}

private enum TangledWorkspaceProposalTestError: Error {
  case timedOut
}

private actor PullPageRequests {
  let response: Data
  var requests: [HTTPRequest] = []

  init(response: Data) {
    self.response = response
  }

  func record(_ request: HTTPRequest, body: Data?) -> (Data, HTTPResponse) {
    requests.append(request)
    return (response, HTTPResponse(status: .ok))
  }

  var requestCount: Int {
    requests.count
  }
}
