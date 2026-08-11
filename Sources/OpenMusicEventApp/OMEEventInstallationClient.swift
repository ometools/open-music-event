import ATProto
import ComposableArchitecture2
import ComposableCalendarEvents
import Dependencies
import OpenMusicEventDatabase
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
    public var ensureInstalled: @Sendable (ATProto.URI) async throws -> OMERecord.Event.ID
    public var synchronizeInstalledEvent: @Sendable (OMERecord.Event.ID) async throws -> Void

    public init(
        ensureInstalled: @escaping @Sendable (ATProto.URI) async throws -> OMERecord.Event.ID,
        synchronizeInstalledEvent: @escaping @Sendable (
            OMERecord.Event.ID
        ) async throws -> Void
    ) {
        self.ensureInstalled = ensureInstalled
        self.synchronizeInstalledEvent = synchronizeInstalledEvent
    }
}

public enum OMEEventInstallationError: Error, Equatable {
    case invalidEventURI(ATProto.URI)
    case eventIsNotInstalled(ATProto.URI)
    case installationSourceUnavailable(ATProto.URI)
}

extension OMEEventInstallationClient: DependencyKey {
    public static var liveValue: Self {
        Self(
            ensureInstalled: { eventURI in
                @Dependency(\.defaultDatabase) var database
                guard let eventID = OME.Event.ID(eventURI) else {
                    throw OMEEventInstallationError.invalidEventURI(eventURI)
                }
                let installation = try await database.read { db in
                    (
                        event: try OME.Event.find(eventID).fetchOne(db),
                        provenance: try EventSourceProvenanceRecord.find(eventID).fetchOne(db)
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
                    }
                    return eventID
                }

                let catalogEvent = try await CalendarEventsClient.openMusicEvent(eventURI)
                guard let installationRequest = catalogEvent.source.installationRequest(
                    organizerID: eventID.organizerID
                )
                else {
                    throw OMEEventInstallationError.installationSourceUnavailable(eventURI)
                }

                let result = try await OpenMusicEventSourceValidator(installationRequest)
                    .validate(eventID: eventID)
                guard let workspace = result.insertion.eventSourceProvenances
                    .first(where: { $0.eventID == eventID })
                    .flatMap({ EventSourceProvenanceRecord($0).workspace })
                else {
                    throw OMEEventInstallationError.installationSourceUnavailable(eventURI)
                }
                try await result.insertion.installCanonicalEvent(
                    eventID,
                    from: workspace,
                    in: database
                )
                return eventID
            },
            synchronizeInstalledEvent: { eventID in
                @Dependency(\.defaultDatabase) var database

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
                ref: \(workspace.branch)
                """)

                let validation = try await OpenMusicEventSourceValidator(
                    OpenMusicEventSourceValidationRequest(
                        source: workspace.repository,
                        organizerID: workspace.organizerID,
                        ref: workspace.branch
                    )
                )
                .validate(eventID: eventID)
                guard validation.insertedEventIDs == [eventID] else {
                    throw OMEEventInstallationError.installationSourceUnavailable(eventURI)
                }
                NotificationRefreshDiagnostics.notice("""
                Installed event source validated
                event: \(eventURI)
                repository: \(workspace.repository)
                ref: \(workspace.branch)
                """)

                var insertion = validation.insertion
                for index in insertion.eventSourceProvenances.indices {
                    insertion.eventSourceProvenances[index].source = workspace.sourceProvenance
                }
                try await insertion.replaceCanonicalEvent(
                    eventID,
                    from: workspace,
                    in: database
                )
                NotificationRefreshDiagnostics.notice("""
                Installed event source committed
                event: \(eventURI)
                repository: \(workspace.repository)
                ref: \(workspace.branch)
                """)
            }
        )
    }

    public static var testValue: Self {
        Self(
            ensureInstalled: { eventURI in
                throw OMEEventInstallationError.eventIsNotInstalled(eventURI)
            },
            synchronizeInstalledEvent: { eventID in
                throw OMEEventInstallationError.eventIsNotInstalled(
                    OME.Event.reference(id: eventID).uri
                )
            }
        )
    }
}

public extension DependencyValues {
    var omeEventInstallation: OMEEventInstallationClient {
        get { self[OMEEventInstallationClient.self] }
        set { self[OMEEventInstallationClient.self] = newValue }
    }
}
