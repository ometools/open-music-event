import ATProto
import Foundation
import ATProtoTypes
import ATProtoSQLite
import SQLiteData

@Table("events.openmusic.schedule")
@Lexicon("events.openmusic.schedule", type: .record(key: .tid), description: "One organizer-defined festival day shared across an event's programs. Its date names the day attendees use, even when assigned items continue past midnight.")
public struct Schedule: RecordCodable, Equatable {
    @LexiconIgnored
    @Column(primaryKey: true)
    public let id: ATProto.URI

    @LexiconIgnored
    public var cid: ATProto.CID? = nil

    @LexiconField(description: "The DID-based record URI of the events.openmusic.event containing this festival day.")
    public var event: Event.ID

    @LexiconField(encoding: Event.LocalDayString.self, description: "The organizer-defined event-local date attendees use to name this festival day. Assigned items may begin after midnight on the following calendar date.", minLength: 10, maxLength: 10)
    public var date: LocalDate

    @LexiconField(description: "Client-declared timestamp when this schedule record was created.")
    public var createdAt: ATProto.DateTime

    @LexiconField(description: "An optional attendee-facing title that overrides the date's weekday label.", minLength: 1, maxLength: 5_000, maxGraphemes: 500)
    public var title: String? = nil

    /// Call at the authoring or verified ingestion boundary, separately from payload decoding.
    public func validateReferences() throws {
        try LexiconCoding.validateRecordURI(id, type: Self.self)
        try LexiconCoding.validateRecordURI(event, type: Event.self)
        guard id.authority == event.authority else {
            throw ValidationError("A schedule must be published in its event's repository", path: ["event"])
        }
        if let title {
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError("A schedule title cannot be blank", path: ["title"])
            }
        }
        _ = try encodeLexicon()
    }
}
