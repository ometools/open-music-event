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
        public var contributors: [Contributor]?
        public var recordings: [ExternalPlatform.Asset]?

        public init(
            id: OMERecord.ID<OMERecord.Performance>? = nil,
            title: String,
            description: String? = nil,
            startTime: String,
            endTime: String? = nil,
            contributors: [Contributor]? = nil,
            recordings: [ExternalPlatform.Asset]? = nil
        ) {
            self.id = id
            self.title = title
            self.description = description
            self.startTime = startTime
            self.endTime = endTime
            self.contributors = contributors
            self.recordings = recordings
        }

        public struct Contributor: Codable, Equatable, Hashable, Sendable {
            public init(
                subject: Subject,
                billing: OMERecord.Performance.Contributors.Billing = .primary,
                role: OMERecord.Performance.Contributors.Role? = nil
            ) {
                self.subject = subject
                self.billing = billing
                self.role = role
            }

            public var subject: Subject
            public var billing: OMERecord.Performance.Contributors.Billing
            public var role: OMERecord.Performance.Contributors.Role?

            public enum Subject: Equatable, Hashable, Sendable {
                case id(OMERecord.ID<OMERecord.Contributor>)
                case name(String)
                case actor(OMERecord.Contributor.Actor)
            }

            private enum CodingKeys: String, CodingKey {
                case id
                case name
                case actor
                case billing
                case role
            }

            public init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                let id = try container.decodeIfPresent(OMERecord.ID<OMERecord.Contributor>.self, forKey: .id)
                let name = try container.decodeIfPresent(String.self, forKey: .name)
                let actor = try container.decodeIfPresent(OMERecord.Contributor.Actor.self, forKey: .actor)

                let subjects = [
                    id.map(Subject.id),
                    name.map(Subject.name),
                    actor.map(Subject.actor),
                ].compactMap { $0 }
                guard subjects.count == 1, let subject = subjects.first else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .id,
                        in: container,
                        debugDescription: "Performance contributor must contain exactly one of id, name, or actor."
                    )
                }

                self.init(
                    subject: subject,
                    billing: try container.decodeIfPresent(
                        OMERecord.Performance.Contributors.Billing.self,
                        forKey: .billing
                    ) ?? .primary,
                    role: try container.decodeIfPresent(
                        OMERecord.Performance.Contributors.Role.self,
                        forKey: .role
                    )
                )
            }

            public func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                switch subject {
                case let .id(id):
                    try container.encode(id, forKey: .id)
                case let .name(name):
                    try container.encode(name, forKey: .name)
                case let .actor(actor):
                    try container.encode(actor, forKey: .actor)
                }
                if billing != .primary {
                    try container.encode(billing, forKey: .billing)
                }
                try container.encodeIfPresent(role, forKey: .role)
            }
        }
    }
}
