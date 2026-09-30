import ATProto
import Foundation
import ATProtoTypes
import SQLiteData

extension OpenMusicEvent {
    /// The public record value OME will publish when attendee publishing is introduced.
    /// Local persistence stores this same subject and status without pretending it has
    /// already been written to an AT Protocol repository.
    public struct RSVP: Codable, Equatable, Sendable {
        public static let nsid = ATProto.NSID("app.openmusicevent.rsvp")

        public init(subject: Event.Reference, status: Status) {
            self.subject = subject
            self.status = status
        }

        public var subject: Event.Reference
        public var status: Status

        public enum Status: String, Codable, Equatable, Sendable, SQLiteType {
            case interested = "app.openmusicevent.rsvp#interested"
            case going = "app.openmusicevent.rsvp#going"
            case notGoing = "app.openmusicevent.rsvp#notgoing"
        }

        enum CodingKeys: String, CodingKey {
            case type = "$type"
            case subject
            case status
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            subject = try container.decode(Event.Reference.self, forKey: .subject)
            status = try container.decode(Status.self, forKey: .status)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(Self.nsid.rawValue, forKey: .type)
            try container.encode(subject, forKey: .subject)
            try container.encode(status, forKey: .status)
        }
    }
}
