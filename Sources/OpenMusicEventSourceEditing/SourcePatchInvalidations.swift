import Dependencies
import Foundation
import OpenMusicEventLexicon
import SQLiteData
import SourceEditing

public struct SourcePatchInvalidation: Equatable, Sendable {
    public enum Target: Equatable, Sendable {
        case calendar(OME.Calendar.ID)
        case event(OME.Event.ID)
    }

    public enum Operation: String, Equatable, Sendable {
        case delete
        case insert
        case update
    }

    public var target: Target
    public var operation: Operation
    public var tableName: String

    public init(
        eventID: OME.Event.ID,
        operation: Operation,
        tableName: String
    ) {
        self.target = .event(eventID)
        self.operation = operation
        self.tableName = tableName
    }

    public init(
        calendarID: OME.Calendar.ID,
        operation: Operation,
        tableName: String
    ) {
        self.target = .calendar(calendarID)
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
            OME.sourceMetadataRecordTypes.map(\.descriptor) + OME.sourceTableDescriptors
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
        as: ((String, String, String, String, String) -> Void).self
    )
    func sendSourcePatchInvalidation(
        targetKind: String,
        ownerID: String,
        recordID: String,
        tableName: String,
        operation: String
    ) {
        guard
            let ownerID = OME.Organizer.ID(ownerID),
            let targetKind = SourcePatchInvalidationTargetKind(rawValue: targetKind),
            let operation = SourcePatchInvalidation.Operation(rawValue: operation)
        else { return }

        let invalidation = switch targetKind {
        case .calendar:
            SourcePatchInvalidation(
                calendarID: OME.Calendar.ID(
                    ownerID: ownerID,
                    calendarID: OME.ID<OME.Calendar>(.init(recordID))
                ),
                operation: operation,
                tableName: tableName
            )

        case .event:
            SourcePatchInvalidation(
                eventID: OME.Event.ID(
                    organizerID: ownerID,
                    eventID: OME.ID<OME.Event>(.init(recordID))
                ),
                operation: operation,
                tableName: tableName
            )
        }
        center.yield(invalidation)
    }
}

private func installSourcePatchInvalidationTriggers(
    in db: Database,
    descriptors: [SourceTableDescriptor]
) throws {
    for descriptor in descriptors {
        let target = try SourcePatchInvalidationTriggerTarget(descriptor: descriptor)
        try createSourcePatchInvalidationInsertTrigger(
            for: descriptor,
            target: target,
            in: db
        )
        try createSourcePatchInvalidationUpdateTrigger(
            for: descriptor,
            target: target,
            in: db
        )
        try createSourcePatchInvalidationDeleteTrigger(
            for: descriptor,
            target: target,
            in: db
        )
    }
}

private func createSourcePatchInvalidationInsertTrigger(
    for descriptor: SourceTableDescriptor,
    target: SourcePatchInvalidationTriggerTarget,
    in db: Database
) throws {
    try #sql(
        """
        CREATE TEMPORARY TRIGGER IF NOT EXISTS \(quote: triggerName(for: descriptor, operation: .insert))
        AFTER INSERT ON \(quote: descriptor.tableName)
        FOR EACH ROW
        BEGIN
          SELECT "ome_source_patch_invalidated"(
            \(quote: target.kind.rawValue, delimiter: .text),
            "new".\(quote: target.ownerIDColumnName),
            "new".\(quote: target.recordIDColumnName),
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
    target: SourcePatchInvalidationTriggerTarget,
    in db: Database
) throws {
    try #sql(
        """
        CREATE TEMPORARY TRIGGER IF NOT EXISTS \(quote: triggerName(for: descriptor, operation: .update))
        AFTER UPDATE ON \(quote: descriptor.tableName)
        FOR EACH ROW
        BEGIN
          SELECT "ome_source_patch_invalidated"(
            \(quote: target.kind.rawValue, delimiter: .text),
            "new".\(quote: target.ownerIDColumnName),
            "new".\(quote: target.recordIDColumnName),
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
    target: SourcePatchInvalidationTriggerTarget,
    in db: Database
) throws {
    try #sql(
        """
        CREATE TEMPORARY TRIGGER IF NOT EXISTS \(quote: triggerName(for: descriptor, operation: .delete))
        AFTER DELETE ON \(quote: descriptor.tableName)
        FOR EACH ROW
        BEGIN
          SELECT "ome_source_patch_invalidated"(
            \(quote: target.kind.rawValue, delimiter: .text),
            "old".\(quote: target.ownerIDColumnName),
            "old".\(quote: target.recordIDColumnName),
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

private enum SourcePatchInvalidationTargetKind: String {
    case calendar
    case event
}

private struct SourcePatchInvalidationTriggerTarget {
    var kind: SourcePatchInvalidationTargetKind
    var ownerIDColumnName: String
    var recordIDColumnName: String

    init(descriptor: SourceTableDescriptor) throws {
        if descriptor.primaryKeyColumns.contains("organizerID"),
           descriptor.primaryKeyColumns.contains("eventID")
        {
            self.kind = .event
            self.ownerIDColumnName = "organizerID"
            self.recordIDColumnName = "eventID"
        } else if descriptor.primaryKeyColumns.contains("ownerID"),
                  descriptor.primaryKeyColumns.contains("calendarID")
        {
            self.kind = .calendar
            self.ownerIDColumnName = "ownerID"
            self.recordIDColumnName = "calendarID"
        } else {
            throw SourcePatchInvalidationTriggerError(tableName: descriptor.tableName)
        }
    }
}

private struct SourcePatchInvalidationTriggerError: Error {
    var tableName: String
}
