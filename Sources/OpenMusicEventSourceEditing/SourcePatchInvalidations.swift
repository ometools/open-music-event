import Dependencies
import Foundation
import OpenMusicEventLexicon
import SQLiteData
import SourceEditing

public struct SourcePatchInvalidation: Equatable, Sendable {
    public enum Operation: String, Equatable, Sendable {
        case delete
        case insert
        case update
    }

    public var eventID: OME.Event.ID
    public var operation: Operation
    public var tableName: String

    public init(
        eventID: OME.Event.ID,
        operation: Operation,
        tableName: String
    ) {
        self.eventID = eventID
        self.operation = operation
        self.tableName = tableName
    }
}

public struct SourcePatchInvalidations: Sendable {
    public var installTriggers: @Sendable (Database) throws -> Void
    public var stream: @Sendable () -> AsyncStream<SourcePatchInvalidation>

    public init(
        installTriggers: @escaping @Sendable (Database) throws -> Void,
        stream: @escaping @Sendable () -> AsyncStream<SourcePatchInvalidation>
    ) {
        self.installTriggers = installTriggers
        self.stream = stream
    }
}

public extension SourcePatchInvalidations {
    static let noop = Self(
        installTriggers: { _ in },
        stream: { AsyncStream { $0.finish() } }
    )

    static func live(
        descriptors: @escaping @Sendable () -> [SourceTableDescriptor] = {
            OME.sourceTableDescriptors
        }
    ) -> Self {
        let center = SourcePatchInvalidationCenter()
        let databaseFunction = SourcePatchInvalidationDatabaseFunction(center: center)

        return Self(
            installTriggers: { db in
                db.add(function: databaseFunction.$sendSourcePatchInvalidation)
                try installSourcePatchInvalidationTriggers(
                    in: db,
                    descriptors: descriptors()
                )
            },
            stream: {
                center.stream()
            }
        )
    }
}

public extension DependencyValues {
    var sourcePatchInvalidations: SourcePatchInvalidations {
        get { self[SourcePatchInvalidationsKey.self] }
        set { self[SourcePatchInvalidationsKey.self] = newValue }
    }
}

private enum SourcePatchInvalidationsKey: DependencyKey {
    static let liveValue = SourcePatchInvalidations.live()
    static let testValue = SourcePatchInvalidations.noop
}

private final class SourcePatchInvalidationCenter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<SourcePatchInvalidation>.Continuation] = [:]

    func stream() -> AsyncStream<SourcePatchInvalidation> {
        let id = UUID()
        return AsyncStream { continuation in
            lock.withLock {
                continuations[id] = continuation
            }
            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(id)
            }
        }
    }

    func yield(_ invalidation: SourcePatchInvalidation) {
        let continuations = lock.withLock {
            Array(self.continuations.values)
        }
        for continuation in continuations {
            continuation.yield(invalidation)
        }
    }

    private func removeContinuation(_ id: UUID) {
        lock.withLock {
            continuations[id] = nil
        }
    }
}

private final class SourcePatchInvalidationDatabaseFunction: @unchecked Sendable {
    private let center: SourcePatchInvalidationCenter

    init(center: SourcePatchInvalidationCenter) {
        self.center = center
    }

    @DatabaseFunction(
        "ome_source_patch_invalidated",
        as: ((String, String, String, String) -> Void).self
    )
    func sendSourcePatchInvalidation(
        organizerID: String,
        eventID: String,
        tableName: String,
        operation: String
    ) {
        guard
            let organizerID = OME.Organizer.ID(organizerID),
            let operation = SourcePatchInvalidation.Operation(rawValue: operation)
        else { return }

        center.yield(
            SourcePatchInvalidation(
                eventID: OME.Event.ID(
                    organizerID: organizerID,
                    eventID: OME.ID<OME.Event>(.init(eventID))
                ),
                operation: operation,
                tableName: tableName
            )
        )
    }
}

private func installSourcePatchInvalidationTriggers(
    in db: Database,
    descriptors: [SourceTableDescriptor]
) throws {
    for descriptor in descriptors {
        try validateEventScopedDescriptor(descriptor)
        try createSourcePatchInvalidationInsertTrigger(for: descriptor, in: db)
        try createSourcePatchInvalidationUpdateTrigger(for: descriptor, in: db)
        try createSourcePatchInvalidationDeleteTrigger(for: descriptor, in: db)
    }
}

private func createSourcePatchInvalidationInsertTrigger(
    for descriptor: SourceTableDescriptor,
    in db: Database
) throws {
    try #sql(
        """
        CREATE TEMPORARY TRIGGER IF NOT EXISTS \(quote: triggerName(for: descriptor, operation: .insert))
        AFTER INSERT ON \(quote: descriptor.tableName)
        FOR EACH ROW
        BEGIN
          SELECT "ome_source_patch_invalidated"(
            "new"."organizerID",
            "new"."eventID",
            \(quote: descriptor.tableName, delimiter: .text),
            \(quote: SourcePatchInvalidation.Operation.insert.rawValue, delimiter: .text)
          );
        END
        """
    )
    .execute(db)
}

private func createSourcePatchInvalidationUpdateTrigger(
    for descriptor: SourceTableDescriptor,
    in db: Database
) throws {
    try #sql(
        """
        CREATE TEMPORARY TRIGGER IF NOT EXISTS \(quote: triggerName(for: descriptor, operation: .update))
        AFTER UPDATE ON \(quote: descriptor.tableName)
        FOR EACH ROW
        BEGIN
          SELECT "ome_source_patch_invalidated"(
            "new"."organizerID",
            "new"."eventID",
            \(quote: descriptor.tableName, delimiter: .text),
            \(quote: SourcePatchInvalidation.Operation.update.rawValue, delimiter: .text)
          );
        END
        """
    )
    .execute(db)
}

private func createSourcePatchInvalidationDeleteTrigger(
    for descriptor: SourceTableDescriptor,
    in db: Database
) throws {
    try #sql(
        """
        CREATE TEMPORARY TRIGGER IF NOT EXISTS \(quote: triggerName(for: descriptor, operation: .delete))
        AFTER DELETE ON \(quote: descriptor.tableName)
        FOR EACH ROW
        BEGIN
          SELECT "ome_source_patch_invalidated"(
            "old"."organizerID",
            "old"."eventID",
            \(quote: descriptor.tableName, delimiter: .text),
            \(quote: SourcePatchInvalidation.Operation.delete.rawValue, delimiter: .text)
          );
        END
        """
    )
    .execute(db)
}

private func triggerName(
    for descriptor: SourceTableDescriptor,
    operation: SourcePatchInvalidation.Operation
) -> String {
    "ome_source_patch_invalidated_\(descriptor.tableName)_\(operation.rawValue)"
}

private func validateEventScopedDescriptor(_ descriptor: SourceTableDescriptor) throws {
    guard descriptor.primaryKeyColumns.contains("organizerID"),
          descriptor.primaryKeyColumns.contains("eventID")
    else {
        throw SourcePatchInvalidationTriggerError(tableName: descriptor.tableName)
    }
}

private struct SourcePatchInvalidationTriggerError: Error {
    var tableName: String
}
