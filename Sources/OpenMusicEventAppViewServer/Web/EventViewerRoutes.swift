import ATProto
import ATProtoTypes
import Dependencies
import Elementary
import Foundation
import Hummingbird
import OpenMusicEventLexicon
import OpenMusicEventRouting
import OpenMusicEventWeb
import SQLiteData

extension OpenMusicEventAppViewServer {
    static func viewerResponse(
        claim: BrandedEventRouteClaim,
        canonicalURL: URL,
        query: String?,
        store: OpenMusicEventAppViewStore?
    ) throws -> Response {
        guard let store else { return textResponse("Event \(claim.eventClaim) is temporarily unavailable.", status: .serviceUnavailable) }
        let content: EventViewerContent
        do {
            guard let indexed = try store.eventViewerContent(id: claim.eventID) else {
                return textResponse("Event \(claim.eventClaim) is temporarily unavailable.", status: .serviceUnavailable)
            }
            content = indexed
        } catch is ValidationError {
            return textResponse("Event content is still being indexed.", status: .serviceUnavailable)
        }
        let selection = try EventViewerSelection(query: query)
        let model = try content.presentation(selection: selection)
        let page = EventViewerHTMLPage(model: model, feature: selection.feature, scheduleKind: selection.kind,
            selectedStage: selection.values["stage"], searchQuery: selection.values["q"],
            selectedContributorID: selection.values["contributor"], canonicalURL: canonicalURL.absoluteString)
        return Response(status: .ok,
            headers: [.contentType: "text/html; charset=utf-8", .cacheControl: "no-cache"],
            body: .init(byteBuffer: .init(string: page.render())))
    }
}

extension OpenMusicEventAppViewStore {
    func containsWebBlob(record: ATProto.URI, cid: String) throws -> Bool {
        try database.read { db in
            let value: Lexicon.JSONValue?
            switch record.collection?.rawValue {
            case Event.lexiconID.rawValue: value = try Event.find(record).fetchOne(db)?.encodeLexicon()
            case EventPlace.lexiconID.rawValue: value = try EventPlace.find(record).fetchOne(db)?.encodeLexicon()
            case Contributor.lexiconID.rawValue: value = try Contributor.find(record).fetchOne(db)?.encodeLexicon()
            case ProgramItem.lexiconID.rawValue: value = try ProgramItem.find(record).fetchOne(db)?.encodeLexicon()
            case Social.Category.lexiconID.rawValue: value = try Social.Category.find(record).fetchOne(db)?.encodeLexicon()
            case Social.Post.lexiconID.rawValue: value = try Social.Post.find(record).fetchOne(db)?.encodeLexicon()
            default: return false
            }
            func contains(_ value: Lexicon.JSONValue) -> Bool {
                switch value {
                case .object(let object):
                    if object["$type"]?.string == "blob", object["ref"]?.object?["$link"]?.string == cid { return true }
                    return object.values.contains(where: contains)
                case .array(let values): return values.contains(where: contains)
                default: return false
                }
            }
            return value.map(contains) ?? false
        }
    }
}
