import OpenMusicEventLexicon
import ComposableArchitecture2
import OpenMusicEventComponents
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
        public let eventID: Event.ID
        @FetchOne public var event: Event?
        public var selectedStyleID: String?
        public var destination: Destination.State?

        public init(eventID: Event.ID) {
            self.eventID = eventID
            _event = FetchOne(Event.where { $0.id.eq(eventID) })
        }

        public var siteMap: Event.SiteMap? {
            event?.siteMap
        }

        public var selectedAsset: DisplayImageAsset? {
            selectedStyle?.image.displayImageAsset(recordID: eventID)
        }

        public var selectedStyle: Event.SiteMap.Style? {
            if let selectedStyleID,
               let style = siteMap?.styles.first(where: { $0.id == selectedStyleID }) {
                return style
            }
            return siteMap?.defaultStyle
        }

        public var selectedStyleIdentity: String {
            selectedStyle?.id ?? "no-site-map"
        }

        public var showsStyleSwitcher: Bool {
            (siteMap?.styles.count ?? 0) > 1
        }

        public var featureTitle: String {
            showsStyleSwitcher ? "Site Maps" : "Site Map"
        }
    }

    public enum Action {
        case styleButtonTapped(String)
        case editButtonTapped
        case destination(Destination.Action)
    }

    @Feature
    public enum Destination {
        case editSiteMap(EditSiteMap)
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case let .styleButtonTapped(styleID):
                guard state.siteMap?.styles.contains(where: { $0.id == styleID }) == true else {
                    return
                }
                state.selectedStyleID = styleID
            case .editButtonTapped:
                guard let event = state.event else { return }
                state.destination = .editSiteMap(EditSiteMap.State(event: event))
            case .destination:
                break
            }
        }
        .ifLet(\.destination) {
            Destination.body
        }
    }
}

public struct SiteMapViewerView: View {
    @Bindable var store: StoreOf<SiteMapViewer>
    let showsAuthoringControls: Bool

    public init(store: StoreOf<SiteMapViewer>, showsAuthoringControls: Bool = false) {
        self.store = store
        self.showsAuthoringControls = showsAuthoringControls
    }

    public var body: some View {
        Group {
            if store.event != nil, let asset = store.selectedAsset {
                #if os(Android)
                AndroidSiteMapZoomView(
                    asset: asset,
                    styleIdentity: store.selectedStyleIdentity
                )
                #else
                SwiftUISiteMapZoomView(
                    asset: asset,
                    styleIdentity: store.selectedStyleIdentity
                )
                    .id(store.selectedStyleIdentity)
                #endif
            } else if store.event != nil {
                SiteMapPlaceholderView()
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.background)
        .navigationTitle(store.siteMap?.title ?? "Site Map")
        .toolbar {
            if showsAuthoringControls {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        store.send(.editButtonTapped)
                    } label: {
                        Label("Edit Site Map", systemImage: "pencil")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(store.event == nil)
                }
            }
            if store.showsStyleSwitcher {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ForEach(store.siteMap?.styles ?? []) { style in
                            Button {
                                store.send(.styleButtonTapped(style.id))
                            } label: {
                                HStack {
                                    Text(style.title)
                                    if style.id == store.selectedStyle?.id {
                                        MappedSystemImage(systemName: "checkmark")
                                            .frame(width: 18, height: 18)
                                    }
                                }
                            }
                            .accessibilityIdentifier(
                                "button.site-map-style.\(style.id)"
                            )
                        }
                    } label: {
                        MappedSystemImage(systemName: "layers")
                            .frame(width: 24, height: 24)
                    }
                    .accessibilityLabel(
                        Text(
                            "Map Style",
                            bundle: .module,
                            comment: "Accessibility label for the site map style menu"
                        )
                    )
                    .accessibilityIdentifier("site-map-style-switcher")
                }
            }
        }
        .accessibilityIdentifier(
            "view.site-map.\(store.eventID)"
        )
        .sheet(item: $store.scope(\.destination).editSiteMap) { editStore in
            NavigationStack {
                EditSiteMapView(store: editStore)
            }
        }
    }
}

