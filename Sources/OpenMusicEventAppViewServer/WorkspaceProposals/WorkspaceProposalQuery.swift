import ATProto
import Foundation
import OpenMusicEventLexicon
import SQLiteData
import TangledLexicon

extension OpenMusicEventAppViewStore {
  func workspaceProposalPage(
    source: ATProto.URI,
    targetBranch: String,
    includeRetained: Bool,
    cursor: String?,
    limit: Int,
    tangledWebhookConfiguration: TangledWebhookConfiguration?
  ) async throws -> OME.WorkspaceProposal.Page {
    let cursor = try cursor.map(WorkspaceProposalCursor.init(rawValue:))
    var proposals = try await database.read { database in
      try TangledWorkspaceProposalRow.all.fetchAll(database)
        .map { try $0.proposal() }
        .compactMap {
          try $0.listItem(
            tangledWebhookConfiguration: tangledWebhookConfiguration
          )
        }
        .filter {
          $0.canonicalSource == source
            && $0.targetBranch == targetBranch
            && (includeRetained || $0.isOpenWorkspaceProposal)
        }
    }
    proposals.sort(by: WorkspaceProposalCursor.sortsBefore)

    if let cursor {
      proposals = proposals.filter { cursor.contains($0) }
    }
    let hasNextPage = proposals.count > limit
    let page = Array(proposals.prefix(limit))
    let nextCursor: String?
    if hasNextPage, let last = page.last {
      nextCursor = try WorkspaceProposalCursor(item: last).rawValue
    } else {
      nextCursor = nil
    }
    return OME.WorkspaceProposal.Page(
      proposals: page,
      cursor: nextCursor
    )
  }

  func workspaceProposalDetail(
    id: ATProto.URI,
    tangledWebhookConfiguration: TangledWebhookConfiguration?
  ) async throws -> OME.WorkspaceProposal.Detail? {
    try await workspaceProposal(id: id)?.detail(
      tangledWebhookConfiguration: tangledWebhookConfiguration
    )
  }
}

private struct WorkspaceProposalCursor: Codable, Equatable, Sendable {
  let updatedAt: Date
  let uri: String

  init(item: OME.WorkspaceProposal.ListItem) {
    self.updatedAt = item.updatedAt
    self.uri = item.uri.description
  }

  init(rawValue: String) throws {
    var base64 = rawValue
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    base64.append(String(repeating: "=", count: (4 - base64.count % 4) % 4))
    guard let data = Data(base64Encoded: base64) else {
      throw OpenMusicEventAppViewStoreError.invalidCursor(rawValue)
    }
    do {
      self = try JSONDecoder().decode(Self.self, from: data)
    } catch {
      throw OpenMusicEventAppViewStoreError.invalidCursor(rawValue)
    }
  }

  var rawValue: String {
    get throws {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      return try encoder.encode(self).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    }
  }

  func contains(_ item: OME.WorkspaceProposal.ListItem) -> Bool {
    item.updatedAt < updatedAt
      || (item.updatedAt == updatedAt && item.uri.description < uri)
  }

  static func sortsBefore(
    _ lhs: OME.WorkspaceProposal.ListItem,
    _ rhs: OME.WorkspaceProposal.ListItem
  ) -> Bool {
    lhs.updatedAt > rhs.updatedAt
      || (lhs.updatedAt == rhs.updatedAt && lhs.uri.description > rhs.uri.description)
  }
}

private extension OME.WorkspaceProposal.ListItem {
  var isOpenWorkspaceProposal: Bool {
    status != .closed && status != .merged
  }
}

private extension TangledWorkspaceProposal {
  func listItem(
    tangledWebhookConfiguration: TangledWebhookConfiguration?
  ) throws -> OME.WorkspaceProposal.ListItem? {
    let detail = try detail(
      tangledWebhookConfiguration: tangledWebhookConfiguration
    )
    guard let canonicalSource = detail.canonicalSource,
      let title = detail.title,
      let targetBranch = detail.targetBranch,
      let createdAt = detail.createdAt,
      let updatedAt = detail.updatedAt
    else {
      return nil
    }
    return OME.WorkspaceProposal.ListItem(
      uri: detail.uri,
      canonicalSource: canonicalSource,
      title: title,
      authorDID: detail.authorDID,
      status: detail.status,
      targetBranch: targetBranch,
      createdAt: createdAt,
      updatedAt: updatedAt,
      pullNumber: detail.pullNumber,
      pageURL: detail.pageURL,
      renderStatus: detail.renderStatus
    )
  }

