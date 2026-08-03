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
                Group {
                    #if os(Android)
                    AndroidSiteMapZoomView(asset: asset, eventID: event.id)
                    #else
                    SwiftUISiteMapZoomView(asset: asset, eventID: event.id)
                    #endif
                }
                .background(.background)
                .navigationTitle("Site Map")
            } else {
                SiteMapPlaceholderView(eventWasLoaded: store.event != nil)
            }
        }
    }
}

#if os(Android)
struct AndroidSiteMapZoomView: View {
    let asset: OME.ImageAsset
    let eventID: OMERecord.Event.ID

    var body: some View {
        GeometryReader { geometry in
            ImageAssetAsyncImage(
                asset: asset,
                cacheContext: .init(eventID: eventID),
                contentMode: .fit
            ) {
                SiteMapPlaceholderView(eventWasLoaded: true)
            }
            .frame(
                width: max(geometry.size.width - 32, 1),
                height: max(geometry.size.height - 32, 1)
            )
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .composeModifier {
                AndroidSiteMapZoomModifier()
            }
        }
    }
}
#else
struct SwiftUISiteMapZoomView: View {
    let asset: OME.ImageAsset
    let eventID: OMERecord.Event.ID
    @State var intrinsicImageSize: CGSize?
    @State var committedMagnification: CGFloat = 1
    @State var committedOffset: CGSize = .zero
    @GestureState var gestureState = SiteMapZoomGestureState()

    var body: some View {
        GeometryReader { geometry in
            let availableSize = CGSize(
                width: max(geometry.size.width - 32, 1),
                height: max(geometry.size.height - 32, 1)
            )
            let fittedSize = fittedImageSize(in: availableSize)
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

            ZStack {
                Color.clear
                ImageAssetAsyncImage(
                    asset: asset,
                    cacheContext: .init(eventID: eventID),
                    contentMode: .fit,
                    onIntrinsicSizeLoaded: { size in
                        intrinsicImageSize = size
                    }
                ) {
                    SiteMapPlaceholderView(eventWasLoaded: true)
                }
                .frame(width: fittedSize.width, height: fittedSize.height)
                .scaleEffect(magnification)
                .offset(offset)
            }
            .clipped()
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
    func modify(view: any View) -> any View {
        ComposeView { context in
            let size = remember { mutableStateOf(IntSize.Zero) }
            let magnification = remember { mutableStateOf(Float(1.0)) }
            let translationX = remember { mutableStateOf(Float(0.0)) }
            let translationY = remember { mutableStateOf(Float(0.0)) }

            Box(
                modifier: context.modifier
                    .clipToBounds()
                    .onSizeChanged { size.value = $0 }
                    .pointerInput(true) {
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
