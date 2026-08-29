import ATProto
import ComposableArchitecture2
import ComposableCalendarEvents
import Dependencies
import Foundation
import OpenMusicEventAppEventViewer
import OpenMusicEventDatabase
import OpenMusicEventEntry
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceEditing
#if canImport(OSLog)
import OSLog
#endif
import SQLiteData

enum NotificationRefreshDiagnostics {
    #if canImport(OSLog)
    static let logger = Logger(
        subsystem: "app.openmusicevent",
        category: "notifications"
    )
    #endif

    static func debug(_ message: String) {
        #if canImport(OSLog)
        logger.debug("\(message, privacy: .public)")
        #else
        print(message)
        #endif
    }

    static func notice(_ message: String) {
        #if canImport(OSLog)
        logger.notice("\(message, privacy: .public)")
        #else
        print(message)
        #endif
    }

    static func failure(_ message: String) {
        #if canImport(OSLog)
        logger.error("\(message, privacy: .public)")
        #else
        print(message)
        #endif
    }
}

public struct OMEEventInstallationClient: Sendable {
    public var install: @Sendable (
        ATProto.URI
    ) -> AsyncThrowingStream<OMEEventInstallationProgress, any Error>
    public var ensureInstalled: @Sendable (ATProto.URI) async throws -> OMERecord.Event.ID
    public var restorePublishedEvents: @Sendable (SourceWorkspace) async throws -> Void
    public var synchronizeInstalledEvent: @Sendable (OMERecord.Event.ID) async throws -> Void

    public init(
        ensureInstalled: @escaping @Sendable (ATProto.URI) async throws -> OMERecord.Event.ID,
        restorePublishedEvents: @escaping @Sendable (SourceWorkspace) async throws -> Void = { _ in },
        synchronizeInstalledEvent: @escaping @Sendable (
            OMERecord.Event.ID
        ) async throws -> Void,
        install: (@Sendable (
            ATProto.URI
        ) -> AsyncThrowingStream<OMEEventInstallationProgress, any Error>)? = nil
    ) {
        self.ensureInstalled = ensureInstalled
        self.restorePublishedEvents = restorePublishedEvents
        self.synchronizeInstalledEvent = synchronizeInstalledEvent
        self.install = install ?? { eventURI in
            AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        continuation.yield(.installed(try await ensureInstalled(eventURI)))
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
    }
}

public enum OMEEventInstallationProgress: Equatable, Sendable {
    case preview(EventEntryPreview)
    case installed(OMERecord.Event.ID)
}

public struct EventEntryPreview: Equatable, Sendable {
    public init(title: String, logoURL: URL?) {
        self.title = title
        self.logoURL = logoURL
    }

    public let title: String
    public let logoURL: URL?
}

public enum OMEEventInstallationError: Error, Equatable {
    case invalidEventURI(ATProto.URI)
    case eventIsNotInstalled(ATProto.URI)
    case installationSourceUnavailable(ATProto.URI)
    case noInstalledEvents(SourceWorkspace.ID)
}

extension OMEEventInstallationClient: DependencyKey {
    public static var liveValue: Self {
        @Dependency(\.defaultDatabase) var database
        return withEscapedDependencies { dependencies in
            live(database: database) {
                dependencies.yield {
                    @Dependency(\.date.now) var now
                    return now
                }
            }
        }
    }

    static func live(database: any DatabaseWriter) -> Self {
        live(database: database) {
            @Dependency(\.date.now) var now
            return now
        }
    }

