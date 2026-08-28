import ATProto
import AppViewIndex
import Dependencies
import Foundation
import GRDB
import HTTPClient
import IssueReporting
import SQLiteData
import ServiceLifecycle
import TangledLexicon

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
  struct WebhookObservation: Equatable, Sendable {
    let deliveryID: WebhookInboxDelivery.DeliveryID
    let watchID: WebhookInboxDelivery.WatchID
    let value: TangledPullCreated.Webhook
    let observedAt: Date
  }

  enum RecordObservation: Equatable, Sendable {
    case present(
      cid: ATProto.CID,
      sequence: Int64,
      value: TangledPullRecord
    )
    case deleted(sequence: Int64)
  }

  let id: ATProto.URI
  let webhook: WebhookObservation?
  let record: RecordObservation?
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
    let id = try await resolver.resolve(pull)
    return try await store.recordWorkspaceProposal(
      id: id,
      webhook: TangledWorkspaceProposal.WebhookObservation(
        deliveryID: pull.deliveryID,
        watchID: pull.watchID,
        value: pull.webhook,
        observedAt: pull.receivedAt
      )
    )
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
          .where { $0.webhookDeliveryID.eq(row.deliveryID) }
          .fetchOne(database)
        if proposal == nil {
          pending.append(row.delivery)
        }
      }
      return pending
    }
  }

  func recordWorkspaceProposal(
    id: ATProto.URI,
    webhook: TangledWorkspaceProposal.WebhookObservation
  ) async throws -> TangledWorkspaceProposal {
    try await database.write { database in
      var row = try TangledWorkspaceProposalRow.find(id.description)
        .fetchOne(database)
        ?? TangledWorkspaceProposalRow(uri: id.description)
      try row.hydrate(webhook)
      try TangledWorkspaceProposalRow.upsert { row }.execute(database)
      return try row.proposal()
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

extension OpenMusicEventAppViewStore {
  func tangledWorkspaceProposalRecordIndex(
    configuration: TangledWebhookConfiguration
  ) -> AppViewRecordIndex<TangledPullRecord> {
    AppViewRecordIndex<TangledPullRecord>(collection: TangledNSID.pull)
      .project { mutation, database in
        try TangledWorkspaceProposalRow.apply(
          mutation,
          configuration: configuration,
          in: database
        )
      }
  }
}

@Table("workspaceProposals")
struct TangledWorkspaceProposalRow: Equatable, Sendable {
  @Column(primaryKey: true) var uri: String
  var webhookDeliveryID: String?
  var webhookWatchID: String?
  var webhookPullNumber: Int64?
  var webhookState: String?
  var webhook: Data?
  var webhookObservedAt: Date?
  var recordCID: String?
  var recordSequence: Int64?
  var recordDeleted: Bool?
  var record: Data?

  init(uri: String) {
    self.uri = uri
  }

  mutating func hydrate(
    _ observation: TangledWorkspaceProposal.WebhookObservation
  ) throws {
    webhookDeliveryID = observation.deliveryID.rawValue
    webhookWatchID = observation.watchID.rawValue
    webhookPullNumber = observation.value.pullNumber
    webhookState = observation.value.state
    webhook = try JSONEncoder().encode(observation.value)
    webhookObservedAt = observation.observedAt
  }

  mutating func hydrate(
    _ observation: TangledWorkspaceProposal.RecordObservation
  ) throws {
    switch observation {
    case let .present(cid, sequence, value):
      recordCID = cid.rawValue
      recordSequence = sequence
      recordDeleted = false
      record = try JSONEncoder().encode(value)

    case let .deleted(sequence):
      recordCID = nil
      recordSequence = sequence
      recordDeleted = true
      record = nil
    }
  }

  func proposal() throws -> TangledWorkspaceProposal {
    guard let id = ATProto.URI(uri) else {
      throw TangledWorkspaceProposalPersistenceError.invalidURI(uri)
    }
    let webhookObservation: TangledWorkspaceProposal.WebhookObservation?
    switch (
      webhookDeliveryID,
      webhookWatchID,
      webhook,
      webhookObservedAt
    ) {
    case let (.some(deliveryID), .some(watchID), .some(webhook), .some(observedAt)):
      webhookObservation = TangledWorkspaceProposal.WebhookObservation(
        deliveryID: .init(rawValue: deliveryID),
        watchID: .init(rawValue: watchID),
        value: try JSONDecoder().decode(TangledPullCreated.Webhook.self, from: webhook),
        observedAt: observedAt
      )
    case (nil, nil, nil, nil):
      webhookObservation = nil
    default:
      throw TangledWorkspaceProposalPersistenceError.corruptHydration(uri)
    }

    let recordObservation: TangledWorkspaceProposal.RecordObservation?
    switch (recordCID, recordSequence, recordDeleted, record) {
    case (nil, nil, nil, nil):
      recordObservation = nil
    case let (.some(cid), .some(sequence), .some(false), .some(record)):
      recordObservation = .present(
        cid: ATProto.CID(cid),
        sequence: sequence,
        value: try JSONDecoder().decode(TangledPullRecord.self, from: record)
      )
    case let (nil, .some(sequence), .some(true), nil):
      recordObservation = .deleted(sequence: sequence)
    default:
      throw TangledWorkspaceProposalPersistenceError.corruptHydration(uri)
    }

    return TangledWorkspaceProposal(
      id: id,
      webhook: webhookObservation,
      record: recordObservation
    )
  }

  static func apply(
    _ mutation: AppView.RecordMutation<TangledPullRecord>,
    configuration: TangledWebhookConfiguration,
    in database: Database
  ) throws {
    let uri: ATProto.URI
    let observation: TangledWorkspaceProposal.RecordObservation?
    switch mutation {
    case let .create(current):
      uri = current.uri
      observation = configuration.includes(current.value)
        ? .present(
          cid: current.cid,
          sequence: current.sequence,
          value: current.value
        )
        : nil

    case let .update(previous, current):
      uri = current.uri
      if configuration.includes(current.value) {
        observation = .present(
          cid: current.cid,
          sequence: current.sequence,
          value: current.value
        )
      } else if configuration.includes(previous.value) {
        observation = .deleted(sequence: current.sequence)
      } else {
        observation = nil
      }

    case let .delete(previous, current):
      uri = current.uri
      let existingProposal = try Self.find(uri.description).fetchOne(database)
      observation = previous.map { configuration.includes($0.value) } == true
        || existingProposal != nil
        ? .deleted(sequence: current.sequence)
        : nil
    }

    guard let observation else { return }
    var row = try Self.find(uri.description).fetchOne(database)
      ?? Self(uri: uri.description)
    try row.hydrate(observation)
    try Self.upsert { row }.execute(database)
  }
}

private extension TangledWebhookConfiguration {
  func includes(_ pull: TangledPullRecord) -> Bool {
    watches.contains { watch in
      watch.repositoryOwnerDID == pull.target.repo
        && normalizedTangledBranch(watch.ref) == normalizedTangledBranch(pull.target.branch)
    }
  }
}

private func normalizedTangledBranch(_ value: String) -> String {
  let prefix = "refs/heads/"
  return value.hasPrefix(prefix) ? String(value.dropFirst(prefix.count)) : value
}

enum TangledWorkspaceProposalPersistenceError: Error, Equatable, Sendable {
  case corruptHydration(String)
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
    migrator.registerMigration("Unify Workspace proposal hydration") { database in
      let tableName = TangledWorkspaceProposalRow.tableName
      let replacementTableName = "\(tableName)_unified"
      let deliveryIndexName = "\(tableName)_webhookDeliveryID"
      try #sql(
        """
        CREATE TABLE \(quote: replacementTableName) (
          "uri" TEXT PRIMARY KEY NOT NULL,
          "webhookDeliveryID" TEXT,
          "webhookWatchID" TEXT,
          "webhookPullNumber" INTEGER,
          "webhookState" TEXT,
          "webhook" BLOB,
          "webhookObservedAt" TEXT,
          "recordCID" TEXT,
          "recordSequence" INTEGER,
          "recordDeleted" INTEGER,
          "record" BLOB,
          CHECK (
            (
              "webhookDeliveryID" IS NULL
              AND "webhookWatchID" IS NULL
              AND "webhookPullNumber" IS NULL
              AND "webhookState" IS NULL
              AND "webhook" IS NULL
              AND "webhookObservedAt" IS NULL
            )
            OR
            (
              "webhookDeliveryID" IS NOT NULL
              AND "webhookWatchID" IS NOT NULL
              AND "webhookPullNumber" IS NOT NULL
              AND "webhookState" IS NOT NULL
              AND "webhook" IS NOT NULL
              AND "webhookObservedAt" IS NOT NULL
            )
          ),
          CHECK (
            (
              "recordCID" IS NULL
              AND "recordSequence" IS NULL
              AND "recordDeleted" IS NULL
              AND "record" IS NULL
            )
            OR
            (
              "recordCID" IS NOT NULL
              AND "recordSequence" IS NOT NULL
              AND "recordDeleted" = 0
              AND "record" IS NOT NULL
            )
            OR
            (
              "recordCID" IS NULL
              AND "recordSequence" IS NOT NULL
              AND "recordDeleted" = 1
              AND "record" IS NULL
            )
          )
        ) STRICT
        """
      )
      .execute(database)
      try #sql(
        """
        INSERT INTO \(quote: replacementTableName) (
          "uri",
          "webhookDeliveryID",
          "webhookWatchID",
          "webhookPullNumber",
          "webhookState",
          "webhook",
          "webhookObservedAt"
        )
        SELECT
          "uri",
          "discoveryDeliveryID",
          "watchID",
          "pullNumber",
          "state",
          "webhook",
          "observedAt"
        FROM \(quote: tableName)
        """
      )
      .execute(database)
      try #sql("DROP TABLE \(quote: tableName)").execute(database)
      try #sql(
        "ALTER TABLE \(quote: replacementTableName) RENAME TO \(quote: tableName)"
      )
      .execute(database)
      try #sql(
        """
        CREATE UNIQUE INDEX \(quote: deliveryIndexName)
        ON \(quote: tableName) ("webhookDeliveryID")
        """
      )
      .execute(database)
    }
  }
}
