import Foundation
import OpenMusicEventLexicon

public extension OME {
    struct SourceDatabaseInsertion: Equatable, Sendable {
        public struct Configuration: Equatable, Sendable {
            public var source: OpenMusicEventSourceRepository
            public var organizerID: OME.Organizer.ID
            public var sourceProvenance: SourceProvenance?

            public init(
                source: OpenMusicEventSourceRepository,
                organizerID: OME.Organizer.ID
            ) {
                self.init(
                    source: source,
                    organizerID: organizerID,
                    sourceProvenance: nil
                )
            }

            public init(
                source: OpenMusicEventSourceRepository,
                organizerID: OME.Organizer.ID,
                sourceProvenance: SourceProvenance?
            ) {
                self.source = source
                self.organizerID = organizerID
                self.sourceProvenance = sourceProvenance
            }
        }

        public enum Error: Swift.Error, Equatable, Sendable {
            case conflictingInferredEventID(
                eventID: OME.Event.ID,
                existingSourceKind: SourceKind?,
                existingSourceReference: String?,
                incomingSourceKind: SourceKind,
                incomingSourceReference: String
            )
            case duplicateEventID(OME.Event.ID)
            case invalidLocalTime(String)
            case missingPerformanceEndTime(
                scheduleID: OME.Schedule.ID,
                stageID: OME.ID<OME.Stage>,
                performanceIndex: Int
            )
        }

        public enum EventIDOrigin: String, Codable, Equatable, Sendable {
            case explicit
            case inferred
        }

        public struct EventSourceProvenance: Equatable, Sendable {
            public var eventID: OME.Event.ID
            public var eventIDOrigin: EventIDOrigin
            public var source: SourceProvenance
            public var sourceEventDirectory: String

            public init(
                eventID: OME.Event.ID,
                eventIDOrigin: EventIDOrigin,
                source: SourceProvenance,
                sourceEventDirectory: String
            ) {
                self.eventID = eventID
                self.eventIDOrigin = eventIDOrigin
                self.source = source
                self.sourceEventDirectory = sourceEventDirectory
            }
        }

        public enum SourceKind: String, Codable, Equatable, Sendable {
            case local
            case tangled
        }

        public struct SourceProvenance: Equatable, Sendable {
            public var kind: SourceKind
            public var reference: String
            public var ref: String?

            public init(
                kind: SourceKind,
                reference: String,
                ref: String? = nil
            ) {
                self.kind = kind
                self.reference = reference
                self.ref = ref
            }
        }

        public var eventSourceProvenances: [EventSourceProvenance]
        public var organizers: [OME.Organizer.Draft]
        public var events: [OME.Event.Draft]
        public var eventOrganizers: [OME.EventOrganizer.Draft]
        public var stages: [OME.Stage.Draft]
        public var schedules: [OME.Schedule.Draft]
        public var participants: [OME.Participant.Draft]
        public var channels: [OME.Channel.Draft]
        public var posters: [OME.Poster.Draft]
        public var performances: [OME.Performance.Draft]
        public var performanceParticipants: [OME.Performance.Participants.Draft]

        public init(_ configuration: Configuration) throws {
            self.organizers = [
                OME.Organizer.Draft(id: configuration.organizerID)
            ]
            self.eventSourceProvenances = []
            self.events = []
            self.eventOrganizers = []
            self.stages = []
            self.schedules = []
            self.participants = []
            self.channels = []
            self.posters = []
            self.performances = []
            self.performanceParticipants = []

            var resolvedEventIDs: Set<OME.Event.ID> = []
            for sourceEvent in configuration.source.events {
                try append(
                    sourceEvent: sourceEvent.components,
                    eventDirectoryName: sourceEvent.directoryName,
                    organizerID: configuration.organizerID,
                    sourceProvenance: configuration.sourceProvenance,
                    resolvedEventIDs: &resolvedEventIDs
                )
            }
        }

