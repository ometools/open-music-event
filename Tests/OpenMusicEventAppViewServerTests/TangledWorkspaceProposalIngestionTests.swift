import ATProtoAppView
import ATProto
import CustomDump
import Dependencies
import Foundation
import GRDB
import ATProtoStreams
import ATProtoTypes
import OpenMusicEventLexicon
import OpenMusicEventSourceClone
import SQLiteData
import TangledLexicon
import Testing

@testable import OpenMusicEventAppViewServer

@Suite(.serialized)
struct TangledWorkspaceProposalIngestionTests {
  @Test
  func `discovers watched pulls before replaying statuses`() async throws {
    let database = try DatabaseQueue()
    let store = try OpenMusicEventAppViewStore(
      database: database,
      initiallyReady: false
    )
    let messages = try Self.replayMessages()
    let connections = HydrantConnectionRecorder()
    let client = HydrantClient(runMessages: { configuration, receive in
      let connection = await connections.begin(cursor: configuration.cursor)

      if connection == 2 {
        // The bounded pass has established only the watched pull. Status records were ignored.
        let pullCount = try withDependencies {
          $0.defaultDatabase = database
        } operation: {
          try AppViewIndexDatabase.indexedRecordCount(collection: TangledNSID.pull)
        }
        let statusCount = try withDependencies {
          $0.defaultDatabase = database
        } operation: {
          try AppViewIndexDatabase.indexedRecordCount(collection: TangledNSID.pullStatus)
        }
        let proposalCount = try await database.read { database in
          try TangledWorkspaceProposalRow.fetchCount(database)
        }
        expectNoDifference(pullCount, 1)
        expectNoDifference(statusCount, 0)
        expectNoDifference(proposalCount, 1)
      }

      for message in messages {
        try await receive(message)
      }
    })

    try await OpenMusicEventAppViewIngestion(
      store: store,
      configuration: Self.configuration,
      tangledWebhookConfiguration: try TangledWebhookConfiguration(watches: [Self.watch]),
      client: client
    )
    .run()

    // The full replay can now retain the relevant historical status even though it precedes the pull.
    let proposal = try #require(try await store.workspaceProposal(id: Self.pullURI))
    expectNoDifference(proposal.status?.uri, Self.relevantStatusURI)
    expectNoDifference(proposal.status?.status, .merged)
    expectNoDifference(proposal.lifecycle, .merged)

    let pullCount = try withDependencies {
      $0.defaultDatabase = database
    } operation: {
      try AppViewIndexDatabase.indexedRecordCount(collection: TangledNSID.pull)
    }
    let statusCount = try withDependencies {
      $0.defaultDatabase = database
    } operation: {
      try AppViewIndexDatabase.indexedRecordCount(collection: TangledNSID.pullStatus)
    }
    let unrelatedStatus = try withDependencies {
      $0.defaultDatabase = database
    } operation: {
      try AppViewIndexDatabase.record(uri: Self.unrelatedStatusURI)
    }
    let checkpoints = try withDependencies {
      $0.defaultDatabase = database
    } operation: {
      try [
        AppViewIndexDatabase.checkpoint(id: Self.discoverySubscriptionID)?.sequence,
        AppViewIndexDatabase.checkpoint(id: Self.eventGraphSubscriptionID)?.sequence,
      ]
    }
    let proposalCount = try await database.read { database in
      try TangledWorkspaceProposalRow.fetchCount(database)
    }
    let readiness = await store.readiness.snapshot()
    let cursors = await connections.cursors
    expectNoDifference(pullCount, 1)
    expectNoDifference(statusCount, 1)
    expectNoDifference(unrelatedStatus, nil)
    expectNoDifference(proposalCount, 1)
    expectNoDifference(checkpoints, [3, 3])
    expectNoDifference(readiness, .ready(cursor: 3))
    expectNoDifference(cursors, [0, 0])
  }

