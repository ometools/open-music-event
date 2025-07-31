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
        public var name: String
        public var description: String
        public var iconImageURL: URL?
        public var headerImageURL: URL?
        public var sortIndex: Int?
        public var defaultNotificationState: CommunicationChannel.NotificationState?
        public var userNotificationState: CommunicationChannel.NotificationState?

        public init(
            id: CommunicationChannel.ID? = nil,
            musicEventID: MusicEvent.ID? = nil,
            name: String,
            description: String,
            iconImageURL: URL? = nil,
            headerImageURL: URL? = nil,
            sortIndex: Int? = nil,
            defaultNotificationState: CommunicationChannel.NotificationState? = nil,
            userNotificationState: CommunicationChannel.NotificationState? = nil
        ) {
            self.id = id
            self.musicEventID = musicEventID
            self.name = name
            self.description = description
            self.iconImageURL = iconImageURL
            self.headerImageURL = headerImageURL
            self.sortIndex = sortIndex
            self.defaultNotificationState = defaultNotificationState
            self.userNotificationState = userNotificationState
        }
    }
}

extension CommunicationChannel.Yaml {
    public func toDraft() -> CommunicationChannel.Draft {
        return CommunicationChannel.Draft(
            id: self.id,
            musicEventID: self.musicEventID,
            name: self.name,
            description: self.description,
            iconImageURL: self.iconImageURL,
            headerImageURL: self.headerImageURL,
            sortIndex: self.sortIndex,
            defaultNotificationState: self.defaultNotificationState ?? .unsubscribed,
            userNotificationState: self.userNotificationState ?? .unsubscribed
        )
    }
}

extension CommunicationChannel.Draft {
    public func toYaml() -> CommunicationChannel.Yaml {
        return CommunicationChannel.Yaml(
            id: self.id,
            musicEventID: self.musicEventID,
            name: self.name,
            description: self.description,
            iconImageURL: self.iconImageURL,
            headerImageURL: self.headerImageURL,
            sortIndex: self.sortIndex,
            defaultNotificationState: self.defaultNotificationState,
            userNotificationState: self.userNotificationState
        )
    }
}