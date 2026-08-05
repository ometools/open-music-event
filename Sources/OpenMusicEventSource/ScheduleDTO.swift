import Foundation
import Lexicon
import OpenMusicEventLexicon
import OrderedCollections

public struct ScheduleDTO: Codable, Equatable, Sendable {
    public typealias ScheduleItems = OrderedDictionary<String, [ScheduleItem]>

    public var id: OMERecord.ID<OMERecord.Schedule>?
    public var eventID: OMERecord.ID<OMERecord.Event>?
    public var date: LocalDate
    public var startsAt: String?
    public var endsAt: String?
    public var customTitle: String?
    public var scheduleItems: ScheduleItems

    public init(
        id: OMERecord.ID<OMERecord.Schedule>? = nil,
        eventID: OMERecord.ID<OMERecord.Event>? = nil,
        date: LocalDate,
        startsAt: String? = nil,
        endsAt: String? = nil,
        customTitle: String? = nil,
        scheduleItems: ScheduleItems
    ) {
        self.id = id
        self.eventID = eventID
        self.date = date
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.customTitle = customTitle
        self.scheduleItems = scheduleItems
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case eventID
        case date
        case startsAt
        case endsAt
        case customTitle
        case scheduleItems
        case performances
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(OMERecord.ID<OMERecord.Schedule>.self, forKey: .id)
        self.eventID = try container.decodeIfPresent(OMERecord.ID<OMERecord.Event>.self, forKey: .eventID)
        self.date = try container.decode(LocalDate.self, forKey: .date)
        self.startsAt = try container.decodeIfPresent(String.self, forKey: .startsAt)
        self.endsAt = try container.decodeIfPresent(String.self, forKey: .endsAt)
        self.customTitle = try container.decodeIfPresent(String.self, forKey: .customTitle)
        self.scheduleItems = try decodeScheduleItems(
            from: container,
            scheduleItemsKey: .scheduleItems,
            legacyPerformancesKey: .performances
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(eventID, forKey: .eventID)
        try container.encode(date, forKey: .date)
        try container.encodeIfPresent(startsAt, forKey: .startsAt)
        try container.encodeIfPresent(endsAt, forKey: .endsAt)
        try container.encodeIfPresent(customTitle, forKey: .customTitle)
        try encodeScheduleItems(scheduleItems, to: &container, forKey: .scheduleItems)
    }
}

public struct InlineScheduleDTO: Codable, Equatable, Sendable {
    public var date: LocalDate?
    public var startsAt: String?
    public var endsAt: String?
    public var customTitle: String?
    public var scheduleItems: ScheduleDTO.ScheduleItems

    public init(
        date: LocalDate? = nil,
        startsAt: String? = nil,
        endsAt: String? = nil,
        customTitle: String? = nil,
        scheduleItems: ScheduleDTO.ScheduleItems
    ) {
        self.date = date
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.customTitle = customTitle
        self.scheduleItems = scheduleItems
    }

    private enum CodingKeys: String, CodingKey {
        case date
        case startsAt
        case endsAt
        case customTitle
        case scheduleItems
        case performances
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.date = try container.decodeIfPresent(LocalDate.self, forKey: .date)
        self.startsAt = try container.decodeIfPresent(String.self, forKey: .startsAt)
        self.endsAt = try container.decodeIfPresent(String.self, forKey: .endsAt)
        self.customTitle = try container.decodeIfPresent(String.self, forKey: .customTitle)
        self.scheduleItems = try decodeScheduleItems(
            from: container,
            scheduleItemsKey: .scheduleItems,
            legacyPerformancesKey: .performances
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(date, forKey: .date)
        try container.encodeIfPresent(startsAt, forKey: .startsAt)
        try container.encodeIfPresent(endsAt, forKey: .endsAt)
        try container.encodeIfPresent(customTitle, forKey: .customTitle)
        try encodeScheduleItems(scheduleItems, to: &container, forKey: .scheduleItems)
    }
}

extension ScheduleDTO {
    public struct ScheduleItem: Codable, Equatable, Sendable {
        public typealias ID = OMERecord.ID<ScheduleItem>
        public typealias Kind = OMERecord.ScheduleItem.Kind

        public var kind: Open<Kind>
        public var id: ID?
        public var title: String
        public var description: String?
        public var startTime: String
        public var endTime: String?
        public var contributors: [Contributor]?
        public var recordings: [ExternalPlatform.Asset]?

        public init(
            kind: Open<Kind> = .known(.performance),
            id: ID? = nil,
            title: String,
            description: String? = nil,
            startTime: String,
            endTime: String? = nil,
            contributors: [Contributor]? = nil,
            recordings: [ExternalPlatform.Asset]? = nil
        ) {
            self.kind = kind
            self.id = id
            self.title = title
            self.description = description
            self.startTime = startTime
            self.endTime = endTime
            self.contributors = contributors
            self.recordings = recordings
        }

        private enum CodingKeys: String, CodingKey {
            case kind
            case id
            case title
            case description
            case startTime
            case endTime
            case contributors
            case contributorIDs
            case contributorNames
            case contributorActors
            case recordings
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                kind: container.decode(Open<Kind>.self, forKey: .kind),
                from: container
            )
        }

