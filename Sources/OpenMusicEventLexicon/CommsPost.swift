import Foundation
import SQLiteData
import Tagged

@Table("commsPosts")
public struct CommsPost: Codable, Equatable, Sendable, Identifiable {
    public enum PostIDTag {}
    public typealias PostID = Tagged<PostIDTag, String>

    @Selection public struct ID: Codable, Hashable, Sendable {
        public init(
            organizerID: OME.Organizer.ID,
            eventID: OME.ID<OME.Event>,
            channelID: OME.ID<OME.Channel>,
            postID: CommsPost.PostID
        ) {
            self.organizerID = organizerID
            self.eventID = eventID
            self.channelID = channelID
            self.postID = postID
        }

        public var organizerID: OME.Organizer.ID
        public var eventID: OME.ID<OME.Event>
        public var channelID: OME.ID<OME.Channel>
        public var postID: CommsPost.PostID
    }

    public init(
        id: ID,
        title: String,
        contents: String,
        headerImageURL: URL? = nil,
        images: [OME.ImageAsset]? = nil,
        timestamp: Date? = nil,
        isPinned: Bool = false,
        delivery: OME.Announcement.Delivery = .standard,
        sortIndex: Int
    ) {
        self.id = id
        self.title = title
        self.contents = contents
        self.headerImageURL = headerImageURL
        self.images = images
        self.timestamp = timestamp
        self.isPinned = isPinned
        self.delivery = delivery
        self.sortIndex = sortIndex
    }

    public var id: ID
    public var title: String
    public var contents: String
    public var headerImageURL: URL?
    public var timestamp: Date?
    public var isPinned: Bool
    public var delivery: OME.Announcement.Delivery
    public var sortIndex: Int
    @Column(as: [OME.ImageAsset].JSONRepresentation?.self)
    public var images: [OME.ImageAsset]?

    public var channelRecordID: OME.Channel.ID {
        OME.Channel.ID(
            organizerID: id.organizerID,
            eventID: id.eventID,
            channelID: id.channelID
        )
    }
}
