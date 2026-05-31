import Foundation
import OpenMusicEventLexicon

public struct ScheduleDTO: Codable, Equatable, Sendable {
    public var id: OMERecord.ID<OMERecord.Schedule>?
    public var eventID: OMERecord.ID<OMERecord.Event>?
    public var date: LocalDate
    public var startsAt: String?
    public var endsAt: String?
    public var customTitle: String?
    public var performances: [String: [Performance]]

    public init(
        id: OMERecord.ID<OMERecord.Schedule>? = nil,
        eventID: OMERecord.ID<OMERecord.Event>? = nil,
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
        public var id: OMERecord.ID<OMERecord.Performance>?
        public var title: String
        public var description: String?
        public var startTime: String
        public var endTime: String?
        public var contributorIDs: [OMERecord.ID<OMERecord.Contributor>]?
        public var contributorNames: [String]?
        public var contributorActors: [OMERecord.Contributor.Actor]?
        public var recordings: [ExternalPlatform.Asset]?

        public init(
            id: OMERecord.ID<OMERecord.Performance>? = nil,
            title: String,
            description: String? = nil,
            startTime: String,
            endTime: String? = nil,
            contributorIDs: [OMERecord.ID<OMERecord.Contributor>]? = nil,
            contributorNames: [String]? = nil,
            contributorActors: [OMERecord.Contributor.Actor]? = nil,
            recordings: [ExternalPlatform.Asset]? = nil
        ) {
            self.id = id
            self.title = title
            self.description = description
            self.startTime = startTime
            self.endTime = endTime
            self.contributorIDs = contributorIDs
            self.contributorNames = contributorNames
            self.contributorActors = contributorActors
            self.recordings = recordings
        }
    }
}
