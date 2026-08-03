import ATProto
import ComposableArchitecture2
import Dependencies
import OpenMusicEventDatabase
import OpenMusicEventLexicon
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
            guard isInstalled else {
                throw OMEEventInstallationError.eventIsNotInstalled(eventURI)
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
