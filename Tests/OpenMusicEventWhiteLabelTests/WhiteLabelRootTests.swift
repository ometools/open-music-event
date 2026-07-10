import ATProto
import ComposableArchitecture2
import CustomDump
import Dependencies
import Foundation
import HTTPClient
import HTTPTypes
import IssueReporting
import OpenMusicEventAuthentication
import OpenMusicEventLexicon
import OpenMusicEventSource
import SQLiteData
import Testing
import XRPCClient

@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer
@testable import OpenMusicEventSourceEditing
@testable import OpenMusicEventWhiteLabel
@testable import OpenMusicEventWhiteLabelApp

private typealias OMERecord = OpenMusicEventLexicon.OpenMusicEvent

@MainActor
struct WhiteLabelRootTests {
  @Test
  func unknownOrganizerShowsFirstLaunchError() async throws {
    try await withNonExhaustiveTest {
      let database = try makePreparedDatabase()
      let organizerID = organizerID("unknown")
      let store = makeStore(
        configuration: .init(
          brand: .init(displayName: "Unknown Festival"),
          organizerID: organizerID
        ),
        database: database
      )

      await load(store, suppressingReportedIssues: true)

      #expect(store.state.isLoading == false)
      #expect(store.state.organizationRoot?.state.organizerID == nil)
      #expect(store.state.errorMessage == "Unable to load event source.")
    }
  }

  @Test
  func developmentSourceOverrideBypassesRegistry() async throws {
    try await withNonExhaustiveTest {
      let database = try makePreparedDatabase()
      let organizerID = WickedWoodsWhiteLabel.temporaryDevelopmentOrganizerID
      let descriptor = WhiteLabelSourceDescriptor(reference: .source("/tmp/wicked-woods-ome"))
      let recorder = SourceImportRecorder()

      let store = makeStore(
        configuration: WickedWoodsWhiteLabel.configuration(),
        database: database
      ) {
        $0.whiteLabelDevelopmentSourceOverride = WickedWoodsWhiteLabel.developmentSourceOverride(
          reference: .source("/tmp/wicked-woods-ome")
        )
        $0.whiteLabelOrganizerIdentityResolver = WhiteLabelOrganizerIdentityResolverClient { _ in
          throw RegistryShouldNotBeCalled()
        }
        $0.whiteLabelSourceRegistry = WhiteLabelSourceRegistryClient { _ in
          throw RegistryShouldNotBeCalled()
        }
        $0.whiteLabelSourceImport = WhiteLabelSourceImportClient {
          importedOrganizerID, importedDescriptor in
          await recorder.record(organizerID: importedOrganizerID, descriptor: importedDescriptor)
          let eventID = eventID(organizerID: importedOrganizerID, eventID: "2025")
          try await insertEvent(
            eventID,
            name: "Wicked Woods 2025",
            startDate: LocalDate("2025-08-29"),
            endDate: LocalDate("2025-08-31"),
            into: database
          )
          return [eventID]
        }
      }

      await load(store)

      #expect(await recorder.records == [.init(organizerID: organizerID, descriptor: descriptor)])
      #expect(store.state.organizerID == organizerID)
      #expect(store.state.organizationRoot?.state.organizerID == organizerID)
      #expect(store.state.errorMessage == nil)
    }
  }

