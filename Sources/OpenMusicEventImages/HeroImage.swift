import OpenMusicEventDatabase
import OpenMusicEventLexicon
#if os(Android) || SKIP_BRIDGE
import SkipSwiftUI
#else
import SwiftUI
#endif

public struct HeroImage<Placeholder: View, ChromeTrailingContent: View>: View {
    let title: Text
    let sources: [HeroImageSource]
    let titleSources: [HeroImageTitleSource]
    let tint: Color
    @ViewBuilder var placeholder: () -> Placeholder
    @ViewBuilder var chromeTrailingContent: () -> ChromeTrailingContent
    @State var bottomChromeHeight: CGFloat = 148

    public init(
        title: Text,
        sources: [HeroImageSource],
        titleSources: [HeroImageTitleSource],
        tint: Color = .accentColor,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) where ChromeTrailingContent == EmptyView {
        self.title = title
        self.sources = sources
        self.titleSources = titleSources
        self.tint = tint
        self.placeholder = placeholder
        self.chromeTrailingContent = { EmptyView() }
    }

    public init(
        title: Text,
        sources: [HeroImageSource],
        titleSources: [HeroImageTitleSource],
        tint: Color = .accentColor,
        @ViewBuilder placeholder: @escaping () -> Placeholder,
        @ViewBuilder chromeTrailingContent: @escaping () -> ChromeTrailingContent
    ) {
        self.title = title
        self.sources = sources
        self.titleSources = titleSources
        self.tint = tint
        self.placeholder = placeholder
        self.chromeTrailingContent = chromeTrailingContent
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
    ) where ChromeTrailingContent == EmptyView {
        self.init(
            title: title,
            asset: asset,
            cacheContext: cacheContext,
            logoAsset: logoAsset,
            logoCacheContext: logoCacheContext,
            titleSources: titleSources,
            tint: tint,
            placeholder: placeholder,
            chromeTrailingContent: { EmptyView() }
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
        @ViewBuilder chromeTrailingContent: @escaping () -> ChromeTrailingContent
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
        self.chromeTrailingContent = chromeTrailingContent
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
                    chromeTrailingContent: chromeTrailingContent
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

struct HeroImageBottomChrome<ChromeTrailingContent: View>: View {
    let title: Text
    let titleSources: [HeroImageTitleSource]
    let tint: Color
    @ViewBuilder var chromeTrailingContent: () -> ChromeTrailingContent
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            HeroImageTitleSourceChain(
                title: title,
                sources: titleSources[...]
            )

            .frame(maxWidth: .infinity, alignment: .leading)

            chromeTrailingContent()
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
                let logoSize = CGSize(width: 164, height: 72)
                ImageAssetAsyncImage(
                    image: image,
                    contentMode: .fit,
                    renderedImageSize: logoSize
                ) { reason in
                    switch reason {
                    case .loading:
                        Color.clear
                            .frame(
                                width: logoSize.width,
                                height: logoSize.height,
                                alignment: .leading
                            )
                    case .failure, .unavailable:
                        nextSource
                    }
                }
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
