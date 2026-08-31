import ATProto
import AppViewIndex
import Crypto
import Dependencies
import Foundation
import GRDB
import HTTPClient
import IssueReporting
import LexiconSQLiteData
import OpenMusicEventLexicon
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

  struct StatusObservation: Equatable, Sendable {
    let uri: ATProto.URI
    let cid: ATProto.CID
    let sequence: Int64
    let status: Open<TangledPullStatus>
    let createdAt: TangledTimestamp
  }

  struct RenderInput: Codable, Equatable, Sendable {
    struct Key: Codable, Equatable, Hashable, RawRepresentable, Sendable {
      let rawValue: String

      init(rawValue: String) {
        self.rawValue = rawValue
      }
    }

    let proposalRevision: ATProto.CID
    let targetRevision: String
    let roundNumber: Int
    let patchDigest: String
    let rendererVersion: Int

    func key() throws -> Key {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      return Key(
        rawValue: Data(SHA256.hash(data: try encoder.encode(self))).base64EncodedString()
      )
    }
  }

  enum RenderState: Equatable, Sendable {
    case awaitingInput
    case pending
    case ready(OME.WorkspaceProposal.Presentation)
  }

  enum RenderCompletionOutcome: Equatable, Sendable {
    case accepted
    case superseded
  }

  let id: ATProto.URI
  let webhook: WebhookObservation?
  let record: RecordObservation?
  let status: StatusObservation?
  let renderInput: RenderInput?
  let renderState: RenderState

  var lifecycle: Open<TangledPullStatus> {
    if let status {
      return status.status
    }
    switch webhook?.value.state {
    case TangledPullState.closed.rawValue:
      return .closed
    case TangledPullState.merged.rawValue:
      return .merged
    case TangledPullState.open.rawValue:
      return .open
    case let value?:
      return .unknown(.string(value))
    case nil:
      return .open
    }
  }

  init(
    id: ATProto.URI,
    webhook: WebhookObservation?,
    record: RecordObservation?,
    status: StatusObservation? = nil,
    renderInput: RenderInput? = nil,
    renderState: RenderState = .awaitingInput
  ) {
    self.id = id
    self.webhook = webhook
    self.record = record
    self.status = status
    self.renderInput = renderInput
    self.renderState = renderState
  }
}

private struct PersistedWorkspaceProposalRender: Codable, Equatable, Sendable {
  struct Completion: Codable, Equatable, Sendable {
    let inputKey: TangledWorkspaceProposal.RenderInput.Key
    let presentation: OME.WorkspaceProposal.Presentation
  }

  let input: TangledWorkspaceProposal.RenderInput
  var completion: Completion?
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

  func prepareWorkspaceProposalRender(
    id: ATProto.URI,
    input: TangledWorkspaceProposal.RenderInput
  ) async throws -> TangledWorkspaceProposal {
    try await database.write { database in
      guard var row = try TangledWorkspaceProposalRow.find(id.description).fetchOne(database)
      else {
        throw TangledWorkspaceProposalPersistenceError.missingProposal(id.description)
      }
      try row.prepareRender(input)
      try TangledWorkspaceProposalRow.upsert { row }.execute(database)
      return try row.proposal()
    }
  }

  func completeWorkspaceProposalRender(
    id: ATProto.URI,
    expectedInput: TangledWorkspaceProposal.RenderInput,
    presentation: OME.WorkspaceProposal.Presentation
  ) async throws -> TangledWorkspaceProposal.RenderCompletionOutcome {
    try await database.write { database in
      guard var row = try TangledWorkspaceProposalRow.find(id.description).fetchOne(database)
      else {
        throw TangledWorkspaceProposalPersistenceError.missingProposal(id.description)
      }
      guard try row.completeRender(expectedInput: expectedInput, presentation: presentation)
      else {
        return .superseded
      }
      try TangledWorkspaceProposalRow.upsert { row }.execute(database)
      return .accepted
    }
  }
}

extension OpenMusicEventAppViewStore {
  func tangledWorkspaceProposalRecordIndex(
    repositoryDIDs: Set<DID>
  ) -> AppViewRecordIndex<TangledPullRecord> {
    AppViewRecordIndex<TangledPullRecord>(collection: TangledNSID.pull)
      .filter { mutation, database in
        try TangledWorkspaceProposalRow.includes(
          mutation,
          repositoryDIDs: repositoryDIDs,
          in: database
        )
      }
      .project { mutation, database in
        try TangledWorkspaceProposalRow.apply(mutation, in: database)
      }
  }

