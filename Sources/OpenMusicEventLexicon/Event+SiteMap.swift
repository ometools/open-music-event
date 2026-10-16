import ATProtoTypes
import Foundation

extension Event {
    @Lexicon("events.openmusic.defs#siteMap", description: "An event's selectable site-map presentation. Styles have stable event-local identities and organizer-defined display order.")
    public struct SiteMap: Equatable, Sendable {
        @LexiconField(description: "The attendee-facing map title.", minLength: 1, maxLength: 5_000, maxGraphemes: 500)
        public var title: String

        @LexiconField(description: "Ordered selectable map styles. The first style is the default when no defaultStyleID is supplied.", minLength: 1)
        public var styles: [Style]

        @LexiconField(description: "The stable identifier of the default style. It must identify a style in this map.", minLength: 1, maxLength: 100)
        public var defaultStyleID: String? = nil

        public var defaultStyle: Style? {
            if let defaultStyleID { return styles.first { $0.id == defaultStyleID } }
            return styles.first
        }

        public func validate() throws {
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError("A map title cannot be blank", path: ["title"])
            }
            var identifiers: Set<String> = []
            for (index, style) in styles.enumerated() {
                guard !style.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ValidationError("A map style identifier cannot be blank", path: ["styles", String(index), "id"])
                }
                guard identifiers.insert(style.id).inserted else {
                    throw ValidationError("Map style identifiers must be unique", path: ["styles", String(index), "id"])
                }
                guard !style.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ValidationError("A map style title cannot be blank", path: ["styles", String(index), "title"])
                }
                do { try style.image.validateForPublication() }
                catch let error as ValidationError {
                    throw ValidationError(error.reason, path: ["styles", String(index), "image"] + error.path)
                }
            }
            if let defaultStyleID, !identifiers.contains(defaultStyleID) {
                throw ValidationError("The default map style must exist", path: ["defaultStyleID"])
            }
            _ = try encodeLexicon()
        }
    }
}

extension Event.SiteMap {
    @Lexicon("events.openmusic.defs#mapStyle", description: "One named base-map image with a stable identity inside its event. Renaming or reordering the style preserves its identity.")
    public struct Style: Equatable, Sendable, Identifiable {
        @LexiconField(description: "A stable event-local style identifier, independent of its title and array position.", minLength: 1, maxLength: 100)
        public let id: String

        @LexiconField(description: "The attendee-facing style title.", minLength: 1, maxLength: 5_000, maxGraphemes: 500)
        public var title: String

        @LexiconField(description: "The base image for this map style. Local asset paths and cache policy are not part of the public image.")
        public var image: OME.Image
    }
}
