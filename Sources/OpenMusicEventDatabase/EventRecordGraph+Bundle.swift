import ATProto
import Foundation
import OpenMusicEventLexicon

public extension EventRecordGraph {
    init(bundle: Event.Bundle) throws {
        guard bundle.formatVersion == 1, !bundle.revision.isEmpty,
              Set(bundle.records.map(\.uri)).count == bundle.records.count else {
            throw ValidationError("Unsupported or invalid event bundle")
        }
        func decode<R: RecordCodable & NamedLexiconDefinition>(_ type: R.Type) throws -> [R] {
            try bundle.records.filter { $0.uri.collection == ATProto.NSID(R.lexiconID.rawValue) }.map {
                return try R.decodeLexicon($0.value, metadata: RecordMetadata(uri: $0.uri, cid: $0.cid))
            }
        }
        let events = try decode(Event.self)
        guard events.count == 1, let event = events.first, event.id == bundle.uri else {
            throw ValidationError("The event bundle must contain exactly the requested event")
        }
        self.init(event: event,
            programs: try decode(Program.self), schedules: try decode(Schedule.self),
            places: try decode(EventPlace.self), contributors: try decode(Contributor.self),
            items: try decode(ProgramItem.self), categories: try decode(Social.Category.self),
            posts: try decode(Social.Post.self))
        let count = 1 + programs.count + schedules.count + places.count + contributors.count
            + items.count + categories.count + posts.count
        guard count == bundle.records.count else { throw ValidationError("Unknown event bundle record type") }
        try validateBundleRelationships()
    }

    func validateBundleRelationships() throws {
        try validateRelationships()
        let contributorIDs = Set(contributors.map(\.id))
        guard items.allSatisfy({ ($0.credits ?? []).allSatisfy {
            $0.contributor.map { contributorIDs.contains($0) } ?? true
        } }) else { throw ValidationError("The event bundle is missing a credited contributor") }
        let postIDs = Set(posts.map(\.id))
        guard categories.allSatisfy({ Set($0.pinnedPosts ?? []).isSubset(of: postIDs) }) else {
            throw ValidationError("The event bundle is missing a pinned post")
        }
    }
}
