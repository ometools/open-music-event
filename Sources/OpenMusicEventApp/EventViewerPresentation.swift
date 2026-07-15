import SwiftUI

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
            #if os(macOS) && !SKIP
            if let item {
                presentedContent(item)
            } else {
                base
            }
            #else
            base
                .fullScreenCover(item: presentationBinding) { item in
                    presentedContent(item)
                }
            #endif
        }
        .onAppear {
            hasAppeared = true
        }
    }

    private var presentationBinding: Binding<Item?> {
        guard launchAnimation == .disabled, !hasAppeared else {
            return $item
        }

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        return $item.transaction(transaction)
    }
}
