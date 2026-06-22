import ATProto
import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventAuthentication
import OpenMusicEventLexicon
import OpenMusicEventSource
import SQLiteData
import Testing

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

      await store.send(WhiteLabelRoot.Action.task) {
        $0.isLoading = true
        $0.loadingPhase = .preparing
      }?.value

      #expect(store.state.isLoading == false)
      #expect(store.state.organizationRoot?.state.organizerID == nil)
      #expect(
        store.state.errorMessage
          == WhiteLabelError.sourceRegistryUnconfigured(organizerID).localizedDescription)
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

      await store.send(WhiteLabelRoot.Action.task) {
        $0.isLoading = true
        $0.loadingPhase = .preparing
      }?.value

      #expect(await recorder.records == [.init(organizerID: organizerID, descriptor: descriptor)])
      #expect(store.state.organizerID == organizerID)
      #expect(store.state.organizationRoot?.state.organizerID == organizerID)
      #expect(store.state.errorMessage == nil)
    }
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

      await store.send(WhiteLabelRoot.Action.task) {
        $0.isLoading = true
        $0.loadingPhase = .preparing
      }?.value

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

      await store.send(WhiteLabelRoot.Action.task) {
        $0.isLoading = true
        $0.loadingPhase = .preparing
      }?.value

      #expect(await recorder.records == [.init(organizerID: organizerID, descriptor: descriptor)])
      #expect(store.state.organizerID == organizerID)
      #expect(store.state.organizationRoot?.state.organizerID == organizerID)
      #expect(store.state.errorMessage == nil)
    }
  }

  @Test
  func singleImportedSourcePresentsSourceDetailDirectly() async throws {
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

      await store.send(WhiteLabelRoot.Action.task) {
        $0.isLoading = true
        $0.loadingPhase = .preparing
      }?.value

      #expect(store.state.sourceDetail?.state.sourceBaselineID == sourceBaselineID)
      #expect(store.state.organizationRoot == nil)
      #expect(store.state.errorMessage == nil)

      await store.send(
        WhiteLabelRoot.Action.handleNavigationRequest(
          NavigationRequest.event(selectedEventID, nil)
        )
      )?.value

      #expect(store.state.eventViewer?.state.eventID == selectedEventID)
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

      await store.send(WhiteLabelRoot.Action.task) {
        $0.isLoading = true
        $0.loadingPhase = .preparing
      }?.value

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

      await store.send(WhiteLabelRoot.Action.task) {
        $0.isLoading = true
        $0.loadingPhase = .preparing
      }?.value

      #expect(
        store.state.errorMessage
          == WhiteLabelError.directSourceRequiresDevelopmentOverride(organizerID)
          .localizedDescription)
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
  func eventNavigationPresentsEventViewer() async throws {
    try await withNonExhaustiveTest {
      let database = try makePreparedDatabase()
      let organizerID = organizerID("wickedwoods")
      let descriptor = WhiteLabelSourceDescriptor(
        reference: .archiveURL(URL(string: "https://example.com/wicked-woods.tar.gz")!)
      )
      let selectedEventID = eventID(organizerID: organizerID, eventID: "2025")
      try await insertEvent(
        selectedEventID,
        name: "Wicked Woods 2025",
        startDate: LocalDate("2025-08-29"),
        endDate: LocalDate("2025-08-31"),
        into: database
      )

      let store = makeStore(
        configuration: .init(
          brand: .init(displayName: "Wicked Woods"),
          organizerID: organizerID,
          handle: "wickedwoods.ca"
        ),
        database: database
      ) {
        $0.whiteLabelSourceRegistry = WhiteLabelSourceRegistryClient { requestedOrganizerID in
          #expect(requestedOrganizerID == organizerID)
          return descriptor
        }
        $0.whiteLabelSourceImport = WhiteLabelSourceImportClient {
          requestedOrganizerID, requestedDescriptor in
          #expect(requestedOrganizerID == organizerID)
          #expect(requestedDescriptor == descriptor)
          return [selectedEventID]
        }
      }

      await store.send(WhiteLabelRoot.Action.task) {
        $0.isLoading = true
        $0.loadingPhase = .preparing
      }?.value

      #expect(store.state.organizationRoot?.state.organizerID == organizerID)

      let organizationState = try #require(store.state.organizationRoot?.state)
      let organizationStore = withDependencies {
        $0.context = .test
        $0.defaultDatabase = database
        $0.defaultEventID = selectedEventID
      } operation: {
        TestStore(initialState: organizationState) {
          OrganizationRoot()
        }
      }
      await withDependencies {
        $0.context = .test
        $0.defaultDatabase = database
        $0.defaultEventID = selectedEventID
      } operation: {
        await organizationStore.send(
          OrganizationRoot.Action.handleNavigationRequest(
            NavigationRequest.event(selectedEventID, nil)
          )
        )?.value
      }

      #expect(organizationStore.state.eventViewer?.state.eventID == selectedEventID)
    }
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
}

private struct RegistryShouldNotBeCalled: Error {}

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
