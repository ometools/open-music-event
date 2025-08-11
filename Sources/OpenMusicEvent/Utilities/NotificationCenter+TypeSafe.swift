import Foundation
import CoreModels

enum NotificationUserInfo {
    case viewArtist(artistID: Artist.ID)
    case viewPost(channelID: CommunicationChannel.ID, postID: CommunicationChannel.Post.Stub)
    case viewEvent(eventID: MusicEvent.ID)
}

extension NotificationCenter {
    func post(name: Notification.Name, object: Any? = nil, info: NotificationUserInfo) {
        post(name: name, object: object, userInfo: [Notification.InfoKey: info])
    }
}

extension Notification {
    fileprivate static let InfoKey = "InfoKey"
    var info: NotificationUserInfo? {
        return userInfo?[Self.InfoKey] as? NotificationUserInfo
    }
}

extension Notification.Name {
    static let userSelectedToViewArtist = Notification.Name("requestedToViewArtist")
    static let userSelectedToViewPost = Notification.Name("requestedToViewPost")
    static let userSelectedToViewEvent = Notification.Name("requestedToViewEvent")
    static let userRequestedToExitEvent = Notification.Name("requestedToExitEvent")
}
