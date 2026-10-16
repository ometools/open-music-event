import ATProtoTypes
import ATProtoSQLite

extension OpenMusicEvent {
    @Lexicon("events.openmusic.defs#color", type: .integer, description: "An opaque 24-bit sRGB color encoded as red × 65536 + green × 256 + blue, with each channel from 0 through 255.")
    public struct Color: RawRepresentable, Hashable, Sendable {
        @LexiconField(minimum: 0, maximum: 0xFFFFFF)
        public let rawValue: Int

        public init?(rawValue: Int) {
            guard (0...0xFFFFFF).contains(rawValue) else { return nil }
            self.rawValue = rawValue
        }
    }
}