        private init(
            kind: Open<Kind>,
            from container: KeyedDecodingContainer<CodingKeys>
        ) throws {
            self.kind = kind
            self.id = try container.decodeIfPresent(
                ID.self,
                forKey: .id
            )
            self.title = try container.decode(String.self, forKey: .title)
            self.description = try container.decodeIfPresent(String.self, forKey: .description)
            self.startTime = try container.decode(String.self, forKey: .startTime)
            self.endTime = try container.decodeIfPresent(String.self, forKey: .endTime)
            self.contributors = try container.decodeIfPresent([Contributor].self, forKey: .contributors)
                ?? Self.legacyContributors(from: container)
            self.recordings = try container.decodeIfPresent([ExternalPlatform.Asset].self, forKey: .recordings)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(kind, forKey: .kind)
            try container.encodeIfPresent(id, forKey: .id)
            try container.encode(title, forKey: .title)
            try container.encodeIfPresent(description, forKey: .description)
            try container.encode(startTime, forKey: .startTime)
            try container.encodeIfPresent(endTime, forKey: .endTime)
            try container.encodeIfPresent(contributors, forKey: .contributors)
            try container.encodeIfPresent(recordings, forKey: .recordings)
        }

        private static func legacyContributors(
            from container: KeyedDecodingContainer<CodingKeys>
        ) throws -> [Contributor]? {
            var contributors: [Contributor] = []

            contributors.append(
                contentsOf: try container
                    .decodeIfPresent([OMERecord.ID<OMERecord.Contributor>].self, forKey: .contributorIDs)?
                    .map { Contributor(subject: .id($0)) } ?? []
            )
            contributors.append(
                contentsOf: try container
                    .decodeIfPresent([String].self, forKey: .contributorNames)?
                    .map { Contributor(subject: .name($0)) } ?? []
            )
            contributors.append(
                contentsOf: try container
                    .decodeIfPresent([OMERecord.Contributor.Actor].self, forKey: .contributorActors)?
                    .map { Contributor(subject: .actor($0)) } ?? []
            )

            return contributors.isEmpty ? nil : contributors
        }

        public struct Contributor: Codable, Equatable, Hashable, Sendable {
            public init(
                subject: Subject,
                billing: OMERecord.ScheduleItem.Contributor.Billing = .primary,
                role: OMERecord.ScheduleItem.Contributor.Role? = nil
            ) {
                self.subject = subject
                self.billing = billing
                self.role = role
            }

            public var subject: Subject
            public var billing: OMERecord.ScheduleItem.Contributor.Billing
            public var role: OMERecord.ScheduleItem.Contributor.Role?

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
                        debugDescription: "Schedule item contributor must contain exactly one of id, name, or actor."
                    )
                }

                self.init(
                    subject: subject,
                    billing: try container.decodeIfPresent(
                        OMERecord.ScheduleItem.Contributor.Billing.self,
                        forKey: .billing
                    ) ?? .primary,
                    role: try container.decodeIfPresent(
                        OMERecord.ScheduleItem.Contributor.Role.self,
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

        fileprivate static func legacyPerformance(from decoder: any Decoder) throws -> Self {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            return try Self(kind: .known(.performance), from: container)
        }
    }
}

private struct LegacyPerformanceScheduleItem: Decodable {
    var scheduleItem: ScheduleDTO.ScheduleItem

    init(from decoder: any Decoder) throws {
        self.scheduleItem = try ScheduleDTO.ScheduleItem.legacyPerformance(from: decoder)
    }
}

private func decodeScheduleItems<Key: CodingKey>(
    from container: KeyedDecodingContainer<Key>,
    scheduleItemsKey: Key,
    legacyPerformancesKey: Key
) throws -> ScheduleDTO.ScheduleItems {
    let containsScheduleItems = container.contains(scheduleItemsKey)
    let containsLegacyPerformances = container.contains(legacyPerformancesKey)

    guard !(containsScheduleItems && containsLegacyPerformances) else {
        throw DecodingError.dataCorruptedError(
            forKey: scheduleItemsKey,
            in: container,
            debugDescription: "A schedule cannot contain both scheduleItems and performances."
        )
    }

    if containsLegacyPerformances {
        let legacyScheduleItems: OrderedDictionary<String, [LegacyPerformanceScheduleItem]> =
            try decodeOrderedValues(from: container, forKey: legacyPerformancesKey)
        return OrderedDictionary(
            uniqueKeysWithValues: legacyScheduleItems.map { stageID, scheduleItems in
                (stageID, scheduleItems.map(\.scheduleItem))
            }
        )
    }

    return try decodeOrderedValues(from: container, forKey: scheduleItemsKey)
}

private func decodeOrderedValues<Key: CodingKey, Value: Decodable>(
    from container: KeyedDecodingContainer<Key>,
    forKey key: Key
) throws -> OrderedDictionary<String, Value> {
    let values = try container.nestedContainer(
        keyedBy: ScheduleStageCodingKey.self,
        forKey: key
    )
    return OrderedDictionary(
        uniqueKeysWithValues: try values.allKeys.map { stageKey in
            (
                stageKey.stringValue,
                try values.decode(Value.self, forKey: stageKey)
            )
        }
    )
}

private func encodeScheduleItems<Key: CodingKey>(
    _ scheduleItems: ScheduleDTO.ScheduleItems,
    to container: inout KeyedEncodingContainer<Key>,
    forKey key: Key
) throws {
    var values = container.nestedContainer(
        keyedBy: ScheduleStageCodingKey.self,
        forKey: key
    )
    for (stageID, scheduleItems) in scheduleItems {
        try values.encode(scheduleItems, forKey: ScheduleStageCodingKey(stageID))
    }
}

private struct ScheduleStageCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        return nil
    }
}