  @Test
  func `restarts each pass from its independent checkpoint without duplicates`() async throws {
    let database = try DatabaseQueue()
    let store = try OpenMusicEventAppViewStore(
      database: database,
      initiallyReady: false
    )
    let messages = try Self.replayMessages()
    let firstConnections = HydrantConnectionRecorder()
    let interruptedClient = HydrantClient(runMessages: { configuration, receive in
      let connection = await firstConnections.begin(cursor: configuration.cursor)
      guard connection == 1 else {
        throw HydrantIngestionTestError.interrupted
      }
      for message in messages {
        try await receive(message)
      }
    })

    // Discovery finishes durably, but the full replay is interrupted before it starts.
    let interrupted = await #expect(throws: HydrantIngestionTestError.self) {
      try await OpenMusicEventAppViewIngestion(
        store: store,
        configuration: Self.configuration,
        tangledWebhookConfiguration: try TangledWebhookConfiguration(watches: [Self.watch]),
        client: interruptedClient
      )
      .run()
    }
    expectNoDifference(interrupted, .interrupted)

    let interruptedCheckpoints = try withDependencies {
      $0.defaultDatabase = database
    } operation: {
      try [
        AppViewIndexDatabase.checkpoint(id: Self.discoverySubscriptionID)?.sequence,
        AppViewIndexDatabase.checkpoint(id: Self.eventGraphSubscriptionID)?.sequence,
      ]
    }
    let interruptedReadiness = await store.readiness.snapshot()
    expectNoDifference(interruptedCheckpoints, [3, nil])
    expectNoDifference(interruptedReadiness, .catchingUp)

    // Restart resumes discovery after sequence 3, then replays the still-fresh full subscription.
    let restartConnections = HydrantConnectionRecorder()
    let restartClient = HydrantClient(runMessages: { configuration, receive in
      let connection = await restartConnections.begin(cursor: configuration.cursor)
      if connection == 1 {
        try await receive(.caughtUp(.init(cursor: 3)))
      } else {
        for message in messages {
          try await receive(message)
        }
      }
    })
    try await OpenMusicEventAppViewIngestion(
      store: store,
      configuration: Self.configuration,
      tangledWebhookConfiguration: try TangledWebhookConfiguration(watches: [Self.watch]),
      client: restartClient
    )
    .run()
    let restartCursors = await restartConnections.cursors
    expectNoDifference(restartCursors, [4, 0])

    // A later process restart resumes both caught-up checkpoints and writes no duplicates.
    let caughtUpConnections = HydrantConnectionRecorder()
    let caughtUpClient = HydrantClient(runMessages: { configuration, receive in
      _ = await caughtUpConnections.begin(cursor: configuration.cursor)
      try await receive(.caughtUp(.init(cursor: 3)))
    })
    try await OpenMusicEventAppViewIngestion(
      store: store,
      configuration: Self.configuration,
      tangledWebhookConfiguration: try TangledWebhookConfiguration(watches: [Self.watch]),
      client: caughtUpClient
    )
    .run()

    let proposal = try #require(try await store.workspaceProposal(id: Self.pullURI))
    let proposalCount = try await database.read { database in
      try TangledWorkspaceProposalRow.fetchCount(database)
    }
    let pullCount = try withDependencies {
      $0.defaultDatabase = database
    } operation: {
      try AppViewIndexDatabase.indexedRecordCount(collection: TangledNSID.pull)
    }
    let statusCount = try withDependencies {
      $0.defaultDatabase = database
    } operation: {
      try AppViewIndexDatabase.indexedRecordCount(collection: TangledNSID.pullStatus)
    }
    let caughtUpCursors = await caughtUpConnections.cursors
    let readiness = await store.readiness.snapshot()
    expectNoDifference(proposal.status?.status, .merged)
    expectNoDifference(proposalCount, 1)
    expectNoDifference(pullCount, 1)
    expectNoDifference(statusCount, 1)
    expectNoDifference(caughtUpCursors, [4, 4])
    expectNoDifference(readiness, .ready(cursor: 3))
  }

  @Test
  func `calendar-only ingestion opens only the continuous connection`() async throws {
    let database = try DatabaseQueue()
    let store = try OpenMusicEventAppViewStore(
      database: database,
      initiallyReady: false
    )
    let connections = HydrantConnectionRecorder()
    let client = HydrantClient(runMessages: { configuration, receive in
      _ = await connections.begin(cursor: configuration.cursor)
      try await receive(.caughtUp(.init(cursor: 7)))
    })

    try await OpenMusicEventAppViewIngestion(
      store: store,
      configuration: Self.configuration,
      client: client
    )
    .run()

    let cursors = await connections.cursors
    let readiness = await store.readiness.snapshot()
    expectNoDifference(cursors, [0])
    expectNoDifference(readiness, .ready(cursor: 7))
  }
}

