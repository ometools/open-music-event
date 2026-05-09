import Foundation
import OpenMusicEventLexicon

public struct ScheduleDTO: Codable, Equatable, Sendable {
    public var id: OMERecord.Schedule.ID?
    public var eventID: OMERecord.Event.ID?
    public var date: LocalDate
    public var startsAt: String?
    public var endsAt: String?
    public var customTitle: String?
    public var performances: [String: [Performance]]

    public init(
        id: OMERecord.Schedule.ID? = nil,
        eventID: OMERecord.Event.ID? = nil,
        date: LocalDate,
        startsAt: String? = nil,
        endsAt: String? = nil,
        customTitle: String? = nil,
        performances: [String: [Performance]]
    ) {
        self.id = id
        self.eventID = eventID
        self.date = date
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.customTitle = customTitle
        self.performances = performances
    }
}

extension ScheduleDTO {
    public struct Performance: Codable, Equatable, Sendable {
        public var id: OMERecord.Performance.ID?
        public var title: String
        public var description: String?
        public var startTime: String
        public var endTime: String?
        public var participantIDs: [OMERecord.Participant.ID]?
        public var participantNames: [String]?
        public var recordings: [ExternalPlatform.Asset]?

        public init(
            id: OMERecord.Performance.ID? = nil,
            title: String,
            description: String? = nil,
            startTime: String,
            endTime: String? = nil,
            participantIDs: [OMERecord.Participant.ID]? = nil,
            participantNames: [String]? = nil,
            recordings: [ExternalPlatform.Asset]? = nil
        ) {
            self.id = id
            self.title = title
            self.description = description
            self.startTime = startTime
            self.endTime = endTime
            self.participantIDs = participantIDs
            self.participantNames = participantNames
            self.recordings = recordings
        }
    }
}