  @Test
  func canonicalSourceRegistryFetchesOrganizerSourceRecord() async throws {
    let organizerID = organizerID("wickedwoods")
    let handle = Atmosphere.Account.Handle("wickedwoods.ca")
    let recorder = HTTPRequestRecorder()

    let descriptor = try await withDependencies {
      $0[Atmosphere.Account.Client.self] = Atmosphere.Account.Client(
        resolveHandle: { _ in
          Issue.record("Did not expect handle resolution.")
          return (
            Atmosphere.Account(id: .init(organizerID), handle: handle),
            try didDocument(
              did: organizerID,
              handle: handle,
              pdsHost: "wickedwoods.pds.example"
            )
          )
        },
        resolveDID: { did in
          #expect(did == organizerID)
          return (
            Atmosphere.Account(id: .init(organizerID), handle: handle),
            try didDocument(
              did: organizerID,
              handle: handle,
              pdsHost: "wickedwoods.pds.example"
            )
          )
        }
      )
      $0[XRPC.Client.self] = .liveValue
      $0.httpClient = HTTPClient { request, body in
        await recorder.record(request, body)
        return Data(
          """
          {
            "uri": "at://did:plc:wickedwoods/app.openmusicevent.source/canonical",
            "value": {
              "$type": "app.openmusicevent.source",
              "kind": "tangled",
              "reference": "https://tangled.org/did:plc:wickedwoods/wicked-woods-ome",
              "ref": "main",
              "createdAt": "2026-07-10T00:00:00Z"
            }
          }
          """
          .utf8
        )
      }
    } operation: {
      try await WhiteLabelSourceRegistryClient.canonicalSourceRecord.source(organizerID)
    }

    expectNoDifference(
      descriptor,
      WhiteLabelSourceDescriptor(
        reference: .source("https://tangled.org/did:plc:wickedwoods/wicked-woods-ome"),
        version: "main"
      )
    )

    let requests = await recorder.requests
    #expect(requests.count == 1)
    #expect(
      requests.first?.url?.absoluteString
        == "https://wickedwoods.pds.example/xrpc/com.atproto.repo.getRecord?repo=did:plc:wickedwoods&collection=app.openmusicevent.source&rkey=canonical"
    )
    #expect(requests.first?.body == nil)
  }

  @Test
  func startupRestoresStoredAuthenticationBeforeImportingSource() async throws {
    try await withNonExhaustiveTest {
      let database = try makePreparedDatabase()
      let organizerID = WickedWoodsWhiteLabel.temporaryDevelopmentOrganizerID
      let descriptor = WhiteLabelSourceDescriptor(reference: .source("/tmp/wicked-woods-ome"))
      let recorder = StartupOrderRecorder()

      let store = makeStore(
        configuration: WickedWoodsWhiteLabel.configuration(),
        database: database
      ) {
        $0.openMusicEventStoredAuthentication = OpenMusicEventStoredAuthenticationClient {
          await recorder.record(.storedAuthentication)
        }
        $0.whiteLabelDevelopmentSourceOverride = WickedWoodsWhiteLabel.developmentSourceOverride(
          reference: .source("/tmp/wicked-woods-ome")
        )
        $0.whiteLabelSourceImport = WhiteLabelSourceImportClient {
          importedOrganizerID, importedDescriptor in
          await recorder.record(.sourceImport)
          #expect(importedOrganizerID == organizerID)
          #expect(importedDescriptor == descriptor)
          return []
        }
      }

      await load(store)

      #expect(await recorder.events == [.storedAuthentication, .sourceImport])
    }
  }

  @Test
  func handleLookupResolvesBeforeRegistryLookup() async throws {
    try await withNonExhaustiveTest {
      let database = try makePreparedDatabase()
      let organizerID = organizerID("wickedwoods")
      let descriptor = WhiteLabelSourceDescriptor(
        reference: .archiveURL(URL(string: "https://example.com/wicked-woods.tar.gz")!)
      )
      let recorder = SourceImportRecorder()

      let store = makeStore(
        configuration: WickedWoodsWhiteLabel.configuration(),
        database: database
      ) {
        $0.whiteLabelOrganizerIdentityResolver = WhiteLabelOrganizerIdentityResolverClient {
          handle in
          #expect(handle == WickedWoodsWhiteLabel.handle)
          return organizerID
        }
        $0.whiteLabelSourceRegistry = .codeBacked([organizerID: descriptor])
        $0.whiteLabelSourceImport = WhiteLabelSourceImportClient {
          importedOrganizerID, importedDescriptor in
          await recorder.record(organizerID: importedOrganizerID, descriptor: importedDescriptor)
          return []
        }
      }

      await load(store)

      #expect(await recorder.records == [.init(organizerID: organizerID, descriptor: descriptor)])
      #expect(store.state.organizerID == organizerID)
      #expect(store.state.organizationRoot?.state.organizerID == organizerID)
      #expect(store.state.errorMessage == nil)
    }
  }

  @Test
  func singleImportedSourcePresentsTeamWorkspaceDetailDirectly() async throws {
    try await withNonExhaustiveTest {
      let database = try makePreparedDatabase()
      let organizerID = organizerID("wickedwoods")
      let selectedEventID = eventID(organizerID: organizerID, eventID: "2025")
      let descriptor = WhiteLabelSourceDescriptor(
        reference: .source("https://tangled.org/did:plc:cqqtuv75m7e5s4uj6nw4czyu/wicked-woods-ome")
      )
      let source = sourceProvenance("wicked-woods-ome")
      let sourceBaselineID = SourceBaselineRecord.ID(source: source)

      let store = makeStore(
        configuration: WickedWoodsWhiteLabel.configuration(organizerID: organizerID),
        database: database
      ) {
        $0.whiteLabelSourceRegistry = .codeBacked([organizerID: descriptor])
        $0.whiteLabelSourceImport = WhiteLabelSourceImportClient {
          importedOrganizerID, _ in
          #expect(importedOrganizerID == organizerID)
          try await insertSourceBackedEvent(
            selectedEventID,
            source: source,
            into: database
          )
          return [selectedEventID]
        }
      }

      await load(store)

      #expect(store.state.teamWorkspaceDetail?.state.sourceBaselineID == sourceBaselineID)
      #expect(store.state.organizationRoot == nil)
      #expect(store.state.errorMessage == nil)
    }
  }

  @Test
  func singleTangledSourceConfiguresAccountForWorkspaceManagementScopes() async throws {
    try await withNonExhaustiveTest {
      let database = try makePreparedDatabase()
      let organizerID = organizerID("wickedwoods")
      let selectedEventID = eventID(organizerID: organizerID, eventID: "2025")
      let descriptor = WhiteLabelSourceDescriptor(
        reference: .source("https://tangled.org/did:plc:cqqtuv75m7e5s4uj6nw4czyu/wicked-woods-ome")
      )
      let source = sourceProvenance("wicked-woods-ome")
      let sourceBaselineID = SourceBaselineRecord.ID(source: source)

      let store = makeStore(
        configuration: WickedWoodsWhiteLabel.configuration(organizerID: organizerID),
        database: database
      ) {
        $0.whiteLabelSourceRegistry = .codeBacked([organizerID: descriptor])
        $0.whiteLabelSourceImport = WhiteLabelSourceImportClient { importedOrganizerID, _ in
          #expect(importedOrganizerID == organizerID)
          try await insertSourceBackedEvent(
            selectedEventID,
            source: source,
            into: database
          )
          return [selectedEventID]
        }
      }

      await load(store)

      let requiredPermissions = Set(
        OpenMusicEventOAuth.tangledWorkspaceManagementAuthRequirement.permissions.map(\.rawValue)
      )
      let accountPermissions = Set(
        store.state.account.state.authRequirement.permissions.map(\.rawValue)
      )
      let provenanceSourceBaselineIDs = try await database.read { db in
        try EventSourceProvenanceRecord
          .fetchAll(db)
          .compactMap(\.sourceBaselineID)
      }

      #expect(store.state.errorMessage == nil)
      #expect(provenanceSourceBaselineIDs == [sourceBaselineID])
      #expect(store.state.authoringSubject == .sourceBaseline(sourceBaselineID))
      #expect(accountPermissions == requiredPermissions)
    }
  }

  @Test
  func enterAuthoringButtonAuthorizesSingleSourceRoot() async throws {
    try await withNonExhaustiveTest {
      let database = try makePreparedDatabase()
      let organizerID = organizerID("wickedwoods")
      let selectedEventID = eventID(organizerID: organizerID, eventID: "2025")
      let descriptor = WhiteLabelSourceDescriptor(
        reference: .source("https://tangled.org/did:plc:cqqtuv75m7e5s4uj6nw4czyu/wicked-woods-ome")
      )
      let source = sourceProvenance("wicked-woods-ome")
      let sourceBaselineID = SourceBaselineRecord.ID(source: source)
      let recorder = AuthoringRequestRecorder()

      let store = makeStore(
        configuration: WickedWoodsWhiteLabel.configuration(organizerID: organizerID),
        database: database
      ) {
        $0.authoringPolicy = AuthoringPolicyClient(
          authenticate: { _ in OpenMusicEventOAuth.tangledWorkspaceManagementAuthRequirement },
          authorize: { request in
            await recorder.record(request)
            return .all
          },
          mode: { _ in .attendee }
        )
        $0.whiteLabelSourceRegistry = .codeBacked([organizerID: descriptor])
        $0.whiteLabelSourceImport = WhiteLabelSourceImportClient { importedOrganizerID, _ in
          #expect(importedOrganizerID == organizerID)
          try await insertSourceBackedEvent(
            selectedEventID,
            source: source,
            into: database
          )
          return [selectedEventID]
        }
      }

      await load(store)

      #expect(store.state.authoringSubject == .sourceBaseline(sourceBaselineID))
      #expect(store.state.authoringMode == .attendee)
      #expect(!store.state.showsAuthoringControls)

      await store.send(.enterAuthoringButtonTapped) {
        $0.isAuthoringAuthorizationInFlight = true
      }?.value
      await waitForAuthoringAuthorization(toFinishIn: store)

      let requests = await recorder.requests()
      expectNoDifference(
        requests,
        [
          Authoring.Request(
            subject: .sourceBaseline(sourceBaselineID),
            feature: .workspace,
            action: .enterAuthoring
          )
        ]
      )
      #expect(store.state.authoringMode == .authoring(.all))
      #expect(store.state.showsAuthoringControls)
      #expect(!store.state.isAuthoringAuthorizationInFlight)
    }
  }

  @Test
  func tangledSourceDescriptorIsAllowedOutsideDevelopmentOverride() async throws {
    try await withNonExhaustiveTest {
      let database = try makePreparedDatabase()
      let organizerID = organizerID("wickedwoods")
      let descriptor = WhiteLabelSourceDescriptor(
        reference: .source("https://tangled.org/did:plc:cqqtuv75m7e5s4uj6nw4czyu/wicked-woods-ome")
      )
      let recorder = SourceImportRecorder()

      let store = makeStore(
        configuration: WickedWoodsWhiteLabel.configuration(organizerID: organizerID),
        database: database
      ) {
        $0.whiteLabelSourceRegistry = .codeBacked([organizerID: descriptor])
        $0.whiteLabelSourceImport = WhiteLabelSourceImportClient {
          importedOrganizerID, importedDescriptor in
          await recorder.record(organizerID: importedOrganizerID, descriptor: importedDescriptor)
          return []
        }
      }

      await load(store)

      #expect(await recorder.records == [.init(organizerID: organizerID, descriptor: descriptor)])
      #expect(store.state.organizationRoot?.state.organizerID == organizerID)
      #expect(store.state.errorMessage == nil)
    }
  }

  @Test
  func registrySourceDescriptorRequiresDevelopmentOverride() async throws {
    try await withNonExhaustiveTest {
      let database = try makePreparedDatabase()
      let organizerID = organizerID("wickedwoods")
      let descriptor = WhiteLabelSourceDescriptor(reference: .source("/tmp/wicked-woods-ome"))

      let store = makeStore(
        configuration: WickedWoodsWhiteLabel.configuration(organizerID: organizerID),
        database: database
      ) {
        $0.whiteLabelSourceRegistry = .codeBacked([organizerID: descriptor])
        $0.whiteLabelSourceImport = WhiteLabelSourceImportClient { _, _ in
          throw RegistryShouldNotBeCalled()
        }
      }

      await load(store, suppressingReportedIssues: true)

      #expect(
        store.state.errorMessage
          == "Unable to load event source.")
      #expect(store.state.organizationRoot?.state.organizerID == nil)
    }
  }

  @Test
  func liveSourceImportDelegatesSourceReferencesToTangledSourceImport() async throws {
    let database = try makePreparedDatabase()
    let organizerID = organizerID("wickedwoods")
    let importedEventID = eventID(organizerID: organizerID, eventID: "2025")
    let source = "https://tangled.org/did:plc:cqqtuv75m7e5s4uj6nw4czyu/wicked-woods-ome"
    let recorder = TangledSourceImportRecorder()

    let importedEventIDs = try await withDependencies {
      $0.context = .test
      $0.defaultDatabase = database
      $0.tangledSourceImport = TangledSourceImportClient { request in
        await recorder.record(request)
        return try validationResult(eventID: importedEventID)
      }
    } operation: {
      try await WhiteLabelSourceImportClient.live.ensureImported(
        organizerID,
        WhiteLabelSourceDescriptor(reference: .source(source))
      )
    }

    #expect(importedEventIDs == [importedEventID])
    #expect(await recorder.requests == [
      OpenMusicEventSourceValidationRequest(
        source: source,
        organizerID: organizerID
      )
    ])
  }

  @Test
  func liveSourceImportPassesDescriptorVersionToTangledSourceImport() async throws {
    let database = try makePreparedDatabase()
    let organizerID = organizerID("wickedwoods")
    let importedEventID = eventID(organizerID: organizerID, eventID: "2025")
    let source = "https://tangled.org/did:plc:cqqtuv75m7e5s4uj6nw4czyu/wicked-woods-ome"
    let recorder = TangledSourceImportRecorder()

    let importedEventIDs = try await withDependencies {
      $0.context = .test
      $0.defaultDatabase = database
      $0.tangledSourceImport = TangledSourceImportClient { request in
        await recorder.record(request)
        return try validationResult(eventID: importedEventID)
      }
    } operation: {
      try await WhiteLabelSourceImportClient.live.ensureImported(
        organizerID,
        WhiteLabelSourceDescriptor(reference: .source(source), version: "main")
      )
    }

    #expect(importedEventIDs == [importedEventID])
    #expect(await recorder.requests == [
      OpenMusicEventSourceValidationRequest(
        source: source,
        organizerID: organizerID,
        ref: "main"
      )
    ])
  }

  private func makeStore(
    configuration: WhiteLabelAppConfiguration,
    database: any DatabaseWriter,
    updateDependencies: (inout DependencyValues) -> Void = { _ in }
  ) -> TestStore<WhiteLabelRoot> {
    withDependencies {
      $0.context = .test
      $0.defaultDatabase = database
      $0.defaultEventID = eventID(
        organizerID: organizerID("white-label-test-default"),
        eventID: "default"
      )
      updateDependencies(&$0)
    } operation: {
      TestStore(initialState: WhiteLabelRoot.State(configuration: configuration)) {
        WhiteLabelRoot()
      }
    }
  }

  private func makePreparedDatabase() throws -> any DatabaseWriter {
    try withDependencies {
      $0.context = .test
    } operation: {
      let database = try SQLiteData.defaultDatabase()
      var migrator = DatabaseMigrator()
      OMERecord.DatabaseMigrations.register(into: &migrator)
      OpenMusicEventAppDatabaseMigrations.register(into: &migrator)
      try migrator.migrate(database)
      return database
    }
  }

  private func withNonExhaustiveTest(
    _ operation: () async throws -> Void
  ) async throws {
    try await TestExhaustivity.$current.withValue(.off) {
      try await operation()
    }
  }

  private func load(
    _ store: TestStore<WhiteLabelRoot>,
    suppressingReportedIssues: Bool = false
  ) async {
    if suppressingReportedIssues {
      let reporters = IssueReporters.current
      IssueReporters.current = []
      defer { IssueReporters.current = reporters }
      await performLoad(store)
    } else {
      await performLoad(store)
    }
  }

  private func performLoad(_ store: TestStore<WhiteLabelRoot>) async {
    await store.send(WhiteLabelRoot.Action.task)?.value
    await waitForLoad(toFinishIn: store)
  }

  private func waitForLoad(toFinishIn store: TestStore<WhiteLabelRoot>) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(60))
    while !loadIsSettled(store.state) && clock.now < deadline {
      try? await Task.sleep(for: .milliseconds(10))
    }
    #expect(loadIsSettled(store.state))
  }

  private func loadIsSettled(_ state: WhiteLabelRoot.State) -> Bool {
    !state.isLoading
      && (state.errorMessage != nil || state.organizerID != nil)
  }

  private func waitForAuthoringAuthorization(toFinishIn store: TestStore<WhiteLabelRoot>) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(60))
    while store.state.isAuthoringAuthorizationInFlight && clock.now < deadline {
      try? await Task.sleep(for: .milliseconds(10))
    }
    #expect(store.state.isAuthoringAuthorizationInFlight == false)
  }
}

