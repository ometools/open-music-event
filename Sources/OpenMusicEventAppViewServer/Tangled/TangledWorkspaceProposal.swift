import ATProto
import Dependencies
import Foundation
import GRDB
import HTTPClient
import IssueReporting
import SQLiteData
import ServiceLifecycle

struct TangledPullCreated: Equatable, Sendable {
  struct Webhook: Codable, Equatable, Sendable {
    struct Repository: Codable, Equatable, Sendable {
      let host: String
      let port: Int?
      let owner: String
      let ownerDID: DID
      let name: String
    }

    struct Source: Codable, Equatable, Sendable {
      let branch: String
      let revision: String?
      let repositoryDID: String?
    }

    let canonicalSource: String
    let repository: Repository
    let pullNumber: Int64
    let authorDID: DID
    let title: String
    let body: String?
    let targetBranch: String
    let source: Source?
    let roundNumber: Int
    let state: String
    let pageURL: URL
    let patchURL: URL
    let createdAt: String
  }

  let watchID: WebhookInboxDelivery.WatchID
  let deliveryID: WebhookInboxDelivery.DeliveryID
  let webhook: Webhook
  let receivedAt: Date
}

struct TangledWorkspaceProposal: Equatable, Sendable {
  let id: ATProto.URI
  let discoveryDeliveryID: WebhookInboxDelivery.DeliveryID
  let watchID: WebhookInboxDelivery.WatchID
  let webhook: TangledPullCreated.Webhook
  let observedAt: Date
}

struct TangledPullURIResolver: Sendable {
  var resolve: @Sendable (TangledPullCreated) async throws -> ATProto.URI

  init(
    resolve: @escaping @Sendable (TangledPullCreated) async throws -> ATProto.URI
  ) {
    self.resolve = resolve
  }

  static var live: Self {
    Self { pull in
      @Dependency(\.httpClient) var httpClient
      let data: Data = try await withDependencies {
        $0.logBody = false
      } operation: {
        try await httpClient.get(pull.webhook.pageURL, decodingTo: Data.self)
      }
      guard let html = String(data: data, encoding: .utf8) else {
        throw TangledPullURIResolutionError.invalidHTML
      }
      return try pullURI(in: html, expectedAuthorDID: pull.webhook.authorDID)
    }
  }

  static func pullURI(
    in html: String,
    expectedAuthorDID: DID
  ) throws -> ATProto.URI {
    let values = html.matches(of: /data-aturi="(?<uri>[^"]+)"/)
      .map { String($0.output.uri) }
    guard !values.isEmpty else {
      throw TangledPullURIResolutionError.missingURI
    }
    guard values.count == 1 else {
      throw TangledPullURIResolutionError.multipleURIs
    }
    let value = values[0]
    guard let uri = ATProto.URI(value) else {
      throw TangledPullURIResolutionError.invalidURI(value)
    }
    guard uri.collection == Self.pullCollection, uri.rkey != nil else {
      throw TangledPullURIResolutionError.unsupportedURI(value)
    }
    guard case .did(let authorDID) = uri.authority,
      authorDID == expectedAuthorDID
    else {
      throw TangledPullURIResolutionError.authorMismatch(value)
    }
    return uri
  }

  private static let pullCollection: ATProto.NSID = "sh.tangled.repo.pull"
}

enum TangledPullURIResolutionError: Error, Equatable, Sendable {
  case invalidHTML
  case missingURI
  case multipleURIs
  case invalidURI(String)
  case unsupportedURI(String)
  case authorMismatch(String)
}

struct TangledWorkspaceProposalProcessor: Sendable {
  let configuration: TangledWebhookConfiguration
  let store: OpenMusicEventAppViewStore
  let resolver: TangledPullURIResolver

  init(
    configuration: TangledWebhookConfiguration,
    store: OpenMusicEventAppViewStore,
    resolver: TangledPullURIResolver = .live
  ) {
    self.configuration = configuration
    self.store = store
    self.resolver = resolver
  }

  func pendingPulls() async throws -> [TangledPullCreated] {
    try await store.pendingTangledPullCreatedDeliveries().map { delivery in
      guard let watch = configuration.watchesByID[delivery.watchID] else {
        throw TangledWorkspaceProposalProcessingError.watchUnavailable(delivery.watchID)
      }
      return try TangledPullCreated(
        payload: delivery.payload,
        deliveryID: delivery.deliveryID,
        receivedAt: delivery.receivedAt,
        watch: watch
      )
    }
  }