#if os(Android)
struct AndroidSiteMapZoomView: View {
    let asset: DisplayImageAsset
    let styleIdentity: String
    @State var loadedStyleIdentity: String?

    var body: some View {
        ImageAssetAsyncImage(
            image: asset,
            contentMode: .fit,
            onIntrinsicSizeLoaded: { _ in
                loadedStyleIdentity = styleIdentity
            }
        ) { reason in
            SiteMapImagePlaceholderView(reason: reason)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if loadedStyleIdentity == styleIdentity {
                SiteMapLoadedAccessibilityMarker(styleIdentity: styleIdentity)
            }
        }
        .composeModifier {
            AndroidSiteMapZoomModifier(styleIdentity: styleIdentity)
        }
    }
}
#else
struct SwiftUISiteMapZoomView: View {
    let asset: DisplayImageAsset
    let styleIdentity: String
    @State var intrinsicImageSize: CGSize?
    @State var loadedStyleIdentity: String?
    @State var committedMagnification: CGFloat = 1
    @State var committedOffset: CGSize = .zero
    @GestureState var gestureState = SiteMapZoomGestureState()

    var body: some View {
        GeometryReader { geometry in
            let fittedSize = fittedImageSize(in: geometry.size)
            let magnification = max(
                1,
                committedMagnification * gestureState.magnification
            )
            let magnifiedOffset = anchoredOffset(
                committedOffset,
                from: committedMagnification,
                to: magnification,
                anchor: gestureState.anchor,
                viewportSize: geometry.size
            )
            let offset = clampedOffset(
                CGSize(
                    width: magnifiedOffset.width + gestureState.translation.width,
                    height: magnifiedOffset.height + gestureState.translation.height
                ),
                magnification: magnification,
                fittedSize: fittedSize,
                viewportSize: geometry.size
            )

            ImageAssetAsyncImage(
                image: asset,
                contentMode: .fit,
                onIntrinsicSizeLoaded: { size in
                    intrinsicImageSize = size
                    loadedStyleIdentity = styleIdentity
                }
            ) { reason in
                SiteMapImagePlaceholderView(reason: reason)
            }
            .frame(width: fittedSize.width, height: fittedSize.height)
            .scaleEffect(magnification)
            .offset(offset)
            .gesture(
                MagnifyGesture()
                    .simultaneously(with: DragGesture())
                    .updating($gestureState) { value, state, _ in
                        if let magnification = value.first {
                            state.magnification = magnification.magnification
                            state.anchor = magnification.startAnchor
                            state.translation = .zero
                        } else if let drag = value.second {
                            state.translation = drag.translation
                        }
                    }
                    .onEnded { value in
                        let magnification = max(
                            1,
                            committedMagnification
                                * (value.first?.magnification ?? 1)
                        )
                        let magnifiedOffset = anchoredOffset(
                            committedOffset,
                            from: committedMagnification,
                            to: magnification,
                            anchor: value.first?.startAnchor ?? .center,
                            viewportSize: geometry.size
                        )
                        let translation = value.first == nil
                            ? value.second?.translation ?? .zero
                            : .zero
                        committedMagnification = magnification
                        committedOffset = clampedOffset(
                            CGSize(
                                width: magnifiedOffset.width + translation.width,
                                height: magnifiedOffset.height + translation.height
                            ),
                            magnification: magnification,
                            fittedSize: fittedSize,
                            viewportSize: geometry.size
                        )
                    }
            )
            .overlay {
                if loadedStyleIdentity == styleIdentity {
                    SiteMapLoadedAccessibilityMarker(styleIdentity: styleIdentity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    func anchoredOffset(
        _ offset: CGSize,
        from oldMagnification: CGFloat,
        to newMagnification: CGFloat,
        anchor: UnitPoint,
        viewportSize: CGSize
    ) -> CGSize {
        let magnificationChange = newMagnification / oldMagnification
        let anchorOffset = CGSize(
            width: (anchor.x - 0.5) * viewportSize.width,
            height: (anchor.y - 0.5) * viewportSize.height
        )
        return CGSize(
            width: offset.width * magnificationChange
                + anchorOffset.width * (1 - magnificationChange),
            height: offset.height * magnificationChange
                + anchorOffset.height * (1 - magnificationChange)
        )
    }

    func clampedOffset(
        _ offset: CGSize,
        magnification: CGFloat,
        fittedSize: CGSize,
        viewportSize: CGSize
    ) -> CGSize {
        let maximumX = max(
            (fittedSize.width * magnification - viewportSize.width) / 2,
            0
        )
        let maximumY = max(
            (fittedSize.height * magnification - viewportSize.height) / 2,
            0
        )
        return CGSize(
            width: min(max(offset.width, -maximumX), maximumX),
            height: min(max(offset.height, -maximumY), maximumY)
        )
    }
}

struct SiteMapZoomGestureState {
    var magnification: CGFloat = 1
    var anchor: UnitPoint = .center
    var translation: CGSize = .zero
}
#endif

#if SKIP
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.unit.IntSize

struct AndroidSiteMapZoomModifier: ContentModifier {
    let styleIdentity: String

    func modify(view: any View) -> any View {
        ComposeView { context in
            let size = remember(styleIdentity) { mutableStateOf(IntSize.Zero) }
            let magnification = remember(styleIdentity) { mutableStateOf(Float(1.0)) }
            let translationX = remember(styleIdentity) { mutableStateOf(Float(0.0)) }
            let translationY = remember(styleIdentity) { mutableStateOf(Float(0.0)) }

            Box(
                modifier: context.modifier
                    .clipToBounds()
                    .onSizeChanged { size.value = $0 }
                    .pointerInput(styleIdentity) {
                        detectTransformGestures(
                            panZoomLock: true,
                            onGesture: { centroid, pan, zoom, _ in
                                let oldMagnification = magnification.value
                                let newMagnification = max(
                                    Float(1.0),
                                    oldMagnification * zoom
                                )
                                let magnificationChange =
                                    newMagnification / oldMagnification
                                let width = Float(size.value.width)
                                let height = Float(size.value.height)
                                let maximumX = max(
                                    (width * newMagnification - width) / 2,
                                    Float(0.0)
                                )
                                let maximumY = max(
                                    (height * newMagnification - height) / 2,
                                    Float(0.0)
                                )
                                let proposedX = translationX.value
                                    * magnificationChange
                                    + (centroid.x - width / 2)
                                    * (1 - magnificationChange)
                                    + pan.x
                                let proposedY = translationY.value
                                    * magnificationChange
                                    + (centroid.y - height / 2)
                                    * (1 - magnificationChange)
                                    + pan.y

                                magnification.value = newMagnification
                                translationX.value = min(
                                    max(proposedX, -maximumX),
                                    maximumX
                                )
                                translationY.value = min(
                                    max(proposedY, -maximumY),
                                    maximumY
                                )
                            }
                        )
                    }
            ) {
                view.Compose(
                    context: context.content(
                        modifier: Modifier
                            .fillMaxSize()
                            .graphicsLayer(
                                scaleX: magnification.value,
                                scaleY: magnification.value,
                                translationX: translationX.value,
                                translationY: translationY.value,
                                transformOrigin: TransformOrigin(
                                    pivotFractionX: Float(0.5),
                                    pivotFractionY: Float(0.5)
                                )
                            )
                    )
                )
            }
        }
    }
}
#endif

struct SiteMapLoadedAccessibilityMarker: View {
    let styleIdentity: String

    var body: some View {
        // The marker appears only after the shared image loader has decoded the
        // selected map. UI automation can therefore distinguish a real map from
        // the loading and failure placeholders without changing the visual UI.
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityLabel("Loaded Site Map")
            .accessibilityIdentifier("image.site-map.\(styleIdentity)")
    }
}

struct SiteMapPlaceholderView: View {
    var body: some View {
        ViewerPlaceholderView(
            title: "Site Map",
            systemImage: "map",
            description: "No site map has been added to this event yet."
        )
    }
}

struct SiteMapImagePlaceholderView: View {
    let reason: ImageAssetPlaceholderReason

    @ViewBuilder
    var body: some View {
        switch reason {
        case .loading:
            ProgressView()
        case .failure, .unavailable:
            ViewerPlaceholderView(
                title: "Site Map",
                systemImage: "map",
                description: "This site map could not be loaded."
            )
        }
    }
}