private struct RegistryShouldNotBeCalled: Error {}

private actor HTTPRequestRecorder {
  struct Request: Sendable {
    var url: URL?
    var body: Data?
  }

  private var values: [Request] = []

  var requests: [Request] {
    values
  }

  func record(_ request: HTTPRequest, _ body: Data?) {
    values.append(
      Request(
        url: request.url,
        body: body
      )
    )
  }
}

private actor StartupOrderRecorder {
  enum Event: Equatable, Sendable {
    case storedAuthentication
    case sourceImport
  }

  private(set) var events: [Event] = []

  func record(_ event: Event) {
    events.append(event)
  }
}

private struct SourceImportRecord: Equatable, Sendable {
  var organizerID: OMERecord.Organizer.ID
  var descriptor: WhiteLabelSourceDescriptor
}

private actor SourceImportRecorder {
  private var values: [SourceImportRecord] = []

  var records: [SourceImportRecord] {
    values
  }

  func record(
    organizerID: OMERecord.Organizer.ID,
    descriptor: WhiteLabelSourceDescriptor
  ) {
    values.append(SourceImportRecord(organizerID: organizerID, descriptor: descriptor))
  }
}

private actor AuthoringRequestRecorder {
  private var values: [Authoring.Request] = []

  func requests() -> [Authoring.Request] {
    values
  }

  func record(_ request: Authoring.Request) {
    values.append(request)
  }
}