  func detail(
    tangledWebhookConfiguration: TangledWebhookConfiguration?
  ) throws -> OME.WorkspaceProposal.Detail {
    guard case let .did(authorDID) = id.authority else {
      throw TangledWorkspaceProposalPersistenceError.corruptHydration(id.description)
    }
    let pullRecord: TangledPullRecord?
    let recordCID: ATProto.CID?
    let recordAvailability: OME.WorkspaceProposal.RecordAvailability
    switch record {
    case nil:
      pullRecord = nil
      recordCID = nil
      recordAvailability = .awaitingRecord
    case let .present(cid, _, value):
      pullRecord = value
      recordCID = cid
      recordAvailability = .present
    case .deleted:
      pullRecord = nil
      recordCID = nil
      recordAvailability = .deleted
    }

    let title = pullRecord?.title ?? webhook?.value.title
    let targetBranch = pullRecord?.target.branch ?? webhook?.value.targetBranch
    let createdAt = try (pullRecord?.createdAt ?? webhook?.value.createdAt)
      .map(workspaceProposalDate)

    let webhookSourceRepositoryDID: DID?
    if let value = webhook?.value.source?.repositoryDID {
      guard let did = DID(value) else {
        throw TangledWorkspaceProposalPersistenceError.corruptHydration(id.description)
      }
      webhookSourceRepositoryDID = did
    } else {
      webhookSourceRepositoryDID = nil
    }
    let source: OME.WorkspaceProposal.Source?
    if let sourceBranch = pullRecord?.source?.branch ?? webhook?.value.source?.branch {
      source = OME.WorkspaceProposal.Source(
        repositoryDID: pullRecord?.source?.repo ?? webhookSourceRepositoryDID,
        branch: sourceBranch,
        revision: webhook?.value.source?.revision
      )
    } else {
      source = nil
    }

    let renderStatus: OME.WorkspaceProposal.RenderStatus
    let presentation: OME.WorkspaceProposal.Presentation?
    switch renderState {
    case .awaitingInput:
      renderStatus = .awaitingInput
      presentation = nil
    case .pending:
      renderStatus = .pending
      presentation = nil
    case let .ready(value):
      renderStatus = .ready
      presentation = value
    }

    let targetRepositoryDID = pullRecord?.target.repo
      ?? webhook.flatMap { observation in
        tangledWebhookConfiguration?.watchesByID[observation.watchID]?.repositoryDID
      }
    let canonicalSource = try resolvedCanonicalSource(
      targetRepositoryDID: targetRepositoryDID,
      tangledWebhookConfiguration: tangledWebhookConfiguration
    )
    return OME.WorkspaceProposal.Detail(
      uri: id,
      canonicalSource: canonicalSource,
      title: title,
      body: pullRecord?.body ?? webhook?.value.body,
      authorDID: authorDID,
      status: OME.WorkspaceProposal.Status(rawValue: lifecycle.rawValue),
      targetRepositoryDID: targetRepositoryDID,
      targetBranch: targetBranch,
      source: source,
      createdAt: createdAt,
      updatedAt: try status.map { try workspaceProposalDate($0.createdAt) } ?? createdAt,
      pullNumber: webhook?.value.pullNumber,
      roundNumber: webhook?.value.roundNumber ?? pullRecord?.rounds.indices.last,
      pageURL: webhook?.value.pageURL,
      patchURL: webhook?.value.patchURL,
      recordCID: recordCID,
      recordAvailability: recordAvailability,
      statusRecordURI: status?.uri,
      renderStatus: renderStatus,
      presentation: presentation
    )
  }

  func resolvedCanonicalSource(
    targetRepositoryDID: DID?,
    tangledWebhookConfiguration: TangledWebhookConfiguration?
  ) throws -> ATProto.URI? {
    if let value = webhook?.value.canonicalSource {
      guard let source = ATProto.URI(value) else {
        throw TangledWorkspaceProposalPersistenceError.invalidURI(value)
      }
      return source
    }
    guard let targetRepositoryDID,
      let watch = tangledWebhookConfiguration?.watches.first(where: {
        $0.repositoryDID == targetRepositoryDID
      })
    else {
      return nil
    }
    guard let source = ATProto.URI(watch.canonicalSource.reference) else {
      throw TangledWorkspaceProposalPersistenceError.invalidURI(
        watch.canonicalSource.reference
      )
    }
    return source
  }
}

private func workspaceProposalDate(_ value: String) throws -> Date {
  let fractional = ISO8601DateFormatter()
  fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  if let date = fractional.date(from: value) {
    return date
  }

  let wholeSeconds = ISO8601DateFormatter()
  wholeSeconds.formatOptions = [.withInternetDateTime]
  guard let date = wholeSeconds.date(from: value) else {
    throw TangledWorkspaceProposalPersistenceError.invalidTimestamp(value)
  }
  return date
}
