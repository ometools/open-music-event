import ATProto
import Foundation
import SQLiteData

let userScheduleSystemImage = "calendar.and.person"

@Table("userSchedules")
public struct UserSchedule: Equatable, Sendable, Identifiable {
    public init(
        id: UUID,
        eventID: OMERecord.Event.ID,
        title: String,
        userDID: DID? = nil
    ) {
        self.id = id
        self.eventID = eventID
        self.title = title
        self.userDID = userDID
    }

    @Column(primaryKey: true) public var id: UUID
    public var eventID: OMERecord.Event.ID
    public var title: String
    public var userDID: DID?

    public static func all(
        eventID: OMERecord.Event.ID
    ) -> some SelectStatementOf<UserSchedule> {
        Self
            .where { $0.eventID.eq(eventID) }
            .order { $0.title.collate(.nocase) }
    }

    public static func normalizedTitle(_ title: String) throws -> String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...80).contains(title.count) else {
            throw ValidationError.invalidTitle
        }
        return title
    }

    public enum ValidationError: Error, Equatable, Sendable {
        case invalidTitle
    }
}

extension UserSchedule {
    @Table("userSchedulePerformances")
    public struct Performance: Equatable, Sendable, Identifiable {
        public init(
            scheduleID: UserSchedule.ID,
            performanceID: OMERecord.ID<OMERecord.Performance>
        ) {
            self.id = ID(
                scheduleID: scheduleID,
                performanceID: performanceID
            )
        }

        @Selection
        public struct ID: Hashable, Sendable {
            public init(
                scheduleID: UserSchedule.ID,
                performanceID: OMERecord.ID<OMERecord.Performance>
            ) {
                self.scheduleID = scheduleID
                self.performanceID = performanceID
            }

            public var scheduleID: UserSchedule.ID
            public var performanceID: OMERecord.ID<OMERecord.Performance>
        }

        public var id: ID
    }
}

public struct UserScheduleOverlay: Equatable, Sendable {
    public init(
        schedules: [UserSchedule],
        memberships: [UserSchedule.Performance],
        selectedScheduleID: UserSchedule.ID?
    ) {
        self.schedules = schedules
        self.memberships = memberships
        self.selectedScheduleID = selectedScheduleID
    }

    public let schedules: [UserSchedule]
    public let memberships: [UserSchedule.Performance]
    public let selectedScheduleID: UserSchedule.ID?

    public var selectedSchedule: UserSchedule? {
        guard let selectedScheduleID else { return nil }
        return schedules.first { $0.id == selectedScheduleID }
    }

    public var selectedTitle: String {
        selectedSchedule?.title ?? "Event Schedule"
    }

    public func contains(
        performanceID: OMERecord.ID<OMERecord.Performance>,
        in scheduleID: UserSchedule.ID
    ) -> Bool {
        memberships.contains {
            $0.id.scheduleID == scheduleID
                && $0.id.performanceID == performanceID
        }
    }

    public func isMember(
        performanceID: OMERecord.ID<OMERecord.Performance>
    ) -> Bool {
        guard let selectedScheduleID = selectedSchedule?.id else { return false }
        return contains(performanceID: performanceID, in: selectedScheduleID)
    }

    public func showsMembershipIndicator(
        performanceID: OMERecord.ID<OMERecord.Performance>
    ) -> Bool {
        selectedSchedule == nil && memberships.contains {
            $0.id.performanceID == performanceID
        }
    }

    public func isDimmed(
        performanceID: OMERecord.ID<OMERecord.Performance>
    ) -> Bool {
        selectedSchedule != nil && !isMember(performanceID: performanceID)
    }
}
