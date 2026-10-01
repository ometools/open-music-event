import ATProtoSQLite
import OpenMusicEventLexicon
import Foundation
import SQLiteData

@Table("eventViewerState")
public struct EventViewerState: Equatable, Sendable, Identifiable {
    public init(
        id: Event.ID,
        selectedScheduleID: Schedule.ID? = nil,
        selectedUserScheduleID: UUID? = nil,
        didInitializeUserSchedules: Bool = false
    ) {
        self.id = id
        self.selectedScheduleID = selectedScheduleID
        self.selectedUserScheduleID = selectedUserScheduleID
        self.didInitializeUserSchedules = didInitializeUserSchedules
    }

    public var id: Event.ID
    public var selectedScheduleID: Schedule.ID?
    public var selectedUserScheduleID: UUID?
    public var didInitializeUserSchedules = false

    mutating func mergePersistedChanges(
        from oldValue: Self?,
        to newValue: Self
    ) {
        let baseline = oldValue ?? Self(id: newValue.id)

        if selectedScheduleID == baseline.selectedScheduleID {
            selectedScheduleID = newValue.selectedScheduleID
        }
        if selectedUserScheduleID == baseline.selectedUserScheduleID {
            selectedUserScheduleID = newValue.selectedUserScheduleID
        }
        if didInitializeUserSchedules == baseline.didInitializeUserSchedules {
            didInitializeUserSchedules = newValue.didInitializeUserSchedules
        }
    }

    static func persistChanges(
        from oldValue: Self,
        to newValue: Self,
        in db: Database
    ) throws {
        var storedValue = try EventViewerStateRequest(eventID: newValue.id).fetch(db)
        var hasChanges = false

        if oldValue.selectedScheduleID != newValue.selectedScheduleID {
            storedValue.selectedScheduleID = newValue.selectedScheduleID
            hasChanges = true
        }
        if oldValue.selectedUserScheduleID != newValue.selectedUserScheduleID {
            storedValue.selectedUserScheduleID = newValue.selectedUserScheduleID
            hasChanges = true
        }
        if oldValue.didInitializeUserSchedules != newValue.didInitializeUserSchedules {
            storedValue.didInitializeUserSchedules = newValue.didInitializeUserSchedules
            hasChanges = true
        }

        guard hasChanges else { return }
        try Self.upsert { storedValue }.execute(db)
    }
}

struct EventViewerStateRequest: FetchKeyRequest {
    let eventID: Event.ID

    func fetch(_ db: Database) throws -> EventViewerState {
        try EventViewerState
            .where { $0.id.eq(eventID) }
            .fetchOne(db)
        ?? EventViewerState(id: eventID)
    }
}
