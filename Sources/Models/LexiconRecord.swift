import SQLiteData
import ATProto
import Foundation

public enum Lexicon {
    public enum Record {
        @Selection
        public struct Metadata: LexiconMetadata, Equatable, Sendable, Codable {
            public var cid: ATProto.CID?
            public var createdAt: Date
            public var publishedAt: Date?
        }
    }
}

