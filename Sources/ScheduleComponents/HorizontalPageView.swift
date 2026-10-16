#if os(Android) || SKIP_BRIDGE
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

// SKIP INSERT: import skip.ui.*

public struct HorizontalPageView<Content: View, ID: Hashable>: View {
    @Binding var page: ID?
    let content: Content

    public init(
        page: Binding<ID?>,
        @ViewBuilder content: () -> Content
    ) {
        self._page = page
        self.content = content()
    }

    public var body: some View {
        #if (os(iOS) || os(macOS)) && !SKIP_BRIDGE
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                content
                    .containerRelativeFrame(.horizontal)
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $page.animation(.default))
        .scrollIndicators(.never, axes: .horizontal)
        #else
        TabView(selection: $page) {
            content
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        #endif
    }
}
