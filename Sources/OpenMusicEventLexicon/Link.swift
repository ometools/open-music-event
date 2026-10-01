import Foundation
import ATProtoTypes
import ATProtoSQLite

extension OME {
    @Lexicon("events.openmusic.defs#link", description: "A public link with optional presentation and purpose metadata.")
    public struct Link: Equatable, Sendable {
        @LexiconField(encoding: OpenMusicEventLexicon.Event.URLString.self, description: "The URI opened by this link.", format: "uri")
        public var url: URL

        @LexiconField(description: "A short human-readable label for the link.", minLength: 1, maxLength: 5_000, maxGraphemes: 500)
        public var title: String? = nil

        @LexiconField(description: "Additional human-readable context about the link.", maxLength: 30_000, maxGraphemes: 3_000)
        public var description: String? = nil

        @LexiconField(description: "The link's purpose in the event experience.")
        public var role: Open<Role>? = nil

        @LexiconField(description: "The known external platform that hosts the linked resource.")
        public var platform: Open<ExternalPlatform>? = nil
    }
}

extension OME.Link {
    @Lexicon("events.openmusic.defs#contactUse", type: .string, description: "Whether a contact or reporting channel is intended for an active emergency or a non-emergency matter. Other string values may be used by extensions.")
    public enum ContactUse: String, Equatable, Sendable {
        case emergency
        case nonEmergency
    }

    @LexiconUnion
    public enum Role: Equatable, Sendable {
        case website(Website)
        case tickets(Tickets)
        case contact(Contact)
        case reporting(Reporting)

        @Lexicon("events.openmusic.defs#websiteLink", description: "The event or subject's primary website.")
        public struct Website: Equatable, Sendable {}

        @Lexicon("events.openmusic.defs#ticketsLink", description: "A page where attendees can obtain admission or tickets.")
        public struct Tickets: Equatable, Sendable {}

        @Lexicon("events.openmusic.defs#contactLink", description: "A channel for contacting the event or subject.")
        public struct Contact: Equatable, Sendable {
            @LexiconField(description: "Whether this contact channel is intended for emergencies or non-emergency matters.")
            public var use: Open<ContactUse>? = nil
        }

        @Lexicon("events.openmusic.defs#reportingLink", description: "A channel for reporting a safety, conduct, or operational concern.")
        public struct Reporting: Equatable, Sendable {
            @LexiconField(description: "Whether this reporting channel is intended for an active emergency or a non-emergency matter.")
            public var use: Open<ContactUse>? = nil
        }
    }

    public var platformIdentifier: String? {
        switch platform {
        case .known(let platform): platform.rawValue
        case .unknown(let value): value.string
        case nil: nil
        }
    }

    public var detectedPlatform: ExternalPlatform {
        if case .known(let platform) = platform { return platform }
        return ExternalPlatform.detectPlatform(from: url)
    }
}

public extension Event {
    var contactLinks: [OME.Link] {
        (links ?? []).filter {
            if case .known(.contact) = $0.role { return true }
            return false
        }
    }

    var reportingLinks: [OME.Link] {
        (links ?? []).filter {
            if case .known(.reporting) = $0.role { return true }
            return false
        }
    }
}
