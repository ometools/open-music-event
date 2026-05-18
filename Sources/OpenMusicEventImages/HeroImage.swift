import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SwiftUI

public struct HeroImage<Placeholder: View>: View {
    let title: Text
    let asset: OME.ImageAsset?
    let cacheContext: LocalImageCacheContext?
    let tint: Color
    @ViewBuilder var placeholder: () -> Placeholder

    public init(
        title: Text,
        asset: OME.ImageAsset?,
        cacheContext: LocalImageCacheContext?,
        tint: Color = .accentColor,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.title = title
        self.asset = asset
        self.cacheContext = cacheContext
        self.tint = tint
        self.placeholder = placeholder
    }

    public var body: some View {
        ImageAssetAsyncImage(
            asset: asset,
            cacheContext: cacheContext,
            contentMode: .fill
        ) {
            HeroImageFallback(tint: tint) {
                placeholder()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay(alignment: .bottomLeading) {
            HeroImageTitle(title: title)
        }
    }
}

public struct HeroImageList<HeroContent: View, ListContent: View>: View {
    let title: Text
    let heroContent: HeroContent
    let listContent: ListContent

    @State var scrollOffset: CGFloat = .zero
    let stretchFactor: CGFloat = 400
    let coordinateSpaceName = "HeroImageListScroll"

    public init(
        title: Text,
        @ViewBuilder hero: () -> HeroContent,
        @ViewBuilder content: () -> ListContent
    ) {
        self.title = title
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
            List {
                heroRow(height: heroHeight(for: geometry.size.width))

                listContent
            }
            .listStyle(.plain)
            .coordinateSpace(name: coordinateSpaceName)
            .onPreferenceChange(HeroImageOffsetPreferenceKey.self) { minY in
                scrollOffset = -minY
            }
            .ignoresSafeArea(.all, edges: .top)
            .navigationTitle(showNavigationTitle ? title : Text(""))
            .toolbarBackground(showNavigationChrome ? .visible : .hidden)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .animation(.default, value: showNavigationChrome)
        }
        #endif
    }

    private func heroRow(height: CGFloat) -> some View {
        heroContent
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(HeroImageOffsetReader(coordinateSpaceName: coordinateSpaceName))
            .overlay {
                topChromeOverlay
            }
            .scaleEffect(heroScale, anchor: .bottom)
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

    private var heroScale: CGFloat {
        let trueScale = (-scrollOffset / stretchFactor) + 1
        if trueScale >= 1 {
            return trueScale
        } else {
            return pow(max(trueScale, 0.01), 1 / 5)
        }
    }

    private var showNavigationChrome: Bool {
        scrollOffset > 0
    }

    private var showNavigationTitle: Bool {
        scrollOffset > 10
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

struct HeroImageTitle: View {
    let title: Text
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        title
            .font(.largeTitle)
            .fontWeight(.bold)
            .lineLimit(2)
            #if os(iOS)
            .minimumScaleFactor(0.72)
            #endif
            .shadow(color: .black.opacity(0.5), radius: 5, x: 0.5, y: 2)
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
