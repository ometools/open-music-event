import ComposableArchitecture2
import OpenMusicEventLexicon

/// Requests that the application replace its provider subscriptions after a channel preference changes.
public struct NotificationSubscriptionsRefreshRequested: FeatureEventKey {
    public init() {}
}

extension Social.Category.NotificationState {
    var menuTitle: String {
        switch self {
        case .subscribed:
            "Subscribed"
        case .unsubscribed:
            "Unsubscribed"
        }
    }

    var systemImage: String {
        switch self {
        case .subscribed:
            "bell.fill"
        case .unsubscribed:
            "bell.slash"
        }
    }
}