private actor TangledSourceImportRecorder {
  private var values: [OpenMusicEventSourceValidationRequest] = []

  var requests: [OpenMusicEventSourceValidationRequest] {
    values
  }

  func record(_ request: OpenMusicEventSourceValidationRequest) {
    values.append(request)
  }
}

private func validationResult(
  eventID: OMERecord.Event.ID
) throws -> OpenMusicEventSourceValidationResult {
  let source = OpenMusicEventSourceRepository(events: [])
  let insertion = try OMERecord.SourceDatabaseInsertion(
    .init(source: source, organizerID: eventID.organizerID)
  )
  return OpenMusicEventSourceValidationResult(
    repositoryURL: FileManager.default.temporaryDirectory,
    organizerID: eventID.organizerID,
    insertion: insertion,
    insertedEventIDs: [eventID],
    summary: SourceValidationSummary(
      events: [.init(eventID: eventID.eventID.rawValue.rawValue, name: "Imported Event")],
      stageCount: 0,
      scheduleCount: 0,
      contributorCount: 0,
      channelCount: 0,
      posterCount: 0,
      performanceCount: 0,
      performanceContributorCount: 0
    )
  )
}

private func insertEvent(
  _ eventID: OMERecord.Event.ID,
  name: String,
  startDate: LocalDate?,
  endDate: LocalDate?,
  into database: any DatabaseWriter
) async throws {
  let timeZone = TimeZone(identifier: "America/Denver")!
  try await database.write { db in
    try OMERecord.Organizer.insert {
      OMERecord.Organizer.Draft(id: eventID.organizerID)
    }
    .execute(db)
    try OMERecord.Event.insert {
      OMERecord.Event.Draft(
        id: eventID,
        name: name,
        description: nil,
        startDate: startDate,
        endDate: endDate,
        status: .known(.planned),
        mode: .known(.inPerson),
        locations: nil,
        uris: nil,
        timeZone: timeZone,
        images: nil,
        contactNumbers: nil,
        categoryConfigs: nil
      )
    }
    .execute(db)
    try OMERecord.EventOrganizer.insert {
      OMERecord.EventOrganizer.Draft(
        id: .init(
          organizerID: eventID.organizerID,
          eventID: eventID.eventID,
          eventOrganizerID: eventID.organizerID
        )
      )
    }
    .execute(db)
  }
}

