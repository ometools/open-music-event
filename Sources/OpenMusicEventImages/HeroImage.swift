import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SwiftUI

public struct HeroImage<Placeholder: View>: View {
    let title: Text
    let asset: OME.ImageAsset?
    let cacheContext: LocalImageCacheContext?
    let logoAsset: OME.ImageAsset?
    let logoCacheContext: LocalImageCacheContext?
    let tint: Color
    @ViewBuilder var placeholder: () -> Placeholder

    public init(
        title: Text,
        asset: OME.ImageAsset?,
        cacheContext: LocalImageCacheContext?,
        logoAsset: OME.ImageAsset? = nil,
        logoCacheContext: LocalImageCacheContext? = nil,
        tint: Color = .accentColor,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.title = title
        self.asset = asset
        self.cacheContext = cacheContext
        self.logoAsset = logoAsset
        self.logoCacheContext = logoCacheContext ?? cacheContext
        self.tint = tint
        self.placeholder = placeholder
    }

    public var body: some View {
        GeometryReader { geometry in
            ImageAssetAsyncImage(
                asset: asset,
                cacheContext: cacheContext,
                contentMode: .fill
            ) {
                HeroImageFallback(tint: tint) {
                    placeholder()
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                HeroImageBottomChrome(
                    title: title,
                    logoAsset: logoAsset,
                    logoCacheContext: logoCacheContext,
                    tint: tint
                )
                .frame(width: geometry.size.width, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

public struct HeroImageList<HeroContent: View, ListContent: View>: View {
    let title: Text
    let showsNavigationTitleBeforeScroll: Bool
    let heroContent: HeroContent
    let listContent: ListContent

    @State var scrollOffset: CGFloat = .zero
    let coordinateSpaceName = "HeroImageListScroll"

    public init(
        title: Text,
        showsNavigationTitleBeforeScroll: Bool = false,
        @ViewBuilder hero: () -> HeroContent,
        @ViewBuilder content: () -> ListContent
    ) {
        self.title = title
        self.showsNavigationTitleBeforeScroll = showsNavigationTitleBeforeScroll
        self.heroContent = hero()
        self.listContent = content()
    }

    public var body: some View {
        #if os(Android)
        List {
            heroContent
                .frame(maxWidth: .infinity)
                .frame(height: 320)
                .listRowInsets(EdgeInsets())

            listContent
        }
        .navigationTitle(title)
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
        .navigationTitle(shouldShowNavigationTitle ? title : Text(""))
        .toolbarBackground(showNavigationChrome ? .visible : .hidden)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .animation(.default, value: showNavigationChrome)
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

struct HeroImageBottomChrome: View {
    let title: Text
    let logoAsset: OME.ImageAsset?
    let logoCacheContext: LocalImageCacheContext?
    let tint: Color
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack {
            if let logoAsset {
                ImageAssetAsyncImage(
                    asset: logoAsset,
                    cacheContext: logoCacheContext,
                    contentMode: .fit
                ) {
                    HeroImageName(title: title)
                }
                .frame(width: 164, height: 72, alignment: .leading)
                .accessibilityLabel(title)
            } else {
                HeroImageName(title: title)
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