        private mutating func append(
            sourceEvent: OpenMusicEventSourceEvent,
            eventDirectoryName: String,
            organizerID: OME.Organizer.ID,
            sourceProvenance: SourceProvenance?,
            resolvedEventIDs: inout Set<OME.Event.ID>
        ) throws {
            let eventIDOrigin: EventIDOrigin
            let localEventID: OME.ID<OME.Event>
            if let explicitEventID = sourceEvent.event.id?.eventID {
                eventIDOrigin = .explicit
                localEventID = explicitEventID
            } else {
                eventIDOrigin = .inferred
                localEventID = Self.localID(eventDirectoryName)
            }
            let eventID = OME.Event.ID(
                organizerID: organizerID,
                eventID: localEventID
            )
            guard resolvedEventIDs.insert(eventID).inserted else {
                throw Error.duplicateEventID(eventID)
            }

            var event = sourceEvent.event.recordDraft
            event.id = eventID
            events.append(event)
            if let sourceProvenance {
                eventSourceProvenances.append(
                    EventSourceProvenance(
                        eventID: eventID,
                        eventIDOrigin: eventIDOrigin,
                        source: sourceProvenance,
                        sourceEventDirectory: eventDirectoryName
                    )
                )
            }
            eventOrganizers.append(
                OME.EventOrganizer.Draft(
                    id: .init(
                        organizerID: organizerID,
                        eventID: localEventID,
                        eventOrganizerID: organizerID
                    )
                )
            )

            stages.append(
                contentsOf: sourceEvent.stages?.map { stage in
                    var draft = stage.data
                    draft.id = draft.id ?? .init(
                        organizerID: organizerID,
                        eventID: localEventID,
                        stageID: Self.localID(stage.fileName)
                    )
                    return draft
                } ?? []
            )

            participants.append(
                contentsOf: sourceEvent.participants?.map { participant in
                    var draft = participant.data
                    draft.id = draft.id ?? .init(
                        organizerID: organizerID,
                        eventID: localEventID,
                        participantID: Self.localID(participant.fileName)
                    )
                    return draft
                } ?? []
            )

            channels.append(
                contentsOf: sourceEvent.channels?.map { channel in
                    var draft = channel.data
                    draft.id = draft.id ?? .init(
                        organizerID: organizerID,
                        eventID: localEventID,
                        channelID: Self.localID(channel.fileName)
                    )
                    return draft
                } ?? []
            )

            posters.append(
                contentsOf: sourceEvent.posters?.map { poster in
                    var draft = poster.data
                    draft.id = draft.id ?? .init(
                        organizerID: organizerID,
                        eventID: localEventID,
                        posterID: Self.localID(poster.fileName)
                    )
                    return draft
                } ?? []
            )

            for schedule in sourceEvent.schedules ?? [] {
                try append(
                    schedule: schedule.data,
                    scheduleFileName: schedule.fileName,
                    organizerID: organizerID,
                    eventID: localEventID,
                    timeZone: event.timeZone
                )
            }
        }

