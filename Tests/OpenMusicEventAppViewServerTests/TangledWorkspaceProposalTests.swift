import ATProto
import ATProtoAppView
import CustomDump
import Dependencies
import Foundation
import GRDB
import HTTPClient
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import ATProtoTypes
import OpenMusicEventLexicon
import OpenMusicEventSourceClone
import SQLiteData
import TangledLexicon
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
        webhook: TangledWorkspaceProposal.WebhookObservation(
          deliveryID: .init(rawValue: Self.deliveryID),
          watchID: Self.watch.id,
          value: TangledPullCreated.Webhook(
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
        ),
        record: nil
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
  func `Jetstream enriches the webhook proposal without replacing its observation`() async throws {
    let database = try DatabaseQueue()
    let store = try OpenMusicEventAppViewStore(database: database)
    let indexer = store.appViewRecordIndexer(
      tangledWebhookConfiguration: nil
    )
    let webhookProposal = try Self.webhookProposal()

    // The webhook creates the proposal immediately with its delivery and physical-watch facts.
    _ = try await store.recordWorkspaceProposal(
      id: webhookProposal.id,
      webhook: try #require(webhookProposal.webhook)
    )

    // Jetstream later supplies the content-addressed pull record for the same exact URI.
    // The last watch configuration has retired, so the webhook-created row is the admission fact.
    let record = try Self.pullRecord(title: "Add artist detail previews")
    let version = try AppView.RecordVersion(
      collection: TangledNSID.pull,
      uri: Self.pullURI,
      cid: ATProto.CID("bafyreipullone"),
      value: JSONEncoder().encode(record),
      sequence: 100
    )
    let outcome = try withDependencies {
      $0.defaultDatabase = database
    } operation: {
      try indexer.apply(.put(version)).outcome
    }
    expectNoDifference(outcome, .created)

    let hydrated = try #require(try await store.workspaceProposal(id: Self.pullURI))
    expectNoDifference(
      hydrated,
      TangledWorkspaceProposal(
        id: Self.pullURI,
        webhook: webhookProposal.webhook,
        record: .present(
          cid: ATProto.CID("bafyreipullone"),
          sequence: 100,
          value: record
        )
      )
    )

    // Replaying the same Jetstream version does not re-project or disturb the webhook fields.
    let replayOutcome = try withDependencies {
      $0.defaultDatabase = database
    } operation: {
      try indexer.apply(.put(version)).outcome
    }
    expectNoDifference(replayOutcome, .replay)
    let replayed = try #require(try await store.workspaceProposal(id: Self.pullURI))
    expectNoDifference(replayed, hydrated)
  }

  @Test
  func `a Jetstream rebuild and a later webhook converge on the same proposal row`() async throws {
    let database = try DatabaseQueue()
    let store = try OpenMusicEventAppViewStore(database: database)
    let indexer = store.appViewRecordIndexer(
      tangledWebhookConfiguration: try TangledWebhookConfiguration(watches: [Self.watch])
    )
    let record = try Self.pullRecord(title: "Rebuilt artist detail previews")
    let version = try AppView.RecordVersion(
      collection: TangledNSID.pull,
      uri: Self.pullURI,
      cid: ATProto.CID("bafyreipullrebuilt"),
      value: JSONEncoder().encode(record),
      sequence: 200
    )

    // Replaying Jetstream alone is sufficient to reconstruct the proposal identity and record.
    _ = try withDependencies {
      $0.defaultDatabase = database
    } operation: {
      try indexer.apply(.put(version))
    }
    let rebuilt = try #require(try await store.workspaceProposal(id: Self.pullURI))
    expectNoDifference(
      rebuilt,
      TangledWorkspaceProposal(
        id: Self.pullURI,
        webhook: nil,
        record: .present(
          cid: ATProto.CID("bafyreipullrebuilt"),
          sequence: 200,
          value: record
        )
      )
    )

    // A delayed webhook hydrates its source-owned fields without replacing the rebuilt record.
    let webhookProposal = try Self.webhookProposal()
    _ = try await store.recordWorkspaceProposal(
      id: webhookProposal.id,
      webhook: try #require(webhookProposal.webhook)
    )
    let unified = try #require(try await store.workspaceProposal(id: Self.pullURI))
    expectNoDifference(
      unified,
      TangledWorkspaceProposal(
        id: Self.pullURI,
        webhook: webhookProposal.webhook,
        record: rebuilt.record
      )
    )

    // A later record tombstone remains authoritative without erasing webhook history.
    let deletion = try AppView.RecordDeletion(
      collection: TangledNSID.pull,
      uri: Self.pullURI,
      sequence: 201
    )
    let deleteOutcome = try withDependencies {
      $0.defaultDatabase = database
    } operation: {
      try indexer.apply(.delete(deletion)).outcome
    }
    expectNoDifference(deleteOutcome, .deleted)
    let deleted = try #require(try await store.workspaceProposal(id: Self.pullURI))
    expectNoDifference(
      deleted,
      TangledWorkspaceProposal(
        id: Self.pullURI,
        webhook: webhookProposal.webhook,
        record: .deleted(sequence: 201)
      )
    )
  }

  @Test
  func `render readiness follows exact input while Jetstream and webhook hydrate the proposal`() async throws {
    let database = try DatabaseQueue()
    let store = try OpenMusicEventAppViewStore(database: database)
    let indexer = store.appViewRecordIndexer(
      tangledWebhookConfiguration: try TangledWebhookConfiguration(watches: [Self.watch])
    )
    let webhookProposal = try Self.webhookProposal()
    let record = try Self.pullRecord(title: "Render artist detail previews")
    let firstInput = Self.renderInput(
      proposalRevision: ATProto.CID("bafyreirenderone"),
      targetRevision: "1111111111111111111111111111111111111111",
      roundNumber: 0,
      patchDigest: "first-patch-sha256"
    )
    let secondInput = Self.renderInput(
      proposalRevision: ATProto.CID("bafyreirendertwo"),
      targetRevision: "3333333333333333333333333333333333333333",
      roundNumber: 1,
      patchDigest: "second-patch-sha256"
    )
    let firstPresentation = OME.WorkspaceProposal.Presentation.empty
    let secondPresentation = OME.WorkspaceProposal.Presentation(
      groups: [
        .init(id: OME.Contributor.nsid.rawValue, displayName: "Contributor", records: [])
      ]
    )

    // The webhook creates the proposal before Jetstream, without inventing render readiness.
    _ = try await store.recordWorkspaceProposal(
      id: Self.pullURI,
      webhook: try #require(webhookProposal.webhook)
    )
    let awaitingInput = try #require(try await store.workspaceProposal(id: Self.pullURI))
    expectNoDifference(awaitingInput.renderInput, nil)
    expectNoDifference(awaitingInput.renderState, .awaitingInput)

    // Preparing the exact proposal, target, round, patch, and renderer identity makes it pending.
    let pendingFirst = try await store.prepareWorkspaceProposalRender(
      id: Self.pullURI,
      input: firstInput
    )
    expectNoDifference(pendingFirst.renderInput, firstInput)
    expectNoDifference(pendingFirst.renderState, .pending)

    // Only a completion for that same input can make the proposal ready.
    let firstCompletion = try await store.completeWorkspaceProposalRender(
      id: Self.pullURI,
      expectedInput: firstInput,
      presentation: firstPresentation
    )
    expectNoDifference(
      firstCompletion,
      .accepted
    )
    let readyFirst = try #require(try await store.workspaceProposal(id: Self.pullURI))
    expectNoDifference(readyFirst.renderState, .ready(firstPresentation))

    // The matching content-addressed Jetstream record enriches the row without invalidating it.
    let firstVersion = try AppView.RecordVersion(
      collection: TangledNSID.pull,
      uri: Self.pullURI,
      cid: firstInput.proposalRevision,
      value: JSONEncoder().encode(record),
      sequence: 400
    )
    _ = try withDependencies {
      $0.defaultDatabase = database
    } operation: {
      try indexer.apply(.put(firstVersion))
    }
    let hydratedFirst = try #require(try await store.workspaceProposal(id: Self.pullURI))
    expectNoDifference(hydratedFirst.renderState, .ready(firstPresentation))

    // Replaying the same input preserves its completed presentation.
    let replayedFirst = try await store.prepareWorkspaceProposalRender(
      id: Self.pullURI,
      input: firstInput
    )
    expectNoDifference(replayedFirst.renderState, .ready(firstPresentation))

    // A later Jetstream revision invalidates readiness before the next render is prepared.
    let secondVersion = try AppView.RecordVersion(
      collection: TangledNSID.pull,
      uri: Self.pullURI,
      cid: secondInput.proposalRevision,
      value: JSONEncoder().encode(record),
      sequence: 401
    )
    _ = try withDependencies {
      $0.defaultDatabase = database
    } operation: {
      try indexer.apply(.put(secondVersion))
    }
    let invalidated = try #require(try await store.workspaceProposal(id: Self.pullURI))
    expectNoDifference(invalidated.renderInput, firstInput)
    expectNoDifference(invalidated.renderState, .pending)

    // Preparing the second identity clears the first completion atomically.
    let pendingSecond = try await store.prepareWorkspaceProposalRender(
      id: Self.pullURI,
      input: secondInput
    )
    expectNoDifference(pendingSecond.renderInput, secondInput)
    expectNoDifference(pendingSecond.renderState, .pending)

    // A late worker cannot publish the first render over the newer input.
    let lateFirstCompletion = try await store.completeWorkspaceProposalRender(
      id: Self.pullURI,
      expectedInput: firstInput,
      presentation: firstPresentation
    )
    expectNoDifference(
      lateFirstCompletion,
      .superseded
    )
    let stillPending = try #require(try await store.workspaceProposal(id: Self.pullURI))
    expectNoDifference(stillPending.renderState, .pending)

    let secondCompletion = try await store.completeWorkspaceProposalRender(
      id: Self.pullURI,
      expectedInput: secondInput,
      presentation: secondPresentation
    )
    expectNoDifference(
      secondCompletion,
      .accepted
    )

    // A replayed webhook still cannot disturb the completed render.
    _ = try await store.recordWorkspaceProposal(
      id: Self.pullURI,
      webhook: try #require(webhookProposal.webhook)
    )
    let readySecond = try #require(try await store.workspaceProposal(id: Self.pullURI))
    expectNoDifference(readySecond.webhook, webhookProposal.webhook)
    expectNoDifference(readySecond.renderInput, secondInput)
    expectNoDifference(readySecond.renderState, .ready(secondPresentation))
  }

  @Test
  func `Jetstream does not project pulls for an unwatched target`() async throws {
    let database = try DatabaseQueue()
    let store = try OpenMusicEventAppViewStore(database: database)
    let indexer = store.appViewRecordIndexer(
      tangledWebhookConfiguration: try TangledWebhookConfiguration(watches: [Self.watch])
    )
    let unrelatedRecord = TangledPullRecord(
      target: TangledPullRecord.Target(
        repo: DID("did:plc:another-repository")!,
        branch: "main"
      ),
      title: "Unrelated proposal",
      rounds: [
        TangledPullRecord.Round(
          patchBlob: ATProto.Blob(
            ref: "bafkreiunrelatedpatch",
            mimeType: "application/gzip",
            size: 99
          ),
          createdAt: "2026-08-24T20:00:00Z"
        )
      ],
      createdAt: "2026-08-24T20:00:00Z"
    )
    let unrelatedURI = ATProto.URI(
      "at://did:plc:another-author/sh.tangled.repo.pull/unrelated"
    )!
    let version = try AppView.RecordVersion(
      collection: TangledNSID.pull,
      uri: unrelatedURI,
      cid: ATProto.CID("bafyreiunrelatedpull"),
      value: JSONEncoder().encode(unrelatedRecord),
      sequence: 300
    )

    // AppView rejects unrelated pulls before either raw or projected persistence.
    let outcome = try withDependencies {
      $0.defaultDatabase = database
    } operation: {
      try indexer.apply(.put(version)).outcome
    }
    expectNoDifference(outcome, .ignored)
    let proposal = try await store.workspaceProposal(id: unrelatedURI)
    let rawSummary = try withDependencies {
      $0.defaultDatabase = database
    } operation: {
      try AppViewIndexDatabase.summary(collection: TangledNSID.pull)
    }
    expectNoDifference(proposal, nil)
    expectNoDifference(rawSummary, AppViewIndexSummary(presentRecords: 0, tombstones: 0))
  }

  @Test
  func `repository DID admits every branch and accepted proposals remain sticky`() async throws {
    let database = try DatabaseQueue()
    let store = try OpenMusicEventAppViewStore(database: database)
    let watchedIndexer = store.appViewRecordIndexer(
      tangledWebhookConfiguration: try TangledWebhookConfiguration(watches: [Self.watch])
    )
    let firstRecord = try Self.pullRecord(
      title: "Review the release branch",
      targetBranch: "refs/heads/release"
    )
    let firstVersion = try AppView.RecordVersion(
      collection: TangledNSID.pull,
      uri: Self.pullURI,
      cid: ATProto.CID("bafyreireleasebranch"),
      value: JSONEncoder().encode(firstRecord),
      sequence: 310
    )

    // Webhook ownership and pull-target identity are deliberately different facts.
    #expect(Self.watch.repositoryOwnerDID != Self.watch.repositoryDID)
    let firstOutcome = try withDependencies {
      $0.defaultDatabase = database
    } operation: {
      try watchedIndexer.apply(.put(firstVersion)).outcome
    }
    expectNoDifference(firstOutcome, .created)

    // Removing the watch does not strand a proposal that this database already accepted.
    let retiredIndexer = store.appViewRecordIndexer(
      tangledWebhookConfiguration: try TangledWebhookConfiguration(watches: [])
    )
    let updatedRecord = try Self.pullRecord(
      title: "Keep observing the retired watch",
      repositoryDID: DID("did:plc:retired-repository"),
      targetBranch: "some-other-branch"
    )
    let updatedVersion = try AppView.RecordVersion(
      collection: TangledNSID.pull,
      uri: Self.pullURI,
      cid: ATProto.CID("bafyreiretiredwatch"),
      value: JSONEncoder().encode(updatedRecord),
      sequence: 311
    )
    let updateOutcome = try withDependencies {
      $0.defaultDatabase = database
    } operation: {
      try retiredIndexer.apply(.put(updatedVersion)).outcome
    }
    expectNoDifference(updateOutcome, .updated)
    let retained = try #require(try await store.workspaceProposal(id: Self.pullURI))
    expectNoDifference(
      retained.record,
      .present(
        cid: updatedVersion.cid,
        sequence: updatedVersion.sequence,
        value: updatedRecord
      )
    )

    let retiredDeletion = try AppView.RecordDeletion(
      collection: TangledNSID.pull,
      uri: Self.pullURI,
      sequence: 312
    )
    let deleteOutcome = try withDependencies {
      $0.defaultDatabase = database
    } operation: {
      try retiredIndexer.apply(.delete(retiredDeletion)).outcome
    }
    expectNoDifference(deleteOutcome, .deleted)
    let deleted = try #require(try await store.workspaceProposal(id: Self.pullURI))
    expectNoDifference(deleted.record, .deleted(sequence: 312))

    // A clean rebuild with that same retired configuration has no sticky row to admit it.
    let cleanDatabase = try DatabaseQueue()
    let cleanStore = try OpenMusicEventAppViewStore(database: cleanDatabase)
    let cleanIndexer = cleanStore.appViewRecordIndexer(
      tangledWebhookConfiguration: nil
    )
    let rebuildOutcome = try withDependencies {
      $0.defaultDatabase = cleanDatabase
    } operation: {
      try cleanIndexer.apply(.put(updatedVersion)).outcome
    }
    expectNoDifference(rebuildOutcome, .ignored)
    let rebuiltProposal = try await cleanStore.workspaceProposal(id: Self.pullURI)
    expectNoDifference(rebuiltProposal, nil)
  }

  @Test
  func `status records materialize the newest accepted lifecycle and fall back on deletion`() async throws {
    let database = try DatabaseQueue()
    let store = try OpenMusicEventAppViewStore(database: database)
    let watchedIndexer = store.appViewRecordIndexer(
      tangledWebhookConfiguration: try TangledWebhookConfiguration(watches: [Self.watch])
    )
    let pull = try Self.pullRecord(title: "Hydrate proposal status")
    let pullVersion = try AppView.RecordVersion(
      collection: TangledNSID.pull,
      uri: Self.pullURI,
      cid: ATProto.CID("bafyreistatuspull"),
      value: JSONEncoder().encode(pull),
      sequence: 500
    )
    _ = try withDependencies {
      $0.defaultDatabase = database
    } operation: {
      try watchedIndexer.apply(.put(pullVersion))
    }
    let statusIndexer = store.appViewRecordIndexer(tangledWebhookConfiguration: nil)

    let unrelatedURI = ATProto.URI(
      "at://did:plc:status-author/sh.tangled.repo.pull.status/3unrelated"
    )!
    let unrelated = try Self.statusVersion(
      uri: unrelatedURI,
      cid: "bafyreistatusunrelated",
      sequence: 501,
      pull: ATProto.URI("at://did:plc:other/sh.tangled.repo.pull/3other")!,
      status: .closed
    )
    let unrelatedOutcome = try withDependencies {
      $0.defaultDatabase = database
    } operation: {
      try statusIndexer.apply(.put(unrelated)).outcome
    }
    expectNoDifference(unrelatedOutcome, .ignored)
    let unrelatedSummary = try withDependencies {
      $0.defaultDatabase = database
    } operation: {
      try AppViewIndexDatabase.summary(collection: TangledNSID.pullStatus)
    }
    expectNoDifference(
      unrelatedSummary,
      AppViewIndexSummary(presentRecords: 0, tombstones: 0)
    )
    let unrelatedDeletion = try AppView.RecordDeletion(
      collection: TangledNSID.pullStatus,
      uri: unrelatedURI,
      sequence: 502
    )
    let unrelatedDeleteOutcome = try withDependencies {
      $0.defaultDatabase = database
    } operation: {
      try statusIndexer.apply(.delete(unrelatedDeletion)).outcome
    }
    expectNoDifference(unrelatedDeleteOutcome, .ignored)
    let rejectedDeleteSummary = try withDependencies {
      $0.defaultDatabase = database
    } operation: {
      try AppViewIndexDatabase.summary(collection: TangledNSID.pullStatus)
    }
    expectNoDifference(
      rejectedDeleteSummary,
      AppViewIndexSummary(presentRecords: 0, tombstones: 0)
    )

    let firstURI = ATProto.URI(
      "at://did:plc:status-a/sh.tangled.repo.pull.status/3same"
    )!
    let first = try Self.statusVersion(
      uri: firstURI,
      cid: "bafyreistatusopen",
      sequence: 503,
      pull: Self.pullURI,
      status: .open
    )
    _ = try withDependencies {
      $0.defaultDatabase = database
    } operation: {
      try statusIndexer.apply(.put(first))
    }

    // Equal record keys use the full URI as a stable cross-repository tie-breaker.
    let selectedURI = ATProto.URI(
      "at://did:plc:status-z/sh.tangled.repo.pull.status/3same"
    )!
    let selected = try Self.statusVersion(
      uri: selectedURI,
      cid: "bafyreistatusmerged",
      sequence: 504,
      pull: Self.pullURI,
      status: .merged
    )
    _ = try withDependencies {
      $0.defaultDatabase = database
    } operation: {
      try statusIndexer.apply(.put(selected))
    }
    let merged = try #require(try await store.workspaceProposal(id: Self.pullURI))
    expectNoDifference(
      merged.status,
      TangledWorkspaceProposal.StatusObservation(
        uri: selected.uri,
        cid: selected.cid,
        sequence: selected.sequence,
        status: .merged,
        createdAt: "2026-08-24T20:00:00Z"
      )
    )
    expectNoDifference(merged.lifecycle, .merged)

    let updatedSelected = try Self.statusVersion(
      uri: selectedURI,
      cid: "bafyreistatusclosedupdate",
      sequence: 505,
      pull: Self.pullURI,
      status: .closed
    )
    let statusUpdateOutcome = try withDependencies {
      $0.defaultDatabase = database
    } operation: {
      try statusIndexer.apply(.put(updatedSelected)).outcome
    }
    expectNoDifference(statusUpdateOutcome, .updated)
    let updated = try #require(try await store.workspaceProposal(id: Self.pullURI))
    expectNoDifference(updated.status?.status, .closed)
    expectNoDifference(updated.lifecycle, .closed)

    let unknownURI = ATProto.URI(
      "at://did:plc:status-author/sh.tangled.repo.pull.status/3zzzz"
    )!
    let unknownStatus: Open<TangledPullStatus> = .unknown(
      .string("sh.tangled.repo.pull.status.reviewing")
    )
    let unknown = try Self.statusVersion(
      uri: unknownURI,
      cid: "bafyreistatusunknown",
      sequence: 506,
      pull: Self.pullURI,
      status: unknownStatus
    )
    _ = try withDependencies {
      $0.defaultDatabase = database
    } operation: {
      try statusIndexer.apply(.put(unknown))
    }
    let preserved = try #require(try await store.workspaceProposal(id: Self.pullURI))
    expectNoDifference(preserved.status?.status, unknownStatus)
    expectNoDifference(preserved.lifecycle, unknownStatus)

    let unknownDeletion = try AppView.RecordDeletion(
      collection: TangledNSID.pullStatus,
      uri: unknownURI,
      sequence: 507
    )
    _ = try withDependencies {
      $0.defaultDatabase = database
    } operation: {
      try statusIndexer.apply(.delete(unknownDeletion))
    }
    let fellBack = try #require(try await store.workspaceProposal(id: Self.pullURI))
    expectNoDifference(fellBack.status?.uri, selectedURI)
    expectNoDifference(fellBack.lifecycle, .closed)

    let selectedDeletion = try AppView.RecordDeletion(
      collection: TangledNSID.pullStatus,
      uri: selectedURI,
      sequence: 508
    )
    _ = try withDependencies {
      $0.defaultDatabase = database
    } operation: {
      try statusIndexer.apply(.delete(selectedDeletion))
    }
    let tiedFallback = try #require(try await store.workspaceProposal(id: Self.pullURI))
    expectNoDifference(tiedFallback.status?.uri, firstURI)
    expectNoDifference(tiedFallback.lifecycle, .open)

    let firstDeletion = try AppView.RecordDeletion(
      collection: TangledNSID.pullStatus,
      uri: firstURI,
      sequence: 509
    )
    _ = try withDependencies {
      $0.defaultDatabase = database
    } operation: {
      try statusIndexer.apply(.delete(firstDeletion))
    }
    let cleared = try #require(try await store.workspaceProposal(id: Self.pullURI))
    expectNoDifference(cleared.status, nil)
    expectNoDifference(cleared.lifecycle, .open)
  }

  @Test
  func `the unified hydration migration preserves existing webhook proposals`() throws {
    let database = try DatabaseQueue()
    let proposal = try Self.webhookProposal()
    let webhook = try #require(proposal.webhook)
    let tableName = TangledWorkspaceProposalRow.tableName

    // This is the exact proposal schema already deployed before Jetstream hydration existed.
    var legacyMigrator = DatabaseMigrator()
    legacyMigrator.registerMigration("Create Workspace proposals") { database in
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
        CREATE UNIQUE INDEX "workspaceProposals_discoveryDeliveryID"
        ON \(quote: tableName) ("discoveryDeliveryID")
        """
      )
      .execute(database)
    }
    try legacyMigrator.migrate(database)
    try database.write { database in
      try #sql(
        """
        INSERT INTO \(quote: tableName) (
          "uri",
          "discoveryDeliveryID",
          "watchID",
          "pullNumber",
          "state",
          "webhook",
          "observedAt"
        ) VALUES (
          \(bind: proposal.id.description),
          \(bind: webhook.deliveryID.rawValue),
          \(bind: webhook.watchID.rawValue),
          \(bind: webhook.value.pullNumber),
          \(bind: webhook.value.state),
          \(bind: JSONEncoder().encode(webhook.value)),
          \(bind: webhook.observedAt)
        )
        """
      )
      .execute(database)
    }

    // The new migration changes storage shape without changing the observed proposal.
    var migrator = DatabaseMigrator()
    TangledWorkspaceProposalSchema.registerMigration(into: &migrator)
    try migrator.migrate(database)
    let migrated = try database.read { database in
      try TangledWorkspaceProposalRow.find(proposal.id.description)
        .fetchOne(database)
        .map { try $0.proposal() }
    }
    expectNoDifference(migrated, proposal)

    #expect(throws: DatabaseError.self) {
      try database.write { database in
        try #sql(
          """
          UPDATE \(quote: tableName)
          SET "statusURI" = \(bind: "at://did:plc:status/sh.tangled.repo.pull.status/partial")
          WHERE "uri" = \(bind: proposal.id.description)
          """
        )
        .execute(database)
      }
    }
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
  fileprivate static let repositoryDID = "did:plc:workspace-repository"
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
    repositoryDID: DID(repositoryDID)!,
    ref: "refs/heads/main",
    canonicalSource: CanonicalTangledSource(
      organizerID: OME.Organizer.ID("did:plc:wickedwoods")!,
      repositoryRecordKey: .init(rawValue: "wicked-woods-source")
    )
  )

  fileprivate static func webhookProposal() throws -> TangledWorkspaceProposal {
    TangledWorkspaceProposal(
      id: pullURI,
      webhook: TangledWorkspaceProposal.WebhookObservation(
        deliveryID: .init(rawValue: deliveryID),
        watchID: watch.id,
        value: TangledPullCreated.Webhook(
          canonicalSource: watch.canonicalSource.reference,
          repository: TangledPullCreated.Webhook.Repository(
            host: repository.host,
            port: repository.port,
            owner: repository.owner,
            ownerDID: try #require(DID(repositoryOwnerDID)),
            name: repository.repository
          ),
          pullNumber: 4,
          authorDID: try #require(DID(pullAuthorDID)),
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
          pageURL: pageURL,
          patchURL: patchURL,
          createdAt: "2026-08-24T20:00:00Z"
        ),
        observedAt: receivedAt
      ),
      record: nil
    )
  }

  fileprivate static func pullRecord(
    title: String,
    repositoryDID: DID? = DID(repositoryDID),
    targetBranch: String = "main"
  ) throws -> TangledPullRecord {
    TangledPullRecord(
      target: TangledPullRecord.Target(
        repo: try #require(repositoryDID),
        branch: targetBranch
      ),
      title: title,
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
        repo: DID(pullAuthorDID)!
      ),
      createdAt: "2026-08-24T20:00:00Z"
    )
  }

  fileprivate static func renderInput(
    proposalRevision: ATProto.CID,
    targetRevision: String,
    roundNumber: Int,
    patchDigest: String
  ) -> TangledWorkspaceProposal.RenderInput {
    TangledWorkspaceProposal.RenderInput(
      proposalRevision: proposalRevision,
      targetRevision: targetRevision,
      roundNumber: roundNumber,
      patchDigest: patchDigest,
      rendererVersion: WorkspaceProposalRenderer.currentVersion
    )
  }

  fileprivate static func statusVersion(
    uri: ATProto.URI,
    cid: String,
    sequence: Int64,
    pull: ATProto.URI,
    status: Open<TangledPullStatus>
  ) throws -> AppView.RecordVersion<Data> {
    try AppView.RecordVersion(
      collection: TangledNSID.pullStatus,
      uri: uri,
      cid: ATProto.CID(cid),
      value: JSONEncoder().encode(
        TangledPullStatusRecord(
          pull: pull,
          status: status,
          createdAt: "2026-08-24T20:00:00Z"
        )
      ),
      sequence: sequence
    )
  }

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
