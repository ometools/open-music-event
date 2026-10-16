import ATProto
import CustomDump
import Foundation
import OpenMusicEventLexicon
import Testing

@Suite("OME Workspace proposal XRPC contract")
struct WorkspaceProposalLexiconTests {
  @Test
  func `proposal queries return the shared list and detail contracts`() throws {
    let definitions = try workspaceLexicon(named: "defs")
    let getProposal = try workspaceLexicon(named: "getProposal")
    let getProposals = try workspaceLexicon(named: "getProposals")

    #expect(definitions["id"] as? String == "app.openmusicevent.workspace.defs")
    #expect(getProposal["id"] as? String == OME.WorkspaceProposal.GetProposal.nsid.description)
    #expect(getProposals["id"] as? String == OME.WorkspaceProposal.GetProposals.nsid.description)

    let definitionsBody = try #require(definitions["defs"] as? [String: Any])
    let detail = try #require(definitionsBody["detail"] as? [String: Any])
    let detailProperties = try #require(detail["properties"] as? [String: Any])
    let presentation = try #require(detailProperties["presentation"] as? [String: Any])
    #expect(presentation["ref"] as? String == "#presentation")

    let transition = try #require(
      definitionsBody["presentationTransition"] as? [String: Any]
    )
    let transitionProperties = try #require(transition["properties"] as? [String: Any])
    let before = try #require(transitionProperties["before"] as? [String: Any])
    let after = try #require(transitionProperties["after"] as? [String: Any])
    #expect(before["type"] as? String == "unknown")
    #expect(after["type"] as? String == "unknown")

    let getProposalMain = try mainDefinition(in: getProposal)
    let getProposalParameters = try #require(
      getProposalMain["parameters"] as? [String: Any]
    )
    #expect(getProposalParameters["required"] as? [String] == ["uri"])
    #expect(
      try outputReference(in: getProposalMain)
        == "app.openmusicevent.workspace.defs#detail"
    )

    let getProposalsMain = try mainDefinition(in: getProposals)
    let getProposalsParameters = try #require(
      getProposalsMain["parameters"] as? [String: Any]
    )
    #expect(
      getProposalsParameters["required"] as? [String]
        == ["source", "targetBranch"]
    )
    #expect(
      try outputReference(in: getProposalsMain)
        == "app.openmusicevent.workspace.defs#page"
    )
  }

  @Test
  func `proposal detail encodes presentation as structured JSON`() throws {
    let uri = try #require(
      ATProto.URI("at://did:plc:author/sh.tangled.repo.pull/3proposal")
    )
    let canonicalSource = try #require(
      ATProto.URI("at://did:plc:organizer/sh.tangled.repo/workspace")
    )
    let detail = OME.WorkspaceProposal.Detail(
      uri: uri,
      canonicalSource: canonicalSource,
      title: "Add artist detail previews",
      body: "Carries the old and new artist values.",
      authorDID: try #require(DID("did:plc:author")),
      status: .open,
      targetRepositoryDID: try #require(DID("did:plc:repository")),
      targetBranch: "main",
      source: OME.WorkspaceProposal.Source(
        repositoryDID: try #require(DID("did:plc:author")),
        branch: "artist-preview",
        revision: "2222222222222222222222222222222222222222"
      ),
      createdAt: try #require(
        ISO8601DateFormatter().date(from: "2026-08-24T20:00:00Z")
      ),
      updatedAt: try #require(
        ISO8601DateFormatter().date(from: "2026-08-24T20:01:00Z")
      ),
      pullNumber: 4,
      roundNumber: 0,
      pageURL: URL(string: "https://tangled.org/workspace/pulls/4"),
      patchURL: URL(string: "https://tangled.org/workspace/pulls/4/round/0.patch"),
      recordCID: ATProto.CID("bafyreiproposal"),
      recordAvailability: .present,
      statusRecordURI: ATProto.URI(
        "at://did:plc:author/sh.tangled.repo.pull.status/3status"
      ),
      renderStatus: .ready,
      presentation: .empty
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(detail)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(OME.WorkspaceProposal.Detail.self, from: data)
    expectNoDifference(decoded, detail)

    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let presentation = try #require(json["presentation"] as? [String: Any])
    #expect(presentation["formatVersion"] as? Int == 1)
    #expect((presentation["groups"] as? [Any])?.isEmpty == true)
    #expect(json["recordAvailability"] as? String == OME.WorkspaceProposal.RecordAvailability.present.rawValue)
    #expect(json["renderStatus"] as? String == OME.WorkspaceProposal.RenderStatus.ready.rawValue)
    #expect(json["status"] as? String == OME.WorkspaceProposal.Status.open.rawValue)
    #expect(json["createdAt"] as? String == "2026-08-24T20:00:00Z")
  }

  @Test
  func `proposal list request defaults to open proposals and one hundred results`() throws {
    let parameters = try JSONDecoder().decode(
      OME.WorkspaceProposal.GetProposals.Parameters.self,
      from: Data(
        #"{"source":"at://did:plc:organizer/sh.tangled.repo/workspace","targetBranch":"main"}"#.utf8
      )
    )

    expectNoDifference(
      parameters,
      OME.WorkspaceProposal.GetProposals.Parameters(
        source: try #require(
          ATProto.URI("at://did:plc:organizer/sh.tangled.repo/workspace")
        ),
        targetBranch: "main"
      )
    )
    #expect(parameters.includeRetained == false)
    #expect(parameters.limit == 100)
  }
}

private func workspaceLexicon(named name: String) throws -> [String: Any] {
  let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let url = packageRoot
    .appendingPathComponent("Lexicons")
    .appendingPathComponent("app")
    .appendingPathComponent("openmusicevent")
    .appendingPathComponent("workspace")
    .appendingPathComponent("\(name).json")
  return try #require(
    JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
  )
}

private func mainDefinition(in lexicon: [String: Any]) throws -> [String: Any] {
  let definitions = try #require(lexicon["defs"] as? [String: Any])
  return try #require(definitions["main"] as? [String: Any])
}

private func outputReference(in definition: [String: Any]) throws -> String {
  let output = try #require(definition["output"] as? [String: Any])
  let schema = try #require(output["schema"] as? [String: Any])
  return try #require(schema["ref"] as? String)
}