  func tangledWorkspaceProposalStatusRecordIndex()
    -> AppViewRecordIndex<TangledPullStatusRecord>
  {
    AppViewRecordIndex<TangledPullStatusRecord>(collection: TangledNSID.pullStatus)
      .filter { mutation, database in
        try TangledWorkspaceProposalRow.includes(mutation, in: database)
      }
      .project { mutation, database in
        try TangledWorkspaceProposalRow.apply(mutation, in: database)
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
  var statusURI: String?
  var statusCID: String?
  var statusSequence: Int64?
  var statusValue: Open<TangledPullStatus>?
  var statusCreatedAt: String?
  var render: Data?

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

  mutating func hydrate(
    _ observation: TangledWorkspaceProposal.StatusObservation?
  ) {
    statusURI = observation?.uri.description
    statusCID = observation?.cid.rawValue
    statusSequence = observation?.sequence
    statusValue = observation?.status
    statusCreatedAt = observation?.createdAt
  }

  mutating func prepareRender(
    _ input: TangledWorkspaceProposal.RenderInput
  ) throws {
    let existing = try persistedRender()
    self.render = try JSONEncoder().encode(
      PersistedWorkspaceProposalRender(
        input: input,
        completion: existing?.input == input ? existing?.completion : nil
      )
    )
  }

  mutating func completeRender(
    expectedInput: TangledWorkspaceProposal.RenderInput,
    presentation: OME.WorkspaceProposal.Presentation
  ) throws -> Bool {
    guard var render = try persistedRender(),
      render.input == expectedInput,
      try render.input.key() == expectedInput.key(),
      try acceptsRender(for: expectedInput.proposalRevision)
    else {
      return false
    }
    render.completion = PersistedWorkspaceProposalRender.Completion(
      inputKey: try expectedInput.key(),
      presentation: presentation
    )
    self.render = try JSONEncoder().encode(render)
    return true
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

    let statusObservation: TangledWorkspaceProposal.StatusObservation?
    switch (statusURI, statusCID, statusSequence, statusValue, statusCreatedAt) {
    case (nil, nil, nil, nil, nil):
      statusObservation = nil
    case let (
      .some(statusURI),
      .some(statusCID),
      .some(statusSequence),
      .some(statusValue),
      .some(statusCreatedAt)
    ):
      guard let statusURI = ATProto.URI(statusURI) else {
        throw TangledWorkspaceProposalPersistenceError.invalidURI(statusURI)
      }
      statusObservation = TangledWorkspaceProposal.StatusObservation(
        uri: statusURI,
        cid: ATProto.CID(statusCID),
        sequence: statusSequence,
        status: statusValue,
        createdAt: statusCreatedAt
      )
    default:
      throw TangledWorkspaceProposalPersistenceError.corruptHydration(uri)
    }

    let persistedRender = try persistedRender()
    let renderState: TangledWorkspaceProposal.RenderState
    if let persistedRender {
      switch recordObservation {
      case .deleted:
        renderState = .awaitingInput
      case let .present(cid, _, _) where cid != persistedRender.input.proposalRevision:
        renderState = .pending
      default:
        let inputKey = try persistedRender.input.key()
        if let completion = persistedRender.completion,
          completion.inputKey == inputKey
        {
          renderState = .ready(completion.presentation)
        } else {
          renderState = .pending
        }
      }
    } else {
      renderState = .awaitingInput
    }

    return TangledWorkspaceProposal(
      id: id,
      webhook: webhookObservation,
      record: recordObservation,
      status: statusObservation,
      renderInput: persistedRender?.input,
      renderState: renderState
    )
  }

  private func persistedRender() throws -> PersistedWorkspaceProposalRender? {
    try render.map {
      try JSONDecoder().decode(PersistedWorkspaceProposalRender.self, from: $0)
    }
  }

  private func acceptsRender(for proposalRevision: ATProto.CID) throws -> Bool {
    switch (recordCID, recordSequence, recordDeleted, record) {
    case (nil, nil, nil, nil):
      return true
    case let (.some(cid), .some, .some(false), .some):
      return cid == proposalRevision.rawValue
    case (nil, .some, .some(true), nil):
      return false
    default:
      throw TangledWorkspaceProposalPersistenceError.corruptHydration(uri)
    }
  }

  static func includes(
    _ mutation: AppView.RecordMutation<TangledPullRecord>,
    repositoryDIDs: Set<DID>,
    in database: Database
  ) throws -> Bool {
    switch mutation {
    case let .create(current):
      let existingProposal = try Self.find(current.uri.description).fetchOne(database)
      return repositoryDIDs.contains(current.value.target.repo) || existingProposal != nil

    case let .update(previous, current):
      let existingProposal = try Self.find(current.uri.description).fetchOne(database)
      return repositoryDIDs.contains(current.value.target.repo)
        || repositoryDIDs.contains(previous.value.target.repo)
        || existingProposal != nil

    case let .delete(previous, current):
      let existingProposal = try Self.find(current.uri.description).fetchOne(database)
      return previous.map { repositoryDIDs.contains($0.value.target.repo) } == true
        || existingProposal != nil
    }
  }

  static func apply(
    _ mutation: AppView.RecordMutation<TangledPullRecord>,
    in database: Database
  ) throws {
    let uri: ATProto.URI
    let observation: TangledWorkspaceProposal.RecordObservation
    switch mutation {
    case let .create(current), let .update(_, current):
      uri = current.uri
      observation = .present(
        cid: current.cid,
        sequence: current.sequence,
        value: current.value
      )

    case let .delete(_, current):
      uri = current.uri
      observation = .deleted(sequence: current.sequence)
    }
    var row = try Self.find(uri.description).fetchOne(database)
      ?? Self(uri: uri.description)
    try row.hydrate(observation)
    try Self.upsert { row }.execute(database)
  }

  static func includes(
    _ mutation: AppView.RecordMutation<TangledPullStatusRecord>,
    in database: Database
  ) throws -> Bool {
    switch mutation {
    case let .create(current):
      return try Self.find(current.value.pull.description).fetchOne(database) != nil

    case let .update(previous, current):
      let currentProposal = try Self.find(current.value.pull.description).fetchOne(database)
      let previousProposal = try Self.find(previous.value.pull.description).fetchOne(database)
      return currentProposal != nil || previousProposal != nil

    case let .delete(previous, _):
      // A previous raw value exists only when this filtered index accepted it.
      return previous != nil
    }
  }

  static func apply(
    _ mutation: AppView.RecordMutation<TangledPullStatusRecord>,
    in database: Database
  ) throws {
    var affectedPulls: [ATProto.URI] = []
    func append(_ pull: ATProto.URI) {
      guard !affectedPulls.contains(pull) else { return }
      affectedPulls.append(pull)
    }
    switch mutation {
    case let .create(current):
      append(current.value.pull)
    case let .update(previous, current):
      append(previous.value.pull)
      append(current.value.pull)
    case let .delete(previous, _):
      if let previous {
        append(previous.value.pull)
      }
    }

    let presentStatuses = try AppViewIndexDatabase.presentRecords(
      collection: TangledNSID.pullStatus,
      in: database
    )
    for pull in affectedPulls {
      guard var proposal = try Self.find(pull.description).fetchOne(database) else {
        continue
      }
      var selected: (
        version: AppView.RecordVersion<Data>,
        record: TangledPullStatusRecord
      )?
      for version in presentStatuses {
        let record = try JSONDecoder().decode(
          TangledPullStatusRecord.self,
          from: version.value
        )
        guard record.pull == pull else { continue }
        if let existing = selected,
          !statusRecord(version, sortsAfter: existing.version)
        {
          continue
        }
        selected = (version, record)
      }
      proposal.hydrate(
        selected.map { selected in
          TangledWorkspaceProposal.StatusObservation(
            uri: selected.version.uri,
            cid: selected.version.cid,
            sequence: selected.version.sequence,
            status: selected.record.status,
            createdAt: selected.record.createdAt
          )
        }
      )
      try Self.upsert { proposal }.execute(database)
    }
  }
}

private func statusRecord(
  _ lhs: AppView.RecordVersion<Data>,
  sortsAfter rhs: AppView.RecordVersion<Data>
) -> Bool {
  let lhsKey = lhs.uri.rkey?.rawValue ?? ""
  let rhsKey = rhs.uri.rkey?.rawValue ?? ""
  if lhsKey != rhsKey {
    return lhsKey > rhsKey
  }
  return lhs.uri.description > rhs.uri.description
}

enum TangledWorkspaceProposalPersistenceError: Error, Equatable, Sendable {
  case corruptHydration(String)
  case invalidTimestamp(String)
  case invalidURI(String)
  case missingProposal(String)
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
    migrator.registerMigration("Add Workspace proposal render state") { database in
      let tableName = TangledWorkspaceProposalRow.tableName
      try #sql(
        "ALTER TABLE \(quote: tableName) ADD COLUMN \"render\" BLOB"
      )
      .execute(database)
    }
    migrator.registerMigration("Add Workspace proposal status hydration") { database in
      let tableName = TangledWorkspaceProposalRow.tableName
      let replacementTableName = "\(tableName)_status"
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
          "statusURI" TEXT,
          "statusCID" TEXT,
          "statusSequence" INTEGER,
          "statusValue" TEXT,
          "statusCreatedAt" TEXT,
          "render" BLOB,
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
          ),
          CHECK (
            (
              "statusURI" IS NULL
              AND "statusCID" IS NULL
              AND "statusSequence" IS NULL
              AND "statusValue" IS NULL
              AND "statusCreatedAt" IS NULL
            )
            OR
            (
              "statusURI" IS NOT NULL
              AND "statusCID" IS NOT NULL
              AND "statusSequence" IS NOT NULL
              AND "statusValue" IS NOT NULL
              AND "statusCreatedAt" IS NOT NULL
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
          "webhookObservedAt",
          "recordCID",
          "recordSequence",
          "recordDeleted",
          "record",
          "render"
        )
        SELECT
          "uri",
          "webhookDeliveryID",
          "webhookWatchID",
          "webhookPullNumber",
          "webhookState",
          "webhook",
          "webhookObservedAt",
          "recordCID",
          "recordSequence",
          "recordDeleted",
          "record",
          "render"
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
