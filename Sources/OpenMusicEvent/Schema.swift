//
//  Schema.swift
//  open-music-event
//
//  Created by Woodrow Melling on 8/20/25.
//


// MARK: Preferences Extensions
extension Artist {
    public struct Preferences: Identifiable, Equatable, Sendable, Codable {
        public var id: Artist.ID { artistID }
        public let artistID: Artist.ID
        public var isFavorite: Bool

        public static let tableName = "artistPreferences"

        public init(artistID: Artist.ID, isFavorite: Bool = false) {
            self.artistID = artistID
            self.isFavorite = isFavorite
        }
    }
}

extension Artist.Preferences.Draft: Sendable, Equatable, Codable {}

extension Performance {
    public struct Preferences: Identifiable, Equatable, Sendable, Codable {
        public var id: Performance.ID { performanceID }
        public let performanceID: Performance.ID
        public var seen: Bool

        public static let tableName = "performancePreferences"

        public init(performanceID: Performance.ID, seen: Bool = false) {
            self.performanceID = performanceID
            self.seen = seen
        }
    }
}


extension Performance.Preferences.Draft: Sendable, Equatable, Codable {}

extension CommunicationChannel {
    public struct Preferences: Identifiable, Equatable, Sendable, Codable {
        public var id: CommunicationChannel.ID { channelID }
        public let channelID: CommunicationChannel.ID
        public var userNotificationState: CommunicationChannel.UserNotificationState

        public static let tableName = "channelPreferences"

        public init(
            channelID: CommunicationChannel.ID,
            userNotificationState: CommunicationChannel.UserNotificationState
        ) {
            self.channelID = channelID
            self.userNotificationState = userNotificationState
        }
    }
}

extension CommunicationChannel.Preferences.Draft: Sendable, Equatable, Codable {}

extension CommunicationChannel.Post {
    public struct Preferences: Identifiable, Equatable, Sendable, Codable {
        public var id: CommunicationChannel.Post.ID { postID }
        public let postID: CommunicationChannel.Post.ID
        public var isRead: Bool
        public var isFavorite: Bool

        public static let tableName = "postPreferences"

        public init(postID: CommunicationChannel.Post.ID, isRead: Bool = false, isFavorite: Bool = false) {
            self.postID = postID
            self.isRead = isRead
            self.isFavorite = isFavorite
        }
    }
}

extension CommunicationChannel.Post.Preferences.Draft: Sendable, Equatable, Codable {}


extension Artist.Preferences {
    public struct Draft {
        public typealias PrimaryTable = Artist.Preferences


        public var id: Artist.ID {
            get { artistID }
            set { artistID = newValue }
        }
        public var artistID: Artist.ID
        public var isFavorite: Bool

        public static let tableName = Artist.Preferences.tableName

        public init(_ other: Artist.Preferences) {
            self.artistID = other.artistID
            self.isFavorite = other.isFavorite
        }

        public init(artistID: Artist.ID, isFavorite: Bool = false) {
            self.artistID = artistID
            self.isFavorite = isFavorite
        }
    }
}

extension Performance.Preferences {
    public struct Draft {
        public typealias PrimaryTable = Performance.Preferences
        public var id: Performance.ID {
            get { performanceID }
            set { performanceID = newValue }
        }
        public var performanceID: Performance.ID
        public var seen: Bool

        public static let tableName = Performance.Preferences.tableName

        public init(_ other: Performance.Preferences) {
            self.performanceID = other.performanceID
            self.seen = other.seen
        }

        public init(performanceID: Performance.ID, seen: Bool = false) {
            self.performanceID = performanceID
            self.seen = seen
        }
    }
}

extension CommunicationChannel.Preferences {
    public struct Draft {
        public typealias PrimaryTable = CommunicationChannel.Preferences

        public var id: CommunicationChannel.ID {
            get { channelID }
            set { channelID = newValue }
        }
        public var channelID: CommunicationChannel.ID
        public var userNotificationState: CommunicationChannel.UserNotificationState

        public static let tableName = CommunicationChannel.Preferences.tableName

        public init(_ other: CommunicationChannel.Preferences) {
            self.channelID = other.channelID
            self.userNotificationState = other.userNotificationState
        }

        public init(
            channelID: CommunicationChannel.ID,
            userNotificationState: CommunicationChannel.UserNotificationState
        ) {
            self.channelID = channelID
            self.userNotificationState = userNotificationState
        }
    }
}

extension CommunicationChannel.Post.Preferences {
    public struct Draft {
        public typealias PrimaryTable = CommunicationChannel.Post.Preferences

        public var id: CommunicationChannel.Post.ID {
            get { postID }
            set { postID = newValue }
        }
        public var postID: CommunicationChannel.Post.ID
        public var isRead: Bool
        public var isFavorite: Bool

        public static let tableName = CommunicationChannel.Post.Preferences.tableName

        public init(_ other: CommunicationChannel.Post.Preferences) {
            self.postID = other.postID
            self.isRead = other.isRead
            self.isFavorite = other.isFavorite
        }

        public init(postID: CommunicationChannel.Post.ID, isRead: Bool = false, isFavorite: Bool = false) {
            self.postID = postID
            self.isRead = isRead
            self.isFavorite = isFavorite
        }
    }
}
