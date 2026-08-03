import ATProto
import ComposableArchitecture2
import ComposableCalendarEvents
import Dependencies
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSource
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
            let isInstalled = try await database.read { db in
                try OME.Event.find(eventID).fetchOne(db) != nil
            }
            if isInstalled {
                return eventID
            }

            guard let catalogEvent = try CalendarEventsClient
                .temporaryOpenMusicEventRecords()
                .first(where: { record in
                    record.organizerID == eventID.organizerID.description
                        && record.eventID == eventID.eventID.rawValue.rawValue
                }),
                let installationRequest = catalogEvent.installationRequest(
                    organizerID: eventID.organizerID
                )
            else {
                throw OMEEventInstallationError.installationSourceUnavailable(eventURI)
            }

            let result = try await OpenMusicEventSourceValidator(installationRequest)
                .validate(eventID: eventID)
            try await result.insertion.migrateAndInsert(into: database)
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
