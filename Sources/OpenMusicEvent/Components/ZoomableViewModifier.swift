
let maxAllowedScale = 4.0
import SwiftUI
import SkipFuse

extension View {
    func _zoomable() -> some View {
        #if os(Android)
        self.zoom()
        #else
        ZoomableContainer { self }
        #endif
    }
}


#if SKIP
import me.saket.telephoto.zoomable.__
import androidx.compose.ui.Modifier
import androidx.compose.runtime.Composable



//struct ZoomableViewModifier : ContentModifier {
//    func modify(view: any View) -> any View {
//        view.composeModifier {
//            $0.zoomable(rememberZoomableState())
//        }
//    }
//}
#endif

extension View {
    public func zoom() -> some View {
        #if SKIP
        return ModifiedContent(content: self, modifier: RenderModifier { renderable, context in
            let modifier = context.modifier.zoomable(rememberZoomableState())
            let contentContext = context.content()
            renderable.Render(context: contentContext.with(modifier: modifier))
        })
        #else
        return self
        #endif
    }
}

#if canImport(UIKit)
struct ZoomableContainer<Content: View>: View {

    let content: Content

    @State var currentScale: CGFloat = 1.0
    @State var tapLocation: CGPoint = .zero

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func doubleTapAction(location: CGPoint) {
        tapLocation = location
        currentScale = currentScale == 1.0 ? maxAllowedScale : 1.0
    }

    var body: some View {
        ZoomableScrollView(scale: $currentScale, tapLocation: $tapLocation) {
            content
        }
        .onTapGesture(count: 2, perform: doubleTapAction)
    }

    fileprivate struct ZoomableScrollView: UIViewRepresentable {
        private var content: Content
        @Binding var currentScale: CGFloat
        @Binding var tapLocation: CGPoint

        init(scale: Binding<CGFloat>, tapLocation: Binding<CGPoint>, @ViewBuilder content: () -> Content) {
            _currentScale = scale
            _tapLocation = tapLocation
            self.content = content()
        }

        func makeUIView(context: Context) -> UIScrollView {
            // Setup the UIScrollView
            let scrollView = UIScrollView()
            scrollView.delegate = context.coordinator // for viewForZooming(in:)
            scrollView.maximumZoomScale = maxAllowedScale
            scrollView.minimumZoomScale = 1
            scrollView.bouncesZoom = true
            scrollView.showsHorizontalScrollIndicator = false
            scrollView.showsVerticalScrollIndicator = false
            scrollView.clipsToBounds = false

            // Create a UIHostingController to hold our SwiftUI content
            let hostedView = context.coordinator.hostingController.view!
            hostedView.translatesAutoresizingMaskIntoConstraints = true
            hostedView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            hostedView.frame = scrollView.bounds
            scrollView.addSubview(hostedView)

            return scrollView
        }

        func makeCoordinator() -> Coordinator {
            return Coordinator(hostingController: UIHostingController(rootView: content), scale: $currentScale)
        }

        func updateUIView(_ uiView: UIScrollView, context: Context) {
            // Update the hosting controller's SwiftUI content
            context.coordinator.hostingController.rootView = content

            if uiView.zoomScale > uiView.minimumZoomScale { // Scale out
                uiView.setZoomScale(currentScale, animated: true)
            } else if tapLocation != .zero { // Scale in to a specific point
                uiView.zoom(to: zoomRect(for: uiView, scale: uiView.maximumZoomScale, center: tapLocation), animated: true)
                // Reset the location to prevent scaling to it in case of a negative scale (manual pinch)
                // Use the main thread to prevent unexpected behavior
                DispatchQueue.main.async { tapLocation = .zero }
            }

            assert(context.coordinator.hostingController.view.superview == uiView)
        }

        // MARK: - Utils

        func zoomRect(for scrollView: UIScrollView, scale: CGFloat, center: CGPoint) -> CGRect {
            let scrollViewSize = scrollView.bounds.size

            let width = scrollViewSize.width / scale
            let height = scrollViewSize.height / scale
            let x = center.x - (width / 2.0)
            let y = center.y - (height / 2.0)

            return CGRect(x: x, y: y, width: width, height: height)
        }

        // MARK: - Coordinator
        class Coordinator: NSObject, UIScrollViewDelegate {
            var hostingController: UIHostingController<Content>
            @Binding var currentScale: CGFloat

            init(hostingController: UIHostingController<Content>, scale: Binding<CGFloat>) {
                self.hostingController = hostingController
                _currentScale = scale
            }

            func viewForZooming(in scrollView: UIScrollView) -> UIView? {
                return hostingController.view
            }

            func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
                currentScale = scale
            }
        }
    }
}

#endif
