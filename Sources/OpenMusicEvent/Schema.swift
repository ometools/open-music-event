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
