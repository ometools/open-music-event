import SQLiteData
import Tagged

extension OpenMusicEvent.Event {
    @Table("eventSiteMaps")
    public struct SiteMap: Equatable, Identifiable, Sendable {
        @Selection
        public struct ID: Codable, Equatable, Hashable, Sendable {
            public init(
                organizerID: OME.Organizer.ID,
                eventID: OME.ID<OME.Event>
            ) {
                self.organizerID = organizerID
                self.eventID = eventID
            }

            public init(eventID: OME.Event.ID) {
                self.init(
                    organizerID: eventID.organizerID,
                    eventID: eventID.eventID
                )
            }

            public var organizerID: OME.Organizer.ID
            public var eventID: OME.ID<OME.Event>
        }

        public struct Style: Codable, Equatable, Identifiable, Sendable {
            public typealias ID = OME.ID<Style>

            public init(id: ID, title: String, image: OME.ImageAsset) {
                self.id = id
                self.title = title
                self.image = image
            }

            public var id: ID
            public var title: String
            public var image: OME.ImageAsset
        }

        public init(
            id: ID,
            title: String,
            defaultStyleID: Style.ID? = nil,
            styles: [Style]
        ) {
            self.id = id
            self.title = title
            self.defaultStyleID = defaultStyleID
            self.styles = styles
        }

        public var id: ID
        public var title: String
        public var defaultStyleID: Style.ID?
        @Column(as: [Style].JSONRepresentation.self)
        public var styles: [Style]

        public var defaultStyle: Style? {
            if let defaultStyleID,
               let style = styles.first(where: { $0.id == defaultStyleID }) {
                return style
            }
            return styles.first
        }
    }
}