extension TangledWorkspaceProposalIngestionTests {
  static let configuration = AppViewIngestionConfiguration(
    endpoint: "ws://hydrant.test/stream",
    subscriptionID: "hydrant|ome-appview-v3"
  )
  static let discoverySubscriptionID = "hydrant|ome-appview-v3|workspace-pulls"
  static let eventGraphSubscriptionID = "hydrant|ome-appview-v3|event-graph-v3"
  static let repositoryDID = DID("did:plc:workspace-repository")!
  static let pullAuthorDID = DID("did:plc:proposal-author")!
  static let statusAuthorDID = DID("did:plc:status-author")!
  static let unrelatedStatusAuthorDID = DID("did:plc:unrelated-status-author")!
  static let pullURI = ATProto.URI(
    "at://did:plc:proposal-author/sh.tangled.repo.pull/3mq4ybvnfc522"
  )!
  static let relevantStatusURI = ATProto.URI(
    "at://did:plc:status-author/sh.tangled.repo.pull.status/3relevant"
  )!
  static let unrelatedStatusURI = ATProto.URI(
    "at://did:plc:unrelated-status-author/sh.tangled.repo.pull.status/3unrelated"
  )!
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

  static func replayMessages() throws -> [HydrantClient.Message] {
    [
      try statusMessage(
        id: 1,
        author: unrelatedStatusAuthorDID,
        rkey: "3unrelated",
        cid: "bafyreistatusunrelated",
        pull: ATProto.URI("at://did:plc:other/sh.tangled.repo.pull/3other")!
      ),
      try statusMessage(
        id: 2,
        author: statusAuthorDID,
        rkey: "3relevant",
        cid: "bafyreistatusmerged",
        pull: pullURI
      ),
      try pullMessage(id: 3),
      .caughtUp(.init(cursor: 3)),
    ]
  }

  static func statusMessage(
    id: UInt64,
    author: DID,
    rkey: String,
    cid: ATProto.CID,
    pull: ATProto.URI
  ) throws -> HydrantClient.Message {
    .event(
      HydrantClient.Event(
        id: id,
        payload: .record(
          HydrantClient.Record(
            live: false,
            did: author,
            revision: "rev-\(id)",
            collection: TangledNSID.pullStatus,
            rkey: .init(rawValue: rkey),
            action: .create,
            record: try JSONEncoder().encode(
              TangledPullStatusRecord(
                pull: pull,
                status: .merged,
                createdAt: "2026-08-24T20:00:00Z"
              )
            ),
            cid: cid
          )
        )
      )
    )
  }

  static func pullMessage(id: UInt64) throws -> HydrantClient.Message {
    .event(
      HydrantClient.Event(
        id: id,
        payload: .record(
          HydrantClient.Record(
            live: false,
            did: pullAuthorDID,
            revision: "rev-\(id)",
            collection: TangledNSID.pull,
            rkey: .init(rawValue: "3mq4ybvnfc522"),
            action: .create,
            record: try JSONEncoder().encode(
              TangledPullRecord(
                target: TangledPullRecord.Target(
                  repo: repositoryDID,
                  branch: "main"
                ),
                title: "Hydrate proposal status",
                body: "Carries the old and new artist values.",
                rounds: [
                  TangledPullRecord.Round(
                    patchBlob: ATProto.Blob(
                      ref: "bafkreipatch",
                      mimeType: "application/gzip",
                      size: 123
                    ),
                    createdAt: "2026-08-24T20:00:00Z"
                  )
                ],
                source: TangledPullRecord.Source(
                  branch: "artist-preview",
                  repo: pullAuthorDID
                ),
                createdAt: "2026-08-24T20:00:00Z"
              )
            ),
            cid: "bafyreipull"
          )
        )
      )
    )
  }
}

private actor HydrantConnectionRecorder {
  private(set) var cursors: [UInt64?] = []

  func begin(cursor: UInt64?) -> Int {
    cursors.append(cursor)
    return cursors.count
  }
}

private enum HydrantIngestionTestError: Error, Equatable, Sendable {
  case interrupted
}
