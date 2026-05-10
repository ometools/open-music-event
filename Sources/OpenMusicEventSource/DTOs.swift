import Foundation
import Lexicon
import OpenMusicEventLexicon

public typealias OMERecord = OpenMusicEventLexicon.OpenMusicEvent

public struct EventDTO: Codable, Equatable, Sendable {
    public init(
        id: OMERecord.Event.ID?,
        name: String,
        description: String?,
        startDate: LocalDate?,
        endDate: LocalDate?,
        status: Open<OMERecord.Event.Status>?,
        mode: Open<OMERecord.Event.Mode>?,
        locations: [OMERecord.Event.Location]?,
        uris: [OMERecord.Event.EventURI]?,
        timeZone: TimeZone,
        imageURL: URL?,
        iconImageURL: URL?,
        siteMapImageURL: URL?,
        contactNumbers: [OMERecord.Event.ContactNumber]?,
        categoryConfigs: OMERecord.Event.CategoryConfigs?
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.startDate = startDate
        self.endDate = endDate
        self.status = status
        self.mode = mode
        self.locations = locations
        self.uris = uris
        self.timeZone = timeZone
        self.imageURL = imageURL
        self.iconImageURL = iconImageURL
        self.siteMapImageURL = siteMapImageURL
        self.contactNumbers = contactNumbers
        self.categoryConfigs = categoryConfigs
    }

    public init(_ draft: OMERecord.Event.Draft) {
        self.init(
            id: draft.id,
            name: draft.name,
            description: draft.description,
            startDate: draft.startDate,
            endDate: draft.endDate,
            status: draft.status,
            mode: draft.mode,
            locations: draft.locations,
            uris: draft.uris,
            timeZone: draft.timeZone,
            imageURL: draft.imageURL,
            iconImageURL: draft.iconImageURL,
            siteMapImageURL: draft.siteMapImageURL,
            contactNumbers: draft.contactNumbers,
            categoryConfigs: draft.categoryConfigs
        )
    }

    public var id: OMERecord.Event.ID?
    public var name: String
    public var description: String?
    public var startDate: LocalDate?
    public var endDate: LocalDate?
    public var status: Open<OMERecord.Event.Status>?
    public var mode: Open<OMERecord.Event.Mode>?
    public var locations: [OMERecord.Event.Location]?
    public var uris: [OMERecord.Event.EventURI]?
    @SourceTimeZone public var timeZone: TimeZone
    public var imageURL: URL?
    public var iconImageURL: URL?
    public var siteMapImageURL: URL?
    public var contactNumbers: [OMERecord.Event.ContactNumber]?
    public var categoryConfigs: OMERecord.Event.CategoryConfigs?

    public var recordDraft: OMERecord.Event.Draft {
        OMERecord.Event.Draft(
            id: id,
            name: name,
            description: description,
            startDate: startDate,
            endDate: endDate,
            status: status,
            mode: mode,
            locations: locations,
            uris: uris,
            timeZone: timeZone,
            imageURL: imageURL,
            iconImageURL: iconImageURL,
            siteMapImageURL: siteMapImageURL,
            contactNumbers: contactNumbers,
            categoryConfigs: categoryConfigs
        )
    }
}

public typealias StageDTO = OMERecord.Stage.Draft
public typealias ParticipantDTO = OMERecord.Participant.Draft
public typealias PosterDTO = OMERecord.Poster.Draft
public typealias ChannelDTO = OMERecord.Channel.Draft
