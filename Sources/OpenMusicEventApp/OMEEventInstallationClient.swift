import ATProto
import ComposableArchitecture2
import ComposableCalendarEvents
import Dependencies
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceEditing
import SQLiteData

public struct OMEEventInstallationClient: Sendable {
    public var ensureInstalled: @Sendable (ATProto.URI) async throws -> OMERecord.Event.ID

    public init(
        ensureInstalled: @escaping @Sendable (ATProto.URI) async throws -> OMERecord.Event.ID
    ) {
        self.ensureInstalled = ensureInstalled
    }
}

public enum OMEEventInstallationError: Error, Equatable {
    case invalidEventURI(ATProto.URI)
    case eventIsNotInstalled(ATProto.URI)
    case installationSourceUnavailable(ATProto.URI)
}

extension OMEEventInstallationClient: DependencyKey {
    public static var liveValue: Self {
        Self { eventURI in
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
            if installation.event != nil, installation.provenance != nil {
                return eventID
            }

            let page = try await CalendarEventsClient.openMusicEventPage(
                CalendarEvent.PageRequest(
                    collection: OME.Event.nsid,
                    limit: 100
                )
            )
            guard let catalogEvent = page.events.first(where: { $0.uri == eventURI }),
                let installationRequest = catalogEvent.source.installationRequest(
                    organizerID: eventID.organizerID
                )
            else {
                throw OMEEventInstallationError.installationSourceUnavailable(eventURI)
            }

            let result = try await OpenMusicEventSourceValidator(installationRequest)
                .validate(eventID: eventID)
            if installation.event == nil {
                try await result.insertion.migrateAndInsert(into: database)
            } else {
                guard let provenance = result.insertion.eventSourceProvenances
                    .first(where: { $0.eventID == eventID })
                else {
                    throw OMEEventInstallationError.installationSourceUnavailable(eventURI)
                }
                try await database.write { db in
                    try EventSourceProvenanceRecord.insert {
                        EventSourceProvenanceRecord(provenance)
                    } onConflict: {
                        $0.id
                    }
                    .execute(db)
                }
            }
            return eventID
        }
    }

    public static var testValue: Self {
        Self { eventURI in
            throw OMEEventInstallationError.eventIsNotInstalled(eventURI)
        }
    }
}

public extension DependencyValues {
    var omeEventInstallation: OMEEventInstallationClient {
        get { self[OMEEventInstallationClient.self] }
        set { self[OMEEventInstallationClient.self] = newValue }
    }
}
