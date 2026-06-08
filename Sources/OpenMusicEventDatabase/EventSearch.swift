import OpenMusicEventLexicon
import SQLiteData

@Table("eventSearchDocuments")
public struct EventSearchDocument: Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Equatable, Hashable, Sendable, SQLiteType {
        case channel
        case contact
        case contributor
        case eventInfo
        case feature
        case location
        case performance
        case poster
        case stage
    }

    public enum Target: Codable, Equatable, Hashable, Sendable {
        case channel(OME.ID<OME.Channel>)
        case contributor(OME.ID<OME.Contributor>)
        case feature(String)
        case performance(OME.ID<OME.Performance>)
        case poster(OME.ID<OME.Poster>)
        case stage(OME.ID<OME.Stage>)
    }

    public init(
        id: Int64,
        stableID: String,
        organizerID: OME.Organizer.ID,
        eventID: OME.ID<OME.Event>,
        kind: Kind,
        title: String,
        subtitle: String? = nil,
        body: String? = nil,
        keywords: String = "",
        target: Target,
        baseRank: Int = 0
    ) {
        self.id = id
        self.stableID = stableID
        self.organizerID = organizerID
        self.eventID = eventID
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.keywords = keywords
        self.target = target
        self.baseRank = baseRank
    }

    @Column(primaryKey: true)
    public var id: Int64
    public var stableID: String
    public var organizerID: OME.Organizer.ID
    public var eventID: OME.ID<OME.Event>
    public var kind: Kind
    public var title: String
    public var subtitle: String?
    public var body: String?
    public var keywords: String
    @Column(as: Target.JSONRepresentation.self)
    public var target: Target
    public var baseRank: Int

    public var eventRecordID: OME.Event.ID {
        OME.Event.ID(organizerID: organizerID, eventID: eventID)
    }
}

@Table("eventSearchText")
public struct EventSearchText: Equatable, FTS5, Identifiable, Sendable {
    public init(
        rowid: Int64,
        title: String,
        keywords: String,
        subtitle: String,
        body: String
    ) {
        self.rowid = rowid
        self.title = title
        self.keywords = keywords
        self.subtitle = subtitle
        self.body = body
    }

    @Column(primaryKey: true)
    public let rowid: Int64
    public var id: Int64 { rowid }

    public var title: String
    public var keywords: String
    public var subtitle: String
    public var body: String
}
