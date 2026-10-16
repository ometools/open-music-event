import ATProtoTypes
import ATProtoSQLite
import SQLiteData

extension OpenMusicEvent {
    @Lexicon("events.openmusic.defs#semanticIcon", type: .string, description: "A platform-neutral name for a familiar pictogram. Values describe the depicted object or gesture, not the purpose assigned to it by a product.")
    public struct SemanticIcon: RawRepresentable, Hashable, Sendable, SQLiteType {
        @LexiconField(knownValues: [
            "calendar",
            "heart",
            "thumbsUp",
            "personDoingYoga",
            "speechBubbles",
            "gridOfSquares",
        ])
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public static let calendar = Self(rawValue: "calendar")
        public static let heart = Self(rawValue: "heart")
        public static let thumbsUp = Self(rawValue: "thumbsUp")
        public static let personDoingYoga = Self(rawValue: "personDoingYoga")
        public static let speechBubbles = Self(rawValue: "speechBubbles")
        public static let gridOfSquares = Self(rawValue: "gridOfSquares")

        public static let knownValues: [Self] = [
            .calendar,
            .heart,
            .thumbsUp,
            .personDoingYoga,
            .speechBubbles,
            .gridOfSquares,
        ]
    }
}
