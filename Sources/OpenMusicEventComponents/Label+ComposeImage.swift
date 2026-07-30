#if os(Android) || canImport(SwiftUI)
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

public extension Image {
    init(system: String, material: String) {
        #if os(Android)
        if let assetName = Self.materialAssetName(for: material) {
            self = Image(assetName, bundle: .module).renderingMode(.template)
        } else {
            self.init(systemName: material)
        }
        #else
        self.init(systemName: system)
        #endif
    }

    private static func materialAssetName(for name: String) -> String? {
        switch name {
        case "Icons.Outlined.Campaign": "MaterialCampaign"
        case "Icons.Outlined.Directions": "MaterialDirections"
        case "Icons.Outlined.FormatListBulleted": "MaterialFormatListBulleted"
        case "Icons.Outlined.Forum": "MaterialForum"
        case "Icons.Outlined.GridView": "MaterialGridView"
        case "Icons.Outlined.Groups": "MaterialGroups"
        case "Icons.Outlined.Inventory2": "MaterialInventory2"
        case "Icons.Outlined.Map": "MaterialMap"
        case "Icons.Outlined.MusicNote": "MaterialMusicNote"
        case "Icons.Outlined.PhotoLibrary": "MaterialPhotoLibrary"
        case "Icons.Outlined.PinDrop": "MaterialPinDrop"
        case "Icons.Outlined.QueueMusic": "MaterialQueueMusic"
        case "Icons.Outlined.SelfImprovement": "MaterialSelfImprovement"
        case "Icons.Outlined.Sell": "MaterialSell"
        case "Icons.Outlined.ViewColumn": "MaterialViewColumn"
        case "Icons.Outlined.ViewTimeline": "MaterialViewTimeline"
        default: nil
        }
    }
}

#if os(Android)
public struct ComposeLabelIcon: View {
    let systemImage: String
    let composeImage: String

    public var body: some View {
        Image(system: systemImage, material: composeImage)
            .resizable()
            .scaledToFit()
            .frame(width: 24, height: 24)
    }
}

public extension Label where Title == Text, Icon == ComposeLabelIcon {
    init(
        _ titleKey: LocalizedStringKey,
        systemImage: String,
        composeImage: String
    ) {
        self.init {
            Text(titleKey)
        } icon: {
            ComposeLabelIcon(
                systemImage: systemImage,
                composeImage: composeImage
            )
        }
    }

    @_disfavoredOverload
    init<S>(
        _ title: S,
        systemImage: String,
        composeImage: String
    ) where S: StringProtocol {
        self.init {
            Text(title)
        } icon: {
            ComposeLabelIcon(
                systemImage: systemImage,
                composeImage: composeImage
            )
        }
    }
}
#else
public extension Label where Title == Text, Icon == Image {
    init(
        _ titleKey: LocalizedStringKey,
        systemImage: String,
        composeImage: String
    ) {
        self.init {
            Text(titleKey)
        } icon: {
            Image(system: systemImage, material: composeImage)
        }
    }

    @_disfavoredOverload
    init<S>(
        _ title: S,
        systemImage: String,
        composeImage: String
    ) where S: StringProtocol {
        self.init {
            Text(title)
        } icon: {
            Image(system: systemImage, material: composeImage)
        }
    }
}
#endif
#endif
