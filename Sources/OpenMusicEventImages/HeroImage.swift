import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SwiftUI

public struct HeroImage<Placeholder: View, Overlay: View>: View {
    let title: Text
    let sources: [HeroImageSource]
    let titleSources: [HeroImageTitleSource]
    let tint: Color
    @ViewBuilder var placeholder: () -> Placeholder
    @ViewBuilder var overlay: () -> Overlay
    @State var bottomChromeHeight: CGFloat = 148

    public init(
        title: Text,
        sources: [HeroImageSource],
        titleSources: [HeroImageTitleSource],
        tint: Color = .accentColor,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) where Overlay == EmptyView {
        self.title = title
        self.sources = sources
        self.titleSources = titleSources
        self.tint = tint
        self.placeholder = placeholder
        self.overlay = { EmptyView() }
    }

    public init(
        title: Text,
        sources: [HeroImageSource],
        titleSources: [HeroImageTitleSource],
        tint: Color = .accentColor,
        @ViewBuilder placeholder: @escaping () -> Placeholder,
        @ViewBuilder overlay: @escaping () -> Overlay
    ) {
        self.title = title
        self.sources = sources
        self.titleSources = titleSources
        self.tint = tint
        self.placeholder = placeholder
        self.overlay = overlay
    }

    public init(
        title: Text,
        asset: OME.ImageAsset?,
        cacheContext: LocalImageCacheContext?,
        logoAsset: OME.ImageAsset? = nil,
        logoCacheContext: LocalImageCacheContext? = nil,
        titleSources: [HeroImageTitleSource],
        tint: Color = .accentColor,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) where Overlay == EmptyView {
        self.init(
            title: title,
            asset: asset,
            cacheContext: cacheContext,
            logoAsset: logoAsset,
            logoCacheContext: logoCacheContext,
            titleSources: titleSources,
            tint: tint,
            placeholder: placeholder,
            overlay: { EmptyView() }
        )
    }

    public init(
        title: Text,
        asset: OME.ImageAsset?,
        cacheContext: LocalImageCacheContext?,
        logoAsset: OME.ImageAsset? = nil,
        logoCacheContext: LocalImageCacheContext? = nil,
        titleSources: [HeroImageTitleSource],
        tint: Color = .accentColor,
        @ViewBuilder placeholder: @escaping () -> Placeholder,
        @ViewBuilder overlay: @escaping () -> Overlay
    ) {
        let logoImage = logoAsset.map {
            DisplayImageAsset(asset: $0, cacheContext: logoCacheContext ?? cacheContext)
        }
        self.title = title
        self.sources = [
            asset.map {
                .primaryImage(DisplayImageAsset(asset: $0, cacheContext: cacheContext))
            },
            logoImage.map(HeroImageSource.logo),
        ].compactMap { $0 }
        self.titleSources = titleSources
        self.tint = tint
        self.placeholder = placeholder
        self.overlay = overlay
    }