        private mutating func append(
            schedule: ScheduleDTO,
            scheduleFileName: String,
            organizerID: OME.Organizer.ID,
            eventID: OME.ID<OME.Event>,
            timeZone: TimeZone
        ) throws {
            let scheduleID = schedule.id ?? Self.localID(scheduleFileName)
            let scopedScheduleID = OME.Schedule.ID(
                organizerID: organizerID,
                eventID: eventID,
                scheduleID: scheduleID
            )

            schedules.append(
                OME.Schedule.Draft(
                    id: scopedScheduleID,
                    date: schedule.date,
                    startsAt: try schedule.startsAt?.localTimeDate(
                        on: schedule.date,
                        in: timeZone
                    ),
                    endsAt: try schedule.endsAt?.localTimeDate(
                        on: schedule.date,
                        in: timeZone
                    ),
                    customTitle: schedule.customTitle
                )
            )

            for stageIDString in schedule.performances.keys.sorted() {
                let sourcePerformances = schedule.performances[stageIDString] ?? []
                let stageID = OME.ID<OME.Stage>(.init(stageIDString))
                let resolvedStarts = try sourcePerformances.resolvedStartTimes(
                    on: schedule.date,
                    in: timeZone
                )

                for (offset, sourcePerformance) in sourcePerformances.enumerated() {
                    let index = offset + 1
                    let performanceID = sourcePerformance.id
                        ?? Self.localID("\(scheduleID.rawValue.rawValue)-\(stageID.rawValue.rawValue)-\(index)")
                    let scopedPerformanceID = OME.Performance.ID(
                        organizerID: organizerID,
                        eventID: eventID,
                        performanceID: performanceID
                    )
                    let startTime = resolvedStarts[offset]
                    let endTime: Date

                    if let explicitEndTime = sourcePerformance.endTime {
                        endTime = try explicitEndTime.localTimeDate(
                            on: schedule.date,
                            in: timeZone
                        ).advancedPast(startTime, in: timeZone)
                    } else if sourcePerformances.indices.contains(offset + 1) {
                        endTime = resolvedStarts[offset + 1]
                    } else {
                        throw Error.missingPerformanceEndTime(
                            scheduleID: scopedScheduleID,
                            stageID: stageID,
                            performanceIndex: index
                        )
                    }

                    performances.append(
                        OME.Performance.Draft(
                            id: scopedPerformanceID,
                            stageID: stageID,
                            scheduleID: scheduleID,
                            startTime: startTime,
                            endTime: endTime,
                            title: sourcePerformance.title,
                            description: sourcePerformance.description,
                            recordings: sourcePerformance.recordings ?? []
                        )
                    )

                    performanceParticipants.append(
                        contentsOf: (sourcePerformance.participantIDs ?? []).map {
                            OME.Performance.Participants.Draft(
                                organizerID: organizerID,
                                eventID: eventID,
                                performanceID: performanceID,
                                participantID: $0,
                                anonymousName: nil
                            )
                        }
                    )
                    performanceParticipants.append(
                        contentsOf: (sourcePerformance.participantNames ?? []).map {
                            OME.Performance.Participants.Draft(
                                organizerID: organizerID,
                                eventID: eventID,
                                performanceID: performanceID,
                                participantID: nil,
                                anonymousName: $0
                            )
                        }
                    )
                }
            }
        }

        private static func localID<Record>(_ string: String) -> OME.ID<Record> {
            OME.ID<Record>(.init(string))
        }
    }
}

private extension Array where Element == ScheduleDTO.Performance {
    func resolvedStartTimes(on date: LocalDate, in timeZone: TimeZone) throws -> [Date] {
        var resolved: [Date] = []
        resolved.reserveCapacity(count)

        for performance in self {
            var startTime = try performance.startTime.localTimeDate(
                on: date,
                in: timeZone
            )
            if let previousStartTime = resolved.last {
                startTime = startTime.advancedPast(previousStartTime, in: timeZone)
            }
            resolved.append(startTime)
        }

        return resolved
    }
}

private extension String {
    func localTimeDate(on date: LocalDate, in timeZone: TimeZone) throws -> Date {
        let parts = split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count),
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              let second = parts.count == 3 ? Int(parts[2]) : 0,
              let date = date.at(hour: hour, minute: minute, second: second, in: timeZone)
        else {
            throw OME.SourceDatabaseInsertion.Error.invalidLocalTime(self)
        }

        return date
    }
}

private extension Date {
    func advancedPast(_ previousDate: Date, in timeZone: TimeZone) -> Date {
        var date = self
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        while date <= previousDate {
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: date)
            else { break }
            date = nextDate
        }
        return date
    }
}

extension OME.SourceDatabaseInsertion.Error: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .conflictingInferredEventID(
            eventID,
            _,
            _,
            incomingSourceKind,
            incomingSourceReference
        ):
            return """
            Inferred event ID '\(eventID.eventID.rawValue.rawValue)' for organizer '\(eventID.organizerID)' already belongs to another source. Add an explicit event ID to import \(incomingSourceKind.rawValue) source \(incomingSourceReference).
            """

        case let .duplicateEventID(eventID):
            return "Source resolves more than one event to '\(eventID.eventID.rawValue.rawValue)' for organizer '\(eventID.organizerID)'. Give each event a unique explicit ID."

        case let .invalidLocalTime(value):
            return "Invalid local time: \(value)"

        case let .missingPerformanceEndTime(scheduleID, stageID, performanceIndex):
            return "Missing end time for performance \(performanceIndex) in schedule '\(scheduleID.scheduleID.rawValue.rawValue)' on stage '\(stageID.rawValue.rawValue)'."
        }
    }
}