private func insertSourceBackedEvent(
  _ eventID: OMERecord.Event.ID,
  source: OMERecord.SourceDatabaseInsertion.SourceProvenance,
  into database: any DatabaseWriter
) async throws {
  try await insertEvent(
    eventID,
    name: "Wicked Woods 2025",
    startDate: LocalDate("2025-08-29"),
    endDate: LocalDate("2025-08-31"),
    into: database
  )
  let sourceBaselineID = SourceBaselineRecord.ID(source: source)
  try await database.write { db in
    try SourceBaselineRecord.insert {
      SourceBaselineRecord(
        source: source,
        databaseFileName: "reference.sqlite",
        importedAt: Date(timeIntervalSince1970: 1)
      )
    }
    .execute(db)
    try EventSourceProvenanceRecord.insert {
      EventSourceProvenanceRecord(
        id: eventID,
        sourceBaselineID: sourceBaselineID,
        sourceKind: source.kind,
        sourceReference: source.reference,
        ref: source.ref,
        eventIDOrigin: .explicit,
        sourceEventDirectory: eventID.eventID.rawValue.rawValue
      )
    }
    .execute(db)
  }
}

private func sourceProvenance(
  _ repository: String
) -> OMERecord.SourceDatabaseInsertion.SourceProvenance {
  OMERecord.SourceDatabaseInsertion.SourceProvenance(
    kind: .tangled,
    reference: "https://tangled.org/did:plc:cqqtuv75m7e5s4uj6nw4czyu/\(repository)",
    ref: "HEAD"
  )
}

private func eventID(
  organizerID: OMERecord.Organizer.ID,
  eventID: String
) -> OMERecord.Event.ID {
  OMERecord.Event.ID(
    organizerID: organizerID,
    eventID: localID(eventID)
  )
}

private func localID<Record>(_ string: String) -> OMERecord.ID<Record> {
  OMERecord.ID<Record>(rawValue: ATProto.Record.Key(rawValue: string))
}

private func organizerID(_ string: String) -> OMERecord.Organizer.ID {
  OMERecord.Organizer.ID("did:plc:\(string)")!
}

private func didDocument(
  did: DID,
  handle: Atmosphere.Account.Handle,
  pdsHost: String? = nil
) throws -> DID.Document {
  let service = pdsHost.map {
    """
        "service": [
          {
            "id": "#atproto_pds",
            "type": "AtprotoPersonalDataServer",
            "serviceEndpoint": "https://\($0)"
          }
        ]
    """
  } ?? """
        "service": []
  """

  return try JSONDecoder().decode(
    DID.Document.self,
    from: Data(
      """
      {
        "id": "\(did)",
        "alsoKnownAs": ["at://\(handle.rawValue)"],
        "verificationMethod": [],
        \(service)
      }
      """.utf8
    )
  )
}
