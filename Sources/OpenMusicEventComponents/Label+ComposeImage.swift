#if os(Android) || canImport(SwiftUI)
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

public struct MappedSystemImage: View {
    let systemName: String

    public init(systemName: String) {
        self.systemName = systemName
    }

    public var body: some View {
        #if os(Android)
        ComposeView {
            MaterialSystemImageComposer(systemName: systemName)
        }
        #else
        Image(systemName: systemName)
            .resizable()
            .scaledToFit()
        #endif
    }
}

#if os(Android)
public struct MappedSystemLabelIcon: View {
    let systemName: String

    public var body: some View {
        MappedSystemImage(systemName: systemName)
            .frame(width: 24, height: 24)
    }
}

public extension Label where Title == Text, Icon == MappedSystemLabelIcon {
    init(_ titleKey: LocalizedStringKey, mappedSystemImage systemName: String) {
        self.init {
            Text(titleKey)
        } icon: {
            MappedSystemLabelIcon(systemName: systemName)
        }
    }

    @_disfavoredOverload
    init<S>(_ title: S, mappedSystemImage systemName: String) where S: StringProtocol {
        self.init {
            Text(title)
        } icon: {
            MappedSystemLabelIcon(systemName: systemName)
        }
    }
}
#else
public extension Label where Title == Text, Icon == Image {
    init(_ titleKey: LocalizedStringKey, mappedSystemImage systemName: String) {
        self.init {
            Text(titleKey)
        } icon: {
            Image(systemName: systemName)
        }
    }

    @_disfavoredOverload
    init<S>(_ title: S, mappedSystemImage systemName: String) where S: StringProtocol {
        self.init {
            Text(title)
        } icon: {
            Image(systemName: systemName)
        }
    }
}
#endif

#if SKIP
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.__
import androidx.compose.material.icons.outlined.__
import androidx.compose.material3.Icon
import androidx.compose.ui.graphics.vector.ImageVector

struct MaterialSystemImageComposer: ContentComposer {
    let systemName: String

    @Composable func Compose(context: ComposeContext) {
        let imageVector: ImageVector
        switch systemName {
        case "arrow.triangle.turn.up.right.diamond":
            imageVector = Icons.Outlined.Directions
        case "bubble.left.and.bubble.right":
            imageVector = Icons.Outlined.Forum
        case "calendar":
            imageVector = Icons.Outlined.DateRange
        case "calendar.day.timeline.leading":
            imageVector = Icons.Outlined.ViewTimeline
        case "ellipsis":
            imageVector = Icons.Outlined.MoreHoriz
        case "figure.mind.and.body":
            imageVector = Icons.Outlined.SelfImprovement
        case "info.circle":
            imageVector = Icons.Outlined.Info
        case "list.bullet":
            imageVector = Icons.Outlined.FormatListBulleted
        case "magnifyingglass":
            imageVector = Icons.Outlined.Search
        case "map":
            imageVector = Icons.Outlined.Map
        case "mappin.and.ellipse":
            imageVector = Icons.Outlined.PinDrop
        case "megaphone":
            imageVector = Icons.Outlined.Campaign
        case "music.note", "music.mic":
            imageVector = Icons.Outlined.MusicNote
        case "music.note.list":
            imageVector = Icons.Outlined.QueueMusic
        case "person", "person.3":
            imageVector = Icons.Outlined.Groups
        case "phone":
            imageVector = Icons.Outlined.Phone
        case "photo.on.rectangle":
            imageVector = Icons.Outlined.PhotoLibrary
        case "rectangle.split.1x2":
            imageVector = Icons.Outlined.ViewWeek
        case "rectangle.split.3x1":
            imageVector = Icons.Outlined.ViewColumn
        case "square.grid.2x2":
            imageVector = Icons.Outlined.GridView
        case "tag":
            imageVector = Icons.Outlined.Sell
        case "tray.full":
            imageVector = Icons.Outlined.Inventory2
        case "bell":
            imageVector = Icons.Outlined.Notifications
        case "bell.badge":
            imageVector = Icons.Outlined.NotificationImportant
        case "bell.fill":
            imageVector = Icons.Filled.Notifications
        case "bell.slash":
            imageVector = Icons.Outlined.NotificationsOff
        case "checkmark":
            imageVector = Icons.Outlined.Check
        case "gearshape":
            imageVector = Icons.Outlined.Settings
        case "square.and.pencil":
            imageVector = Icons.Outlined.Edit
        default:
            imageVector = Icons.Outlined.Warning
        }

        Icon(
            imageVector: imageVector,
            contentDescription: nil,
            modifier: context.modifier
        )
    }
}
#endif
#endif
