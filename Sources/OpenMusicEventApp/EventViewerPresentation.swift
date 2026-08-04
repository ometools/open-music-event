#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

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
    @Binding var item: Item?
    let presentedContent: (Item) -> PresentedContent

    init(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> PresentedContent
    ) {
        self._item = item
        self.presentedContent = content
    }

    func body(content base: Content) -> some View {
        ZStack {
            base
                .allowsHitTesting(item == nil)
                .accessibilityHidden(item != nil)

            if let item {
                presentedContent(item)
                    .transition(.move(edge: .bottom))
                    .zIndex(1)
            }
        }
        .animation(.default, value: item?.id)
    }

    #if os(Android) && SKIP_BRIDGE
    // Skip's native bridge currently drops the ViewModifier `content:` label.
    // Keep the protocol requirement above and provide the generated call shape.
    func body(_ base: Content) -> some View {
        body(content: base)
    }
    #endif
}
