import ComposableArchitecture2
import OpenMusicEventDatabase
import OpenMusicEventImages
import SQLiteData
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

@Feature
public struct SiteMapViewer {
    public init() {}

    public struct State {
        public let eventID: OMERecord.Event.ID
        @FetchOne public var event: OMERecord.Event?

        public init(eventID: OMERecord.Event.ID) {
            self.eventID = eventID
            _event = FetchOne(OMERecord.Event.where { $0.id.eq(eventID) })
        }
    }

    public enum Action {}

    public var body: some Feature {
        Update { _, _ in }
    }
}

public struct SiteMapViewerView: View {
    let store: StoreOf<SiteMapViewer>

    public init(store: StoreOf<SiteMapViewer>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if let event = store.event,
                let asset = event.images?.imageAsset(role: .siteMap) {
                ScrollView([.vertical, .horizontal]) {
                    ImageAssetAsyncImage(
                        asset: asset,
                        cacheContext: .init(eventID: event.id),
                        contentMode: .fit
                    ) {
                        SiteMapPlaceholderView(eventWasLoaded: true)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .background(.background)
                .navigationTitle("Site Map")
            } else {
                SiteMapPlaceholderView(eventWasLoaded: store.event != nil)
            }
        }
    }
}

struct SiteMapPlaceholderView: View {
    let eventWasLoaded: Bool

    var body: some View {
        ViewerPlaceholderView(
            title: "Site Map",
            systemImage: "map",
            composeImage: "Icons.Outlined.Map",
            description: eventWasLoaded
                ? "No site map has been added to this event yet."
                : "This event could not be loaded."
        )
    }
}
