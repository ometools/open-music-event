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
  func singleTangledSourceConfiguresAccountForLoginScopes() async throws {
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
        OpenMusicEventOAuth.baseAuthRequirement.permissions.map(\.rawValue)
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
  func enterAuthoringButtonPreparesSourceBeforeShowingAuthoringControls() async throws {
    try await withNonExhaustiveTest {
      let database = try makePreparedDatabase()
      let organizerID = organizerID("wickedwoods")
      let selectedEventID = eventID(organizerID: organizerID, eventID: "2025")
      let descriptor = WhiteLabelSourceDescriptor(
        reference: .source("https://tangled.org/did:plc:cqqtuv75m7e5s4uj6nw4czyu/wicked-woods-ome")
      )
      let source = sourceProvenance("wicked-woods-ome")
      let sourceBaselineID = SourceBaselineRecord.ID(source: source)
      let preparationGate = AuthoringPreparationGate()
      let recorder = AuthoringRequestRecorder()

      let store = makeStore(
        configuration: WickedWoodsWhiteLabel.configuration(organizerID: organizerID),
        database: database
      ) {
        $0.authoringPolicy = AuthoringPolicyClient(
          authenticate: { _ in OpenMusicEventOAuth.baseAuthRequirement },
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
        $0.sourceEditModePreparation = SourceEditModePreparationClient { sourceBaselineID in
          await preparationGate.prepare(sourceBaselineID)
        }
      }

      await load(store)

      #expect(store.state.authoringSubject == .sourceBaseline(sourceBaselineID))
      #expect(store.state.authoringMode == .attendee)
      #expect(!store.state.showsAuthoringControls)

      let entryTask = store.send(.enterAuthoringButtonTapped) {
        $0.isAuthoringAuthorizationInFlight = true
      }
      let preparedSourceBaselineIDs = await preparationGate.waitForPreparationToStart()
      expectNoDifference(
        preparedSourceBaselineIDs,
        [sourceBaselineID]
      )
      #expect(store.state.authoringMode == .attendee)
      #expect(!store.state.showsAuthoringControls)
      #expect(store.state.isAuthoringAuthorizationInFlight)

      await preparationGate.finish()
      await store.receive(
        \.enterAuthoringAuthorized,
        .matching { (
          response: (
            Authoring.Subject,
            Authoring.Scope
          )
        ) in
          response.0 == .sourceBaseline(sourceBaselineID)
            && response.1 == .all
        },
        timeout: .seconds(1)
      ) {
        $0.isAuthoringAuthorizationInFlight = false
        $0.authoringMode = .authoring(.all)
      }
      await entryTask?.value

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
  func whiteLabelAppDependenciesRequireLoginBeforeAuthoringEntry() async throws {
    let recorder = AuthRequirementRecorder()
    let organizerID = organizerID("wickedwoods")
    let eventID = eventID(organizerID: organizerID, eventID: "2025")

    try await withDependencies {
      OpenMusicEventWhiteLabelAppDependencies.prepareDependencies(&$0)
      $0.oauthAuthorizationBroker = OAuth.AuthorizationBroker { requirement in
        await recorder.record(requirement)
      }
    } operation: {
      @Dependency(\.authoringPolicy) var authoringPolicy

      let request = Authoring.Request(
        subject: .event(eventID),
        feature: .workspace,
        action: .enterAuthoring
      )
      #expect(try authoringPolicy.authenticate(request.subject) == OpenMusicEventOAuth.baseAuthRequirement)
      _ = try await authoringPolicy.authorize(request)
    }

    #expect(await recorder.requirements == [OpenMusicEventOAuth.baseAuthRequirement])
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

  @Test
  func liveSourceImportUsesArchiveCheckoutForInitialSourceImport() async throws {
    let database = try makePreparedDatabase()
    let organizerID = organizerID("wickedwoods")
    let importedEventID = eventID(organizerID: organizerID, eventID: "2025")
    let source = "https://tangled.org/did:plc:cqqtuv75m7e5s4uj6nw4czyu/wicked-woods-ome"
    let recorder = ArchiveCheckoutRecorder()
    let checkoutURL = FileManager.default.temporaryDirectory
      .appending(path: "white-label-initial-archive-\(UUID().uuidString)")
      .standardizedFileURL
    defer { try? FileManager.default.removeItem(at: checkoutURL) }
    let repository = TangledRepositoryReference(
      host: "tangled.org",
      owner: "did:plc:cqqtuv75m7e5s4uj6nw4czyu",
      repository: "wicked-woods-ome"
    )

    let importedEventIDs = try await withDependencies {
      $0.context = .test
      $0.defaultDatabase = database
      $0.httpClient = HTTPClient { request, _ in
        await recorder.recordArchiveRequest(request)
        return Data("archive".utf8)
      }
      $0.tangledSourceArchiveExtractor = TangledSourceArchiveExtractorClient {
        archiveData, outputURL in
        await recorder.recordExtraction(archiveData: archiveData, outputURL: outputURL)
      }
      $0.tangledSourceCheckout = TangledSourceCheckoutClient { request in
        Issue.record(
          "White-label initial source import should use archive checkout, not the app checkout dependency."
        )
        return TangledSourceCheckout(repositoryURL: request.outputURL)
      }
      $0.tangledSourceImport = TangledSourceImportClient { request in
        @Dependency(\.tangledSourceCheckout) var tangledSourceCheckout
        await recorder.recordImport(request)
        _ = try await tangledSourceCheckout.checkout(
          TangledSourceCheckoutRequest(
            repository: repository,
            ref: request.ref,
            outputURL: checkoutURL
          )
        )
        return try validationResult(eventID: importedEventID)
      }
    } operation: {
      try await WhiteLabelSourceImportClient.live.ensureImported(
        organizerID,
        WhiteLabelSourceDescriptor(reference: .source(source), version: "main")
      )
    }

    #expect(importedEventIDs == [importedEventID])
    let importRequests = await recorder.importRequests()
    expectNoDifference(
      importRequests,
      [
        OpenMusicEventSourceValidationRequest(
          source: source,
          organizerID: organizerID,
          ref: "main"
        )
      ]
    )
    let archiveRequestURLs = await recorder.archiveRequestURLs()
    expectNoDifference(
      archiveRequestURLs,
      [try repository.archiveURL(ref: "main")]
    )
    let extractions = await recorder.extractions()
    expectNoDifference(
      extractions,
      [.init(archiveData: Data("archive".utf8), outputURL: checkoutURL)]
    )
  }

  @Test
  func liveSourceImportUsesArchiveCheckoutEvenWhenAppCheckoutIsGit() async throws {
    let database = try makePreparedDatabase()
    let organizerID = organizerID("wickedwoods")
    let source = "at://did:plc:5df2u7ief6m6tn77jznicxob/sh.tangled.repo/ome-workspace"
    let importedEventID = eventID(organizerID: organizerID, eventID: "2025")
    let recorder = ArchiveCheckoutRecorder()

    let importedEventIDs = try await withDependencies {
      $0.context = .test
      $0.defaultDatabase = database
      $0.tangledSourceCheckout = .git
      $0.tangledSourceImport = TangledSourceImportClient { request in
        @Dependency(\.tangledSourceCheckout) var tangledSourceCheckout
        _ = try await tangledSourceCheckout.checkout(
          TangledSourceCheckoutRequest(
            repository: try TangledRepositoryReference(sourceReference: request.source),
            ref: request.ref,
            outputURL: FileManager.default.temporaryDirectory
              .appending(path: "white-label-launch-\(UUID().uuidString)")
          )
        )
        return try validationResult(eventID: importedEventID)
      }
      $0.tangledSSHCredentials = TangledSSHCredentialsClient {
        Issue.record("White-label launch import should not request SSH credentials.")
        throw PublicWhiteLabelImportRequestedSSHCredentials()
      }
      $0.httpClient = HTTPClient { _, _ in
        Data("archive".utf8)
      }
      $0.tangledSourceArchiveExtractor = TangledSourceArchiveExtractorClient {
        archiveData, outputURL in
        await recorder.recordExtraction(archiveData: archiveData, outputURL: outputURL)
      }
    } operation: {
      try await WhiteLabelSourceImportClient.live.ensureImported(
        organizerID,
        WhiteLabelSourceDescriptor(reference: .source(source), version: "main")
      )
    }

    #expect(importedEventIDs == [importedEventID])
    let extractions = await recorder.extractions()
    #expect(extractions.map(\.archiveData) == [Data("archive".utf8)])
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

private actor AuthRequirementRecorder {
  private var values: [OAuth.AuthRequirement] = []

  var requirements: [OAuth.AuthRequirement] {
    values
  }

  func record(_ requirement: OAuth.AuthRequirement) {
    values.append(requirement)
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

private actor ArchiveCheckoutRecorder {
  struct Extraction: Equatable, Sendable {
    var archiveData: Data
    var outputURL: URL
  }

  private var archiveRequests: [URL] = []
  private var extractionValues: [Extraction] = []
  private var imports: [OpenMusicEventSourceValidationRequest] = []

  func archiveRequestURLs() -> [URL] {
    archiveRequests
  }

  func extractions() -> [Extraction] {
    extractionValues
  }

  func importRequests() -> [OpenMusicEventSourceValidationRequest] {
    imports
  }

  func recordArchiveRequest(_ request: HTTPRequest) {
    if let url = request.url {
      archiveRequests.append(url)
    }
  }

  func recordExtraction(archiveData: Data, outputURL: URL) {
    extractionValues.append(Extraction(archiveData: archiveData, outputURL: outputURL))
  }

  func recordImport(_ request: OpenMusicEventSourceValidationRequest) {
    imports.append(request)
  }
}

private struct PublicWhiteLabelImportRequestedSSHCredentials: Error {}
private actor AuthoringPreparationGate {
  private var isFinished = false
  private var sourceBaselineIDs: [SourceBaselineRecord.ID] = []
  private var finishWaiters: [CheckedContinuation<Void, Never>] = []
  private var startWaiters: [CheckedContinuation<[SourceBaselineRecord.ID], Never>] = []

  func finish() {
    isFinished = true
    let waiters = finishWaiters
    finishWaiters.removeAll()
    waiters.forEach { $0.resume() }
  }

  func prepare(_ sourceBaselineID: SourceBaselineRecord.ID) async {
    sourceBaselineIDs.append(sourceBaselineID)
    let startWaiters = startWaiters
    self.startWaiters.removeAll()
    startWaiters.forEach { $0.resume(returning: sourceBaselineIDs) }
    guard !isFinished else { return }
    await withCheckedContinuation { continuation in
      finishWaiters.append(continuation)
    }
  }

  func waitForPreparationToStart() async -> [SourceBaselineRecord.ID] {
    if !sourceBaselineIDs.isEmpty {
      return sourceBaselineIDs
    }
    return await withCheckedContinuation { continuation in
      startWaiters.append(continuation)
    }
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
