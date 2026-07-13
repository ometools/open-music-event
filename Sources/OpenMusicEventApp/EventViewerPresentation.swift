import SwiftUI

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
    @State var presentsInitialItemDirectly: Bool

    init(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> PresentedContent
    ) {
        self._item = item
        self.presentedContent = content
        self._presentsInitialItemDirectly = State(initialValue: item.wrappedValue != nil)
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
            if presentsInitialItemDirectly, let item {
                presentedContent(item)
            } else {
                base
                    .fullScreenCover(item: $item) { item in
                        presentedContent(item)
                    }
            }
            #endif
        }
        .onChange(of: item == nil) { _, isNil in
            if isNil {
                presentsInitialItemDirectly = false
            }
        }
    }
}
