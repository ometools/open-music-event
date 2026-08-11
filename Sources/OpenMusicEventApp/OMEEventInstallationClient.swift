import ATProto
import ComposableArchitecture2
import ComposableCalendarEvents
import Dependencies
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
    public var synchronizeInstalledEvent: @Sendable (OMERecord.Event.ID) async throws -> Void

    public init(
        ensureInstalled: @escaping @Sendable (ATProto.URI) async throws -> OMERecord.Event.ID,
        synchronizeInstalledEvent: @escaping @Sendable (
            OMERecord.Event.ID
        ) async throws -> Void,
        install: (@Sendable (
            ATProto.URI
        ) -> AsyncThrowingStream<OMEEventInstallationProgress, any Error>)? = nil
    ) {
        self.ensureInstalled = ensureInstalled
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
}

extension OMEEventInstallationClient: DependencyKey {
    public static var liveValue: Self {
        let install = { @Sendable (
            eventURI: ATProto.URI,
            preview: @escaping @Sendable (EventEntryPreview) -> Void
        ) async throws -> OMERecord.Event.ID in
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
            preview(
                EventEntryPreview(
                    title: catalogEvent.name,
                    logoURL: catalogEvent.eventEntryLogoURL
                )
            )
            guard let installationRequest = catalogEvent.source.installationRequest(
                organizerID: eventID.organizerID
            ) else {
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
        }

        return Self(
            ensureInstalled: { eventURI in
                try await install(eventURI) { _ in }
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

public extension DependencyValues {
    var omeEventInstallation: OMEEventInstallationClient {
        get { self[OMEEventInstallationClient.self] }
        set { self[OMEEventInstallationClient.self] = newValue }
    }
}
