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
    @State var intrinsicImageSize: CGSize?
    @State var committedMagnification: CGFloat = 1
    @GestureState var gestureMagnification: CGFloat = 1

    public init(store: StoreOf<SiteMapViewer>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if let event = store.event,
                let asset = event.images?.imageAsset(role: .siteMap) {
                GeometryReader { geometry in
                    let availableSize = CGSize(
                        width: max(geometry.size.width - 32, 1),
                        height: max(geometry.size.height - 32, 1)
                    )
                    let fittedSize = fittedImageSize(in: availableSize)
                    let magnification = max(
                        1,
                        committedMagnification * gestureMagnification
                    )

                    ScrollView([.vertical, .horizontal]) {
                        ImageAssetAsyncImage(
                            asset: asset,
                            cacheContext: .init(eventID: event.id),
                            contentMode: .fit,
                            onIntrinsicSizeLoaded: { size in
                                intrinsicImageSize = size
                            }
                        ) {
                            SiteMapPlaceholderView(eventWasLoaded: true)
                        }
                        .frame(
                            width: fittedSize.width * magnification,
                            height: fittedSize.height * magnification
                        )
                        .frame(
                            minWidth: availableSize.width,
                            minHeight: availableSize.height
                        )
                        .padding(16)
                        .gesture(
                            MagnifyGesture()
                                .updating($gestureMagnification) { value, state, _ in
                                    state = value.magnification
                                }
                                .onEnded { value in
                                    committedMagnification = max(
                                        1,
                                        committedMagnification * value.magnification
                                    )
                                }
                        )
                    }
                }
                .background(.background)
                .navigationTitle("Site Map")
            } else {
                SiteMapPlaceholderView(eventWasLoaded: store.event != nil)
            }
        }
    }

    func fittedImageSize(in availableSize: CGSize) -> CGSize {
        guard let intrinsicImageSize,
              intrinsicImageSize.width > 0,
              intrinsicImageSize.height > 0 else {
            return availableSize
        }

        let scale = min(
            availableSize.width / intrinsicImageSize.width,
            availableSize.height / intrinsicImageSize.height
        )
        return CGSize(
            width: intrinsicImageSize.width * scale,
            height: intrinsicImageSize.height * scale
        )
    }
}

struct SiteMapPlaceholderView: View {
    let eventWasLoaded: Bool

    var body: some View {
        ViewerPlaceholderView(
            title: "Site Map",
            systemImage: "map",
            description: eventWasLoaded
                ? "No site map has been added to this event yet."
                : "This event could not be loaded."
        )
    }
}
