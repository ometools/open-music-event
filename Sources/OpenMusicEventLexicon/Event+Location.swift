import Foundation
import ATProtoTypes
import ATProtoSQLite

extension Event {
    @Lexicon("events.openmusic.defs#location", description: "A place associated with the event, with an optional name, machine-readable locators, and public links.")
    public struct Location: Equatable, Sendable {
        @LexiconField(description: "The organizer's human-readable name for this event location.", minLength: 1, maxLength: 5_000, maxGraphemes: 500)
        public var name: String? = nil

        @LexiconField(description: "Event-specific information about this location, such as arrival guidance or an announcement status.", maxLength: 30_000, maxGraphemes: 3_000)
        public var description: String? = nil

        @LexiconField(description: "Machine-readable identifiers or coordinates for this location.")
        public var locators: [Open<Locator>]? = nil

        @LexiconField(description: "External pages for this location, such as map-provider or venue links.")
        public var links: [OME.Link]? = nil
    }

    @LexiconUnion
    public enum Locator: Equatable, Sendable {
        case address(Address)
        case foursquare(Foursquare)
        case geo(Geo)
        case hthree(HThree)
    }

    @Lexicon("community.lexicon.location.address", description: "A physical location in the form of a street address.")
    public struct Address: Equatable, Sendable {
        @LexiconField(description: "The ISO 3166 country code. Preferably the 2-letter code.", minLength: 2, maxLength: 10)
        public var country: String

        @LexiconField(description: "The postal code of the location.")
        public var postalCode: String? = nil

        @LexiconField(description: "The administrative region of the country. For example, a state in the USA.")
        public var region: String? = nil

        @LexiconField(description: "The locality of the region. For example, a city in the USA.")
        public var locality: String? = nil

        @LexiconField(description: "The street address.")
        public var street: String? = nil

        @LexiconField(description: "The name of the location.")
        public var name: String? = nil
    }

    @Lexicon("community.lexicon.location.geo", description: "A physical location in the form of a WGS84 coordinate.")
    public struct Geo: Equatable, Sendable {
        public var latitude: String
        public var longitude: String
        public var altitude: String? = nil

        @LexiconField(description: "The name of the location.")
        public var name: String? = nil
    }

    @Lexicon("community.lexicon.location.fsq", description: "A physical location contained in the Foursquare Open Source Places dataset.")
    public struct Foursquare: Equatable, Sendable {
        @LexiconField(name: "fsq_place_id", description: "The unique identifier of a Foursquare POI.")
        public var fsqPlaceID: String
        public var latitude: String? = nil
        public var longitude: String? = nil

        @LexiconField(description: "The name of the location.")
        public var name: String? = nil
    }

    @Lexicon("community.lexicon.location.hthree", description: "A physical location in the form of a H3 encoded location.")
    public struct HThree: Equatable, Sendable {
        @LexiconField(description: "The h3 encoded location.")
        public var value: String

        @LexiconField(description: "The name of the location.")
        public var name: String? = nil
    }
}