    public var body: some View {
        GeometryReader { geometry in
            HeroImageBackground(
                sources: sources,
                tint: tint,
                focusSafeAreaInsets: focusSafeAreaInsets(for: geometry)
            ) {
                placeholder()
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                HeroImageBottomChrome(
                    title: title,
                    titleSources: titleSources,
                    tint: tint,
                    overlay: overlay
                )
                .frame(width: geometry.size.width, alignment: .leading)
                .background(HeroImageBottomChromeHeightReader())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onPreferenceChange(HeroImageBottomChromeHeightPreferenceKey.self) { height in
            if height > 0 {
                bottomChromeHeight = height
            }
        }
    }

    private func focusSafeAreaInsets(for geometry: GeometryProxy) -> EdgeInsets {
        EdgeInsets(
            top: geometry.safeAreaInsets.top + 72,
            leading: 0,
            bottom: bottomChromeHeight,
            trailing: 0
        )
    }
}

public struct HeroImageBackground<Placeholder: View>: View {
    let sources: [HeroImageSource]
    let tint: Color
    let focusSafeAreaInsets: EdgeInsets
    @ViewBuilder var placeholder: () -> Placeholder
    @Environment(\.heroImageRendering) var heroImageRendering

    public init(
        sources: [HeroImageSource],
        tint: Color = .accentColor,
        focusSafeAreaInsets: EdgeInsets = EdgeInsets(),
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.sources = sources
        self.tint = tint
        self.focusSafeAreaInsets = focusSafeAreaInsets
        self.placeholder = placeholder
    }

    public var body: some View {
        HeroImageSourceChain(
            sources: sources[...],
            rendering: heroImageRendering,
            tint: tint,
            focusSafeAreaInsets: focusSafeAreaInsets,
            placeholder: placeholder
        )
    }
}

public struct HeroImageList<HeroContent: View, ListContent: View>: View {
    let title: Text
    let showsNavigationTitleBeforeScroll: Bool
    let initialScrollID: AnyHashable?
    let heroContent: HeroContent
    let listContent: ListContent

    @State var scrollOffset: CGFloat = .zero
    let coordinateSpaceName = "HeroImageListScroll"

    public init(
        title: Text,
        showsNavigationTitleBeforeScroll: Bool = false,
        initialScrollID: AnyHashable? = nil,
        @ViewBuilder hero: () -> HeroContent,
        @ViewBuilder content: () -> ListContent
    ) {
        self.title = title
        self.showsNavigationTitleBeforeScroll = showsNavigationTitleBeforeScroll
        self.initialScrollID = initialScrollID
        self.heroContent = hero()
        self.listContent = content()
    }

    public var body: some View {
        #if os(Android)
        ScrollViewReader { proxy in
            List {
                heroContent
                    .frame(maxWidth: .infinity)
                    .frame(height: 320)
                    .listRowInsets(EdgeInsets())

                listContent
            }
            .navigationTitle(title)
            .onAppear {
                if let initialScrollID {
                    proxy.scrollTo(initialScrollID, anchor: .top)
                }
            }
            .onChange(of: initialScrollID) { _, newValue in
                if let newValue {
                    proxy.scrollTo(newValue, anchor: .top)
                }
            }
        }
        #else
        GeometryReader { geometry in
            scrollTrackedList(height: heroHeight(for: geometry.size.width))
        }
        #endif
    }

    @ViewBuilder
    private func scrollTrackedList(height: CGFloat) -> some View {
        #if os(iOS)
        if #available(iOS 18.0, *) {
            list(height: height)
                .onScrollGeometryChange(for: CGFloat.self) {
                    $0.contentOffset.y + $0.contentInsets.top
                } action: { _, newValue in
                    scrollOffset = newValue
                }
        } else {
            list(height: height)
        }
        #else
        list(height: height)
        #endif
    }

    private func list(height: CGFloat) -> some View {
        ScrollViewReader { proxy in
            List {
                heroRow(height: height)

                listContent
            }
            .listStyle(.plain)
            .coordinateSpace(name: coordinateSpaceName)
            .onPreferenceChange(HeroImageOffsetPreferenceKey.self) { minY in
                geometryOffsetChanged(minY)
            }
            .ignoresSafeArea(.all, edges: .top)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    inlineNavigationTitle
                }
            }
            .toolbarBackground(showNavigationChrome ? .visible : .hidden)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .animation(.default, value: showNavigationChrome)
            .animation(.default, value: shouldShowNavigationTitle)
            .onAppear {
                if let initialScrollID {
                    proxy.scrollTo(initialScrollID, anchor: .top)
                }
            }
            .onChange(of: initialScrollID) { _, newValue in
                if let newValue {
                    proxy.scrollTo(newValue, anchor: .top)
                }
            }
        }
    }

    private func heroRow(height: CGFloat) -> some View {
        heroContent
            .frame(maxWidth: .infinity)
            .frame(height: height + pullDistance)
            .overlay {
                topChromeOverlay
            }
            .frame(height: height, alignment: .bottom)
            .background(HeroImageOffsetReader(coordinateSpaceName: coordinateSpaceName))
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden, edges: .top)
            .ignoresSafeArea(.all, edges: .top)
            .clipShape(
                ScaledShape(
                    shape: Rectangle(),
                    scale: CGSize(width: 1, height: 2),
                    anchor: .bottom
                )
            )
    }

    private func heroHeight(for width: CGFloat) -> CGFloat {
        min(max(width, 280), 420)
    }

    private var pullDistance: CGFloat {
        max(0, -scrollOffset)
    }

    private var showNavigationChrome: Bool {
        scrollOffset > 0
    }

    private var showNavigationTitle: Bool {
        scrollOffset > 10
    }

    private var shouldShowNavigationTitle: Bool {
        showsNavigationTitleBeforeScroll || showNavigationTitle
    }

    private var inlineNavigationTitle: some View {
        title
            .font(.headline)
            .lineLimit(1)
            .opacity(shouldShowNavigationTitle ? 1 : 0)
            .accessibilityHidden(!shouldShowNavigationTitle)
    }

    @Environment(\.colorScheme) var colorScheme

    private var chromeColor: Color {
        switch colorScheme {
        case .dark:
            .black
        case .light:
            .white
        @unknown default:
            .black
        }
    }

    private var topChromeOverlay: some View {
        LinearGradient(
            colors: [
                chromeColor.opacity(0.85),
                chromeColor.opacity(0.28),
                .clear,
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .opacity(chromeOpacity)
    }

    private var chromeOpacity: CGFloat {
        guard scrollOffset > 0 else { return 0 }
        return min(scrollOffset, 100) / 100
    }

    private func geometryOffsetChanged(_ minY: CGFloat) {
        #if os(iOS)
        if #available(iOS 18.0, *) { return }
        #endif
        scrollOffset = -minY
    }
}

struct HeroImageSourceChain<Placeholder: View>: View {
    let sources: ArraySlice<HeroImageSource>
    let rendering: HeroImageRendering
    let tint: Color
    let focusSafeAreaInsets: EdgeInsets
    @ViewBuilder var placeholder: () -> Placeholder

    @ViewBuilder
    var body: some View {
        if let source = sources.first {
            switch rendering.renderer(for: source.kind) {
            case .fullBleedImage:
                ImageAssetAsyncImage(
                    image: source.image,
                    contentMode: .fill,
                    focusSafeAreaInsets: focusSafeAreaInsets
                ) {
                    HeroImageSourceChain(
                        sources: sources.dropFirst(),
                        rendering: rendering,
                        tint: tint,
                        focusSafeAreaInsets: focusSafeAreaInsets,
                        placeholder: placeholder
                    )
                }

            case .centeredLogo:
                HeroImageFallback(tint: tint) {
                    ImageAssetAsyncImage(
                        image: source.image,
                        contentMode: .fit
                    ) { reason in
                        switch reason {
                        case .loading:
                            Color.clear
                        case .failure, .unavailable:
                            centeredFallbackContent
                        }
                    }
                    .frame(maxWidth: 260, maxHeight: 160)
                    .padding(.horizontal, 48)
                    .padding(.vertical, 56)
                }
            }
        } else {
            HeroImageFallback(tint: tint) {
                placeholder()
            }
        }
    }

    @ViewBuilder
    private var centeredFallbackContent: some View {
        if sources.dropFirst().isEmpty {
            placeholder()
        } else {
            HeroImageSourceChain(
                sources: sources.dropFirst(),
                rendering: rendering,
                tint: tint,
                focusSafeAreaInsets: focusSafeAreaInsets,
                placeholder: placeholder
            )
        }
    }
}

struct HeroImageFallback<Content: View>: View {
    let tint: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Rectangle()
                .fill(tint.opacity(0.14))

            content()
                .foregroundStyle(tint)
                .opacity(0.86)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct HeroImageBottomChrome<Overlay: View>: View {
    let title: Text
    let titleSources: [HeroImageTitleSource]
    let tint: Color
    @ViewBuilder var overlay: () -> Overlay
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            overlay()

            HStack {
                HeroImageTitleSourceChain(
                    title: title,
                    sources: titleSources[...]
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 56)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            LinearGradient(
                colors: [.clear, chromeColor.opacity(0.86)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var chromeColor: Color {
        switch colorScheme {
        case .dark:
            .black
        case .light:
            .white
        @unknown default:
            .black
        }
    }
}

struct HeroImageTitleSourceChain: View {
    let title: Text
    let sources: ArraySlice<HeroImageTitleSource>

    @ViewBuilder
    var body: some View {
        if let source = sources.first {
            switch source {
            case let .logo(image):
                ImageAssetAsyncImage(
                    image: image,
                    contentMode: .fit
                ) { reason in
                    switch reason {
                    case .loading:
                        Color.clear
                    case .failure, .unavailable:
                        nextSource
                    }
                }
                .frame(width: 164, height: 72, alignment: .leading)
                .accessibilityLabel(title)

            case .title:
                HeroImageName(title: title)
            }
        } else {
            HeroImageName(title: title)
        }
    }

    @ViewBuilder
    private var nextSource: some View {
        HeroImageTitleSourceChain(
            title: title,
            sources: sources.dropFirst()
        )
    }
}

struct HeroImageName: View {
    let title: Text

    var body: some View {
        title
            .font(.largeTitle)
            .fontWeight(.bold)
            .lineLimit(2)
            #if os(iOS)
            .minimumScaleFactor(0.72)
            #endif
            .shadow(color: .black.opacity(0.5), radius: 5, x: 0.5, y: 2)
            .opacity(0.92)
    }
}

struct HeroImageOffsetReader: View {
    let coordinateSpaceName: String

    var body: some View {
        GeometryReader { geometry in
            Color.clear.preference(
                key: HeroImageOffsetPreferenceKey.self,
                value: geometry.frame(in: .named(coordinateSpaceName)).minY
            )
        }
    }
}

struct HeroImageOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct HeroImageBottomChromeHeightReader: View {
    var body: some View {
        GeometryReader { geometry in
            Color.clear.preference(
                key: HeroImageBottomChromeHeightPreferenceKey.self,
                value: geometry.size.height
            )
        }
    }
}

struct HeroImageBottomChromeHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
