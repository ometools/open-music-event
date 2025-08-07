//
//  CommunicationChannel+Yaml.swift
//  OpenMusicEventParser
//
//  Created by Claude on 8/3/25.
//

import Foundation
import CoreModels

extension CommunicationChannel {
    public struct Yaml: Equatable, Sendable, Codable {
        public var id: CommunicationChannel.ID?
        public var musicEventID: MusicEvent.ID?
        public var firebaseTopicName: FirebaseTopicName?
        public var name: String
        public var description: String
        public var iconImageURL: URL?
        public var headerImageURL: URL?
        public var sortIndex: Int?
        public var defaultNotificationState: CommunicationChannel.DefaultNotificationState?
        public var userNotificationState: CommunicationChannel.UserNotificationState?
        public var notificationsRequired: Bool?

        public init(
            id: CommunicationChannel.ID? = nil,
            musicEventID: MusicEvent.ID? = nil,
            firebaseTopicName: FirebaseTopicName?,
            name: String,
            description: String,
            iconImageURL: URL? = nil,
            headerImageURL: URL? = nil,
            sortIndex: Int? = nil,
            defaultNotificationState: CommunicationChannel.DefaultNotificationState? = nil,
            userNotificationState: CommunicationChannel.UserNotificationState? = nil,
            notificationsRequired: Bool? = nil
        ) {
            self.id = id
            self.musicEventID = musicEventID
            self.firebaseTopicName = firebaseTopicName
            self.name = name
            self.description = description
            self.iconImageURL = iconImageURL
            self.headerImageURL = headerImageURL
            self.sortIndex = sortIndex
            self.defaultNotificationState = defaultNotificationState
            self.userNotificationState = userNotificationState
            self.notificationsRequired = notificationsRequired
        }
    }
}

extension CommunicationChannel.Yaml {
    public func toDraft() -> CommunicationChannel.Draft {
        return CommunicationChannel.Draft(
            id: self.id,
            musicEventID: self.musicEventID,
            firebaseTopicName: self.firebaseTopicName,
            name: self.name,
            description: self.description,
            iconImageURL: self.iconImageURL,
            headerImageURL: self.headerImageURL,
            sortIndex: self.sortIndex,
            defaultNotificationState: self.defaultNotificationState ?? .unsubscribed,
            userNotificationState: self.userNotificationState ?? .unsubscribed,
            notificationsRequired: self.notificationsRequired ?? false
        )
    }
}

extension CommunicationChannel.Draft {
    public func toYaml() -> CommunicationChannel.Yaml {
        return CommunicationChannel.Yaml(
            id: self.id,
            musicEventID: self.musicEventID,
            firebaseTopicName: self.firebaseTopicName,
            name: self.name,
            description: self.description,
            iconImageURL: self.iconImageURL,
            headerImageURL: self.headerImageURL,
            sortIndex: self.sortIndex,
            defaultNotificationState: self.defaultNotificationState,
            userNotificationState: self.userNotificationState,
            notificationsRequired: self.notificationsRequired
        )
    }
}
