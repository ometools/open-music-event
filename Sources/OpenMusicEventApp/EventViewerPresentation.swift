#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

enum EventViewerPresentationLaunchAnimation {
    case automatic
    case disabled
}

private struct EventViewerPresentationLaunchAnimationKey: EnvironmentKey {
    static let defaultValue: EventViewerPresentationLaunchAnimation = .automatic
}

extension EnvironmentValues {
    var eventViewerPresentationLaunchAnimation: EventViewerPresentationLaunchAnimation {
        get { self[EventViewerPresentationLaunchAnimationKey.self] }
        set { self[EventViewerPresentationLaunchAnimationKey.self] = newValue }
    }
}

public extension View {
    func openMusicEventViewerPresentation<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        modifier(
            OpenMusicEventViewerPresentation(
                item: item,
                content: content
            )
        )
    }
}

struct OpenMusicEventViewerPresentation<
    Item: Identifiable,
    PresentedContent: View
>: ViewModifier {
    @Environment(\.eventViewerPresentationLaunchAnimation) var launchAnimation
    @Binding var item: Item?
    let presentedContent: (Item) -> PresentedContent
    @State var hasAppeared = false

    init(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> PresentedContent
    ) {
        self._item = item
        self.presentedContent = content
    }

    func body(content base: Content) -> some View {
        Group {
            #if os(Android) || (os(macOS) && !SKIP)
            if let item {
                presentedContent(item)
            } else {
                base
            }
            #else
            if hasAppeared {
                base
                    .fullScreenCover(item: presentationBinding) { item in
                        presentedContent(item)
                    }
            } else if let item {
                presentedContent(item)
            } else {
                base
            }
            #endif
        }
        .onAppear {
            hasAppeared = true
        }
    }

    #if os(Android) && SKIP_BRIDGE
    // Skip's native bridge currently drops the ViewModifier `content:` label.
    // Keep the protocol requirement above and provide the generated call shape.
    func body(_ base: Content) -> some View {
        body(content: base)
    }
    #endif

    private var presentationBinding: Binding<Item?> {
        guard launchAnimation == .disabled, !hasAppeared else {
            return $item
        }

        #if os(Android) && SKIP_BRIDGE
        return $item
        #else
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        return $item.transaction(transaction)
        #endif
    }
}
