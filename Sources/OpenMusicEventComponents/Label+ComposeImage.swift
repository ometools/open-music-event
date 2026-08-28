#if os(Android) || canImport(SwiftUI)
#if os(Android) || SKIP_BRIDGE
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
        #if os(Android) || SKIP_BRIDGE
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

#if os(Android) || SKIP_BRIDGE
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
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.unit.dp

struct MaterialSystemImageComposer: ContentComposer {
    let systemName: String

    @Composable func Compose(context: ComposeContext) {
        let imageVector: ImageVector
        switch systemName {
        case "arrow.up.right":
            imageVector = Icons.Outlined.OpenInNew
        case "arrow.triangle.turn.up.right.diamond":
            imageVector = Icons.Outlined.Directions
        case "bubble.left.and.bubble.right":
            imageVector = Icons.Outlined.Forum
        case "calendar":
            imageVector = Icons.Outlined.DateRange
        case "calendar.and.person":
            imageVector = ImageVector.Builder(
                name = "CalendarAccount",
                defaultWidth: Float(24).dp,
                defaultHeight: Float(24).dp,
                viewportWidth: Float(24),
                viewportHeight: Float(24)
            ).also { builder in
                builder.addPath(
                    pathData: PathParser().parsePathString(
                        "M19 3H18V1H16V3H8V1H6V3H5C3.9 3 3 3.9 3 5V19C3 20.11 3.9 21 5 21H19C20.11 21 21 20.11 21 19V5C21 3.9 20.11 3 19 3M19 19H5V9H19V19M19 7H5V5H19M12 10C14 10 15 12.42 13.59 13.84C12.17 15.26 9.75 14.25 9.75 12.25C9.75 11 10.75 10 12 10M16.5 17.88V18H7.5V17.88C7.5 16.63 9.5 15.63 12 15.63S16.5 16.63 16.5 17.88Z"
                    ).toNodes(),
                    fill: SolidColor(androidx.compose.ui.graphics.Color.Black),
                    fillAlpha: Float(1)
                )
            }.build()
        case "calendar.day.timeline.leading":
            imageVector = Icons.Outlined.ViewTimeline
        case "checkmark.circle", "checkmark-circle":
            imageVector = Icons.Outlined.CheckCircle
        case "exclamationmark.triangle":
            imageVector = Icons.Outlined.Warning
        case "ellipsis":
            imageVector = Icons.Outlined.MoreHoriz
        case "figure.mind.and.body":
            imageVector = Icons.Outlined.SelfImprovement
        case "folder":
            imageVector = Icons.Outlined.Folder
        case "hammer":
            imageVector = Icons.Outlined.Build
        case "info.circle":
            imageVector = Icons.Outlined.Info
        case "list.bullet":
            imageVector = Icons.Outlined.FormatListBulleted
        case "layers":
            imageVector = Icons.Outlined.Layers
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
        case "person", "person.crop.circle", "person.crop.square":
            imageVector = Icons.Outlined.Person
        case "person.3":
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
        case "slider.horizontal.3":
            imageVector = Icons.Outlined.Tune
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
        case "chevron.down":
            imageVector = Icons.Outlined.ExpandMore
        case "chevron.up":
            imageVector = Icons.Outlined.ExpandLess
        case "gearshape":
            imageVector = Icons.Outlined.Settings
        case "heart":
            imageVector = Icons.Outlined.FavoriteBorder
        case "heart.badge":
            imageVector = ImageVector.Builder(
                name = "HeartBadgePlus",
                defaultWidth: Float(24).dp,
                defaultHeight: Float(24).dp,
                viewportWidth: Float(24),
                viewportHeight: Float(24)
            ).also { builder in
                builder.addPath(
                    pathData: PathParser().parsePathString(
                        "M16.5 3C14.76 3 13.09 3.81 12 5.09C10.91 3.81 9.24 3 7.5 3C4.42 3 2 5.42 2 8.5C2 12.26 5.4 15.36 10.55 20.04L12 21.35L13.45 20.03C18.6 15.36 22 12.26 22 8.5C22 5.42 19.58 3 16.5 3M12.1 18.55L12 18.65L11.9 18.55C7.14 14.24 4 11.39 4 8.5C4 6.5 5.5 5 7.5 5C9.04 5 10.54 5.99 11.07 7.36H12.94C13.46 5.99 14.96 5 16.5 5C18.5 5 20 6.5 20 8.5C20 11.39 16.86 14.24 12.1 18.55Z"
                    ).toNodes(),
                    fill: SolidColor(androidx.compose.ui.graphics.Color.Black),
                    fillAlpha: Float(1)
                )
                builder.addPath(
                    pathData: PathParser().parsePathString(
                        "M19 0V3H16V5H19V8H21V5H24V3H21V0Z"
                    ).toNodes(),
                    fill: SolidColor(androidx.compose.ui.graphics.Color.Black),
                    fillAlpha: Float(1)
                )
            }.build()
        case "square.and.pencil":
            imageVector = Icons.Outlined.Edit
        default:
            imageVector = Icons.Outlined.Warning
        }

        // A raw Material Icon does not inherit SkipUI's foreground style.
        // Resolve it explicitly so mapped icons behave like SwiftUI Image.
        let tint = ForegroundStyle()
            .asColor(opacity: 1.0, animationContext: context)
            ?? Color.primary.asColor(opacity: 1.0, animationContext: context)
            ?? androidx.compose.material3.MaterialTheme.colorScheme.onSurface

        Icon(
            imageVector: imageVector,
            contentDescription: nil,
            modifier: context.modifier,
            tint: tint
        )
    }
}
#endif
#endif