  @discardableResult
  func process(_ pull: TangledPullCreated) async throws -> TangledWorkspaceProposal {
    let proposal = TangledWorkspaceProposal(
      id: try await resolver.resolve(pull),
      discoveryDeliveryID: pull.deliveryID,
      watchID: pull.watchID,
      webhook: pull.webhook,
      observedAt: pull.receivedAt
    )
    try await store.upsert(proposal)
    return proposal
  }
}

enum TangledWorkspaceProposalProcessingError: Error, Equatable, Sendable {
  case watchUnavailable(WebhookInboxDelivery.WatchID)
}

struct TangledWorkspaceProposalService: Service {
  let processor: TangledWorkspaceProposalProcessor
  let clock = ContinuousClock()

  func run() async throws {
    do {
      try await cancelWhenGracefulShutdown {
        while true {
          for pull in try await processor.pendingPulls() {
            do {
              try await processor.process(pull)
            } catch {
              reportIssue(error)
            }
          }
          try await clock.sleep(for: .seconds(2))
        }
      }
    } catch is CancellationError {
    }
  }
}

extension OpenMusicEventAppViewStore {
  func pendingTangledPullCreatedDeliveries() async throws -> [WebhookInboxDelivery] {
    try await database.read { database in
      let rows =
        try WebhookInboxDeliveryRow
        .where { $0.source.eq(WebhookInboxDelivery.Source.tangled.rawValue) }
        .where { $0.event.eq("pull_request:created") }
        .order(by: \.receivedAt)
        .fetchAll(database)
      var pending: [WebhookInboxDelivery] = []
      for row in rows {
        let proposal =
          try TangledWorkspaceProposalRow
          .where { $0.discoveryDeliveryID.eq(row.deliveryID) }
          .fetchOne(database)
        if proposal == nil {
          pending.append(row.delivery)
        }
      }
      return pending
    }
  }

  func upsert(_ proposal: TangledWorkspaceProposal) async throws {
    let row = try TangledWorkspaceProposalRow(proposal)
    try await database.write { database in
      try TangledWorkspaceProposalRow.upsert { row }.execute(database)
    }
  }

  func workspaceProposal(id: ATProto.URI) async throws -> TangledWorkspaceProposal? {
    try await database.read { database in
      try TangledWorkspaceProposalRow.find(id.description)
        .fetchOne(database)
        .map { try $0.proposal() }
    }
  }
}

@Table("workspaceProposals")
struct TangledWorkspaceProposalRow: Equatable, Sendable {
  @Column(primaryKey: true) var uri: String
  var discoveryDeliveryID: String
  var watchID: String
  var pullNumber: Int64
  var state: String
  var webhook: Data
  var observedAt: Date

  init(_ proposal: TangledWorkspaceProposal) throws {
    uri = proposal.id.description
    discoveryDeliveryID = proposal.discoveryDeliveryID.rawValue
    watchID = proposal.watchID.rawValue
    pullNumber = proposal.webhook.pullNumber
    state = proposal.webhook.state
    webhook = try JSONEncoder().encode(proposal.webhook)
    observedAt = proposal.observedAt
  }

  func proposal() throws -> TangledWorkspaceProposal {
    guard let id = ATProto.URI(uri) else {
      throw TangledWorkspaceProposalPersistenceError.invalidURI(uri)
    }
    return TangledWorkspaceProposal(
      id: id,
      discoveryDeliveryID: .init(rawValue: discoveryDeliveryID),
      watchID: .init(rawValue: watchID),
      webhook: try JSONDecoder().decode(TangledPullCreated.Webhook.self, from: webhook),
      observedAt: observedAt
    )
  }
}

enum TangledWorkspaceProposalPersistenceError: Error, Equatable, Sendable {
  case invalidURI(String)
}

enum TangledWorkspaceProposalSchema {
  static func registerMigration(into migrator: inout DatabaseMigrator) {
    migrator.registerMigration("Create Workspace proposals") { database in
      let tableName = TangledWorkspaceProposalRow.tableName
      let deliveryIndexName = "\(tableName)_discoveryDeliveryID"
      try #sql(
        """
        CREATE TABLE \(quote: tableName) (
          "uri" TEXT PRIMARY KEY NOT NULL,
          "discoveryDeliveryID" TEXT NOT NULL,
          "watchID" TEXT NOT NULL,
          "pullNumber" INTEGER NOT NULL,
          "state" TEXT NOT NULL,
          "webhook" BLOB NOT NULL,
          "observedAt" TEXT NOT NULL
        ) STRICT
        """
      )
      .execute(database)
      try #sql(
        """
        CREATE UNIQUE INDEX \(quote: deliveryIndexName)
        ON \(quote: tableName) ("discoveryDeliveryID")
        """
      )
      .execute(database)
    }
  }
}
