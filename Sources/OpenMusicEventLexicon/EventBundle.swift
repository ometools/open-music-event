import ATProto
import Foundation

public extension Event {
    /// An AppView snapshot. Record CIDs identify the original records; revision identifies
    /// the complete event projection, including changes to child records.
    struct Bundle: Codable, Equatable, Sendable {
        public var formatVersion: Int
        public var uri: Event.ID
        public var revision: String
        public var records: [IndexedRecord]

        public init(formatVersion: Int = 1, uri: Event.ID, revision: String, records: [IndexedRecord]) {
            self.formatVersion = formatVersion
            self.uri = uri
            self.revision = revision
            self.records = records
        }
    }

    struct GetEventBundle: XRPC.Query, Sendable {
        public static let nsid = ATProto.NSID("events.openmusic.getEventBundle")
        public typealias Input = Never
        public typealias Output = Bundle
        public var parameters: Parameters

        public init(uri: Event.ID) { self.parameters = Parameters(uri: uri) }

        public struct Parameters: Codable, Equatable, Sendable {
            public var uri: Event.ID
        }
    }
}
