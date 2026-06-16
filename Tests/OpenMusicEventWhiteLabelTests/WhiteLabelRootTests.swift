import ATProto
import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventLexicon
import SQLiteData
import Testing

@testable import OpenMusicEventAppEventViewer
@testable import OpenMusicEventWhiteLabel

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
      }?.value

      #expect(store.state.isLoading == false)
      #expect(store.state.events.isEmpty)
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
      }?.value

      #expect(await recorder.records == [.init(organizerID: organizerID, descriptor: descriptor)])
      #expect(store.state.organizerID == organizerID)
      #expect(store.state.errorMessage == nil)
      #expect(store.state.events.map { $0.name } == ["Wicked Woods 2025"])
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
      }?.value

      #expect(await recorder.records == [.init(organizerID: organizerID, descriptor: descriptor)])
      #expect(store.state.organizerID == organizerID)
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
      }?.value

      #expect(
        store.state.errorMessage
          == WhiteLabelError.directSourceRequiresDevelopmentOverride(organizerID)
          .localizedDescription)
      #expect(store.state.events.isEmpty)
    }
  }

  @Test
  func eventButtonPresentsEventViewer() async throws {
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
      }?.value
      store.send(WhiteLabelRoot.Action.eventButtonTapped(selectedEventID))

      #expect(store.state.eventViewer?.state.eventID == selectedEventID)
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
      WhiteLabelDatabaseMigrations.register(into: &migrator)
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
