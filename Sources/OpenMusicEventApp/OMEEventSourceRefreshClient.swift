import ComposableNotifications
import Dependencies
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceEditing
import SQLiteData

public struct OMEEventSourceRefreshRequest: Equatable, Sendable {
    public init(
        eventID: OMERecord.Event.ID,
        version: NotificationSource.Version
    ) {
        self.eventID = eventID
        self.version = version
    }

    public var eventID: OMERecord.Event.ID
    public var version: NotificationSource.Version
}

public enum OMEEventSourceRefreshResult: Equatable, Sendable {
    case refreshed
    case requiresWorkspaceReconciliation
}

public struct OMEEventSourceRefreshClient: Sendable {
    public init(
        refresh: @escaping @Sendable (
            OMEEventSourceRefreshRequest
        ) async throws -> OMEEventSourceRefreshResult
    ) {
        self.refresh = refresh
    }

    public var refresh: @Sendable (
        OMEEventSourceRefreshRequest
    ) async throws -> OMEEventSourceRefreshResult
}

public enum OMEEventSourceRefreshError: Error, Equatable, Sendable {
    case eventIsNotInstalled(OMERecord.Event.ID)
    case sourceUnavailable(OMERecord.Event.ID)
    case unexpectedEvent(OMERecord.Event.ID)
}

extension OMEEventSourceRefreshClient: DependencyKey {
    public static var liveValue: Self {
        Self { request in
            @Dependency(\.defaultDatabase) var database

            let installed = try await database.read { db in
                let provenance = try EventSourceProvenanceRecord
                    .find(request.eventID)
                    .fetchOne(db)
                let workspaceInstallation = try provenance?.workspace.flatMap { workspace in
                    try SourceWorkspaceInstallationRecord
                        .find(workspace.id)
                        .fetchOne(db)
                }
                return (
                    provenance: provenance,
                    workspaceInstallation: workspaceInstallation
                )
            }
            guard let provenance = installed.provenance else {
                throw OMEEventSourceRefreshError.eventIsNotInstalled(request.eventID)
            }
            guard let workspace = provenance.workspace else {
                throw OMEEventSourceRefreshError.sourceUnavailable(request.eventID)
            }
            guard installed.workspaceInstallation == nil else {
                return .requiresWorkspaceReconciliation
            }

            let validation = try await OpenMusicEventSourceValidator(
                OpenMusicEventSourceValidationRequest(
                    source: workspace.repository,
                    organizerID: workspace.organizerID,
                    ref: request.version.rawValue
                )
            )
            .validate(eventID: request.eventID)
            guard validation.insertedEventIDs == [request.eventID] else {
                throw OMEEventSourceRefreshError.unexpectedEvent(request.eventID)
            }

            // The notification version selects one immutable Tangled revision. Persisted
            // provenance continues to describe the canonical branch that produced it.
            var insertion = validation.insertion
            for index in insertion.eventSourceProvenances.indices {
                insertion.eventSourceProvenances[index].source = workspace.sourceProvenance
            }
            try await insertion.replaceCanonicalEvent(
                request.eventID,
                from: workspace,
                in: database
            )
            return .refreshed
        }
    }

    public static var testValue: Self {
        Self { _ in
            unimplemented(
                "OMEEventSourceRefreshClient.refresh",
                placeholder: .refreshed
            )
        }
    }
}

public extension DependencyValues {
    var omeEventSourceRefresh: OMEEventSourceRefreshClient {
        get { self[OMEEventSourceRefreshClient.self] }
        set { self[OMEEventSourceRefreshClient.self] = newValue }
    }
}
