import Foundation
import OpenMusicEventLexicon
import SQLiteData

@Table("performanceReactions")
public struct PerformanceReaction: Equatable, Sendable, Identifiable {
    public init(
        id: UUID,
        performanceID: OME.Performance.ID,
        emoji: Emoji,
        reactedAt: Date
    ) {
        self.id = id
        self.performanceID = performanceID
        self.emoji = emoji
        self.reactedAt = reactedAt
    }

    @Column(primaryKey: true) public var id: UUID
    public var performanceID: OME.Performance.ID
    public var emoji: Emoji
    public var reactedAt: Date
}

extension PerformanceReaction {
    public struct Emoji: Codable, Equatable, Hashable, QueryBindable, RawRepresentable, Sendable {
        public init?(rawValue: String) {
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.count == 1, let character = value.first else { return nil }

            let scalars = character.unicodeScalars
            let isEmoji = scalars.contains { $0.properties.isEmojiPresentation }
                || scalars.contains { $0.value == 0xFE0F || $0.value == 0x20E3 }
                || (scalars.count > 1 && scalars.contains { $0.properties.isEmoji })
            guard isEmoji else { return nil }
            self.rawValue = value
        }

        init(validatedRawValue: String) {
            self.rawValue = validatedRawValue
        }

        public let rawValue: String

        public static let heart = Self(validatedRawValue: "❤️")
        public static let fire = Self(validatedRawValue: "🔥")
        public static let eyes = Self(validatedRawValue: "👀")
        public static let raisedHands = Self(validatedRawValue: "🙌")
        public static let explodingHead = Self(validatedRawValue: "🤯")

        public static let defaults: [Self] = [
            .heart,
            .fire,
            .eyes,
            .raisedHands,
            .explodingHead,
        ]
    }

    public static func forEvent(
        eventID: OME.Event.ID
    ) -> some SelectStatementOf<Self> {
        Self
            .where { $0.performanceID.organizerID.eq(eventID.organizerID) }
            .where { $0.performanceID.eventID.eq(eventID.eventID) }
            .order { $0.reactedAt }
    }

    public static func forPerformance(
        performanceID: OME.Performance.ID
    ) -> some SelectStatementOf<Self> {
        Self
            .where { $0.performanceID.eq(performanceID) }
            .order { $0.reactedAt }
    }

    public static func toggle(
        performanceID: OME.Performance.ID,
        emoji: Emoji,
        id: UUID,
        date: Date,
        in db: Database
    ) throws {
        let existingReaction = try Self
            .where { $0.performanceID.eq(performanceID) }
            .where { $0.emoji.eq(emoji) }
            .fetchOne(db)
        if let reaction = existingReaction {
            try Self.find(reaction.id).delete().execute(db)
            return
        }

        try add(
            performanceID: performanceID,
            emoji: emoji,
            id: id,
            date: date,
            in: db
        )
    }

    public static func add(
        performanceID: OME.Performance.ID,
        emoji: Emoji,
        id: UUID,
        date: Date,
        in db: Database
    ) throws {
        let isSelected = try Self
            .where { $0.performanceID.eq(performanceID) }
            .where { $0.emoji.eq(emoji) }
            .fetchOne(db) != nil
        guard !isSelected else { return }

        try Self.insert {
            Self(
                id: id,
                performanceID: performanceID,
                emoji: emoji,
                reactedAt: date
            )
        }
        .execute(db)

        let existingUsage = try PerformanceReactionEmojiUsage.find(emoji).fetchOne(db)
        try PerformanceReactionEmojiUsage.upsert {
            PerformanceReactionEmojiUsage(
                emoji: emoji,
                selectionCount: (existingUsage?.selectionCount ?? 0) + 1,
                lastUsedAt: date
            )
        }
        .execute(db)
    }

    public static func menuEmojis(
        selected: [Emoji],
        usage: [PerformanceReactionEmojiUsage],
        limit: Int = 5
    ) -> [Emoji] {
        var result: [Emoji] = []

        for emoji in selected where !result.contains(emoji) {
            result.append(emoji)
        }

        let ranked = usage.sorted {
            if $0.selectionCount != $1.selectionCount {
                return $0.selectionCount > $1.selectionCount
            }
            if $0.lastUsedAt != $1.lastUsedAt {
                return $0.lastUsedAt > $1.lastUsedAt
            }
            return $0.emoji.rawValue < $1.emoji.rawValue
        }

        for emoji in ranked.map(\.emoji) + Emoji.defaults {
            guard result.count < Swift.max(limit, selected.count) else { break }
            if !result.contains(emoji) {
                result.append(emoji)
            }
        }
        return result
    }
}

@Table("performanceReactionEmojiUsage")
public struct PerformanceReactionEmojiUsage: Equatable, Sendable, Identifiable {
    public init(
        emoji: PerformanceReaction.Emoji,
        selectionCount: Int,
        lastUsedAt: Date
    ) {
        self.emoji = emoji
        self.selectionCount = selectionCount
        self.lastUsedAt = lastUsedAt
    }

    @Column(primaryKey: true) public var emoji: PerformanceReaction.Emoji
    public var selectionCount: Int
    public var lastUsedAt: Date

    public var id: PerformanceReaction.Emoji { emoji }

    public static var ranked: some SelectStatementOf<Self> {
        Self.order {
            ($0.selectionCount.desc(), $0.lastUsedAt.desc(), $0.emoji)
        }
    }
}