    private static func live(
        database: any DatabaseWriter,
        now: @escaping @Sendable () -> Date
    ) -> Self {
        let install = { @Sendable (
            eventURI: ATProto.URI,
            preview: @escaping @Sendable (EventEntryPreview) -> Void
        ) async throws -> OMERecord.Event.ID in
            guard let eventID = OME.Event.ID(eventURI) else {
                throw OMEEventInstallationError.invalidEventURI(eventURI)
            }
            let installation = try await database.read { db in
                (
                    event: try OME.Event.find(eventID).fetchOne(db),
                    provenance: try EventSourceProvenanceRecord.find(eventID).fetchOne(db),
                    installedEvent: try InstalledEventRecord.find(eventID).fetchOne(db)
                )
            }
            if installation.event != nil, let provenance = installation.provenance {
                try await database.write { db in
                    try InstalledEventRecord.upsert {
                        InstalledEventRecord(
                            id: eventID,
                            sourceProvenance: provenance.sourceProvenance
                        )
                    }
                    .execute(db)
                    if installation.installedEvent == nil {
                        try initializeCommsPostReadState(
                            for: eventID,
                            now: now(),
                            in: db
                        )
                    }
                }
                return eventID
            }

            let catalogEvent = try await CalendarEventsClient.openMusicEvent(eventURI)
            preview(
                EventEntryPreview(
                    title: catalogEvent.name,
                    logoURL: catalogEvent.eventEntryLogoURL
                )
            )
            let published = try await publishedEventInstallation(
                eventID,
                catalogEvent: catalogEvent
            )
            try await published.insertion.installPublishedEvent(
                eventID,
                from: published.workspace,
                in: database,
                initializeInstalledEvent: { database in
                    try initializeCommsPostReadState(
                        for: eventID,
                        now: now(),
                        in: database
                    )
                }
            )
            return eventID
        }

        return Self(
            ensureInstalled: { eventURI in
                try await install(eventURI) { _ in }
            },
            restorePublishedEvents: { workspace in
                let installedEvents: [InstalledEventRecord] = try await database.read { db in
                    try InstalledEventRecord.all.fetchAll(db)
                }
                let installedEventIDs = installedEvents
                    .filter { $0.workspace?.id == workspace.id }
                    .map(\.id)
                    .sorted { $0.eventID.rawValue < $1.eventID.rawValue }
                guard !installedEventIDs.isEmpty else {
                    throw OMEEventInstallationError.noInstalledEvents(workspace.id)
                }

                var publishedEvents: [OME.SourceDatabaseInsertion] = []
                publishedEvents.reserveCapacity(installedEventIDs.count)
                for eventID in installedEventIDs {
                    let published = try await publishedEventInstallation(eventID)
                    guard published.workspace.referencesSameRepository(as: workspace) else {
                        throw OMEEventInstallationError.installationSourceUnavailable(
                            OME.Event.reference(id: eventID).uri
                        )
                    }
                    publishedEvents.append(published.insertion)
                }
                try await OME.SourceDatabaseInsertion.restorePublishedEvents(
                    publishedEvents,
                    from: workspace,
                    in: database
                )
            },
            synchronizeInstalledEvent: { eventID in
                let provenance = try await database.read { db in
                    try EventSourceProvenanceRecord.find(eventID).fetchOne(db)
                }
                let eventURI = OME.Event.reference(id: eventID).uri
                guard let provenance else {
                    throw OMEEventInstallationError.eventIsNotInstalled(eventURI)
                }
                guard let workspace = provenance.workspace else {
                    throw OMEEventInstallationError.installationSourceUnavailable(eventURI)
                }
                NotificationRefreshDiagnostics.notice("""
                Installed event source resolved
                event: \(eventURI)
                repository: \(workspace.repository)
                ref: \(workspace.defaultBranch)
                """)

                let published = try await publishedEventInstallation(eventID)
                guard published.workspace.referencesSameRepository(as: workspace) else {
                    throw OMEEventInstallationError.installationSourceUnavailable(eventURI)
                }
                NotificationRefreshDiagnostics.notice("""
                Installed event source validated
                event: \(eventURI)
                repository: \(published.workspace.repository)
                installed ref: \(workspace.defaultBranch)
                published ref: \(published.workspace.defaultBranch)
                """)

                try await published.insertion.replacePublishedEvent(
                    eventID,
                    from: published.workspace,
                    in: database
                )
                NotificationRefreshDiagnostics.notice("""
                Installed event source committed
                event: \(eventURI)
                repository: \(published.workspace.repository)
                ref: \(published.workspace.defaultBranch)
                """)
            },
            install: { eventURI in
                AsyncThrowingStream { continuation in
                    let task = Task {
                        do {
                            let eventID = try await install(eventURI) { preview in
                                continuation.yield(.preview(preview))
                            }
                            continuation.yield(.installed(eventID))
                            continuation.finish()
                        } catch {
                            continuation.finish(throwing: error)
                        }
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            }
        )
    }

    public static var testValue: Self {
        Self(
            ensureInstalled: { eventURI in
                throw OMEEventInstallationError.eventIsNotInstalled(eventURI)
            },
            restorePublishedEvents: { workspace in
                throw OMEEventInstallationError.noInstalledEvents(workspace.id)
            },
            synchronizeInstalledEvent: { eventID in
                throw OMEEventInstallationError.eventIsNotInstalled(
                    OME.Event.reference(id: eventID).uri
                )
            }
        )
    }
}

private extension OME.CalendarEvent {
    var eventEntryLogoURL: URL? {
        media.first { $0.normalizedEventEntryRole == "icon" }?.url
            ?? media.first { $0.normalizedEventEntryRole == "logo" }?.url
    }
}

private extension OME.CalendarEvent.Media {
    var normalizedEventEntryRole: String? {
        role?
            .split(separator: "#")
            .last
            .map(String.init)?
            .lowercased()
    }
}

private struct PublishedEventInstallation {
    var insertion: OME.SourceDatabaseInsertion
    var workspace: SourceWorkspace
}

private func publishedEventInstallation(
    _ eventID: OMERecord.Event.ID,
    catalogEvent providedCatalogEvent: OME.CalendarEvent? = nil
) async throws -> PublishedEventInstallation {
    let eventURI = OME.Event.reference(id: eventID).uri
    let catalogEvent: OME.CalendarEvent
    if let providedCatalogEvent = providedCatalogEvent {
        catalogEvent = providedCatalogEvent
    } else {
        catalogEvent = try await CalendarEventsClient.openMusicEvent(eventURI)
    }
    guard let installationRequest = try catalogEvent.source.installationRequest(
        organizerID: eventID.organizerID
    ) else {
        throw OMEEventInstallationError.installationSourceUnavailable(eventURI)
    }

    let result = try await OpenMusicEventSourceValidator(installationRequest)
        .validate(eventID: eventID)
    guard result.insertedEventIDs == [eventID],
          let workspace = result.insertion.eventSourceProvenances
            .first(where: { $0.eventID == eventID })
            .flatMap({ EventSourceProvenanceRecord($0).workspace })
    else {
        throw OMEEventInstallationError.installationSourceUnavailable(eventURI)
    }
    return PublishedEventInstallation(insertion: result.insertion, workspace: workspace)
}

private func initializeCommsPostReadState(
    for eventID: OME.Event.ID,
    now: Date,
    in database: Database
) throws {
    guard let event = try OME.Event.find(eventID).fetchOne(database),
          event.isPast(at: now)
    else { return }
    try CommsPostRead.setRead(true, eventID: eventID, in: database)
}

private extension OME.Event {
    func isPast(at now: Date) -> Bool {
        let today = LocalDate(now, in: timeZone)
        if let endDate {
            return endDate < today
        }
        if let startDate {
            return startDate < today
        }
        return false
    }
}

public extension DependencyValues {
    var omeEventInstallation: OMEEventInstallationClient {
        get { self[OMEEventInstallationClient.self] }
        set { self[OMEEventInstallationClient.self] = newValue }
    }
}
