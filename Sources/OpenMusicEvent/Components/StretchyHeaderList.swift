//
//  StretchyHeaderList.swift
//  event-viewer
//
//  Created by Woodrow Melling on 2/21/25.
//

import SwiftUI
import SkipFuse


struct StretchyHeaderList<StretchyContent: View, ListContent: View>: View {

    init(
        title: Text,
        @ViewBuilder stretchyContent: () -> StretchyContent,
        @ViewBuilder listContent: () -> ListContent

    ) {
        self.stretchyContent = stretchyContent()
        self.titleContent = title
        self.listContent = listContent()
    }

    var titleContent: Text
    var stretchyContent: StretchyContent
    var listContent: ListContent

    #if os(iOS) || os(macOS)
//    @Environment(\.stretchFactor)
    var stretchFactor: CGFloat = 400
    @State var offset: CGFloat = .zero
    @State var titleVisibility = false


    var scale: CGFloat {
        let trueScale = (-offset / stretchFactor) + 1

        return if trueScale >= 1 {
            trueScale
        } else {
            pow(trueScale, 1/5)
        }
    }

    var showNavigationBar: Bool {
        offset > 0
    }

    var showTitleInNavigationBar: Bool {
        offset > 10
    }

    /*@Environment(\.showingStretchListDebugInformation)*/
    var showingStretchListDebugInformation = false

    #if os(iOS) || os(Android)
    var headerContentHeight: CGFloat = UIScreen.main.bounds.width
    var headerContentWidth: CGFloat = UIScreen.main.bounds.width
    #elseif os(macOS)
    var headerContentHeight: CGFloat = 0 // Untested
    var headerContentWidth: CGFloat = 0 // Untested
    #endif


    var body: some View {
        if #available(iOS 18.0, *) {
            bodyContent
                .onScrollGeometryChange(for: CGFloat.self) {
                    $0.contentOffset.y + $0.contentInsets.top
                } action: { _, newValue in
                    offset = newValue
                }
        } else {
            bodyContent
        }
    }

    @ViewBuilder
    var bodyContent: some View {
        List {
            self.stretchyContent
                .scaledToFill()

                .overlay { topDimOverlay }
                .scaleEffect(scale, anchor: .bottom) // For stretching
                .listRowInsets(EdgeInsets()) // Remove side + bottom padding from row
                .ignoresSafeArea()
                .frame(width: headerContentWidth, height: headerContentHeight, alignment: .center) // Set content height
                .listRowSeparator(.hidden, edges: .top) // Remove the top separator
//                // The image can can be bigger then the bounds. clip it, but give it plenty of vertical size so that it can never go off the top of the screen
                .clipShape(ScaledShape(shape: Rectangle(), scale: .init(width: 1, height: 2), anchor: .bottom))
                .overlay(alignment: .bottomLeading) {
                    StretchyHeaderListTitleView(titleContent: self.titleContent)
                }

            if showingStretchListDebugInformation {
                Section {
                    Text("offset: \(offset)")
                    Text("scale: \(scale)")
                    Text("ScrollVisibility")
                }
            }

            listContent

        }
        .ignoresSafeArea(.all, edges: .top)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #elseif os(Android)
        .toolbar(.hidden)
        #endif
        .navigationTitle(showNavigationBar ? self.titleContent : Text(""))
        .toolbarBackground(showNavigationBar ? .visible : .hidden)
        .animation(.default, value: self.showNavigationBar)
        .background(.background)
    }

    @Environment(\.colorScheme) var colorScheme
    var mainColor: Color  {
        switch colorScheme {
        case .dark: .black
        case .light: .white
        @unknown default: .black
        }
    }
    private var topDimOverlay: some View {
        let shadowColor = mainColor

        // Adjust the height/opacity to taste:
        return LinearGradient(
            gradient: Gradient(colors: [
                shadowColor,
                shadowColor.opacity(0.1),
                shadowColor
            ]),
            startPoint: .leading,
            endPoint: .trailing
        )
//        .frame(height: 120) // How tall the shadow region is
        .opacity(dimOpacity(for: offset))
    }

    private func dimOpacity(for offset: CGFloat) -> CGFloat {
        // If offset is 0 or negative, we’re pulling down,
        // so we can keep the shadow at 0% opacity.
        guard offset > 0 else { return 0 }

        // Example logic: fade from 0 → 1 as offset goes 0 → 150
        let maxOffset: CGFloat = 100
        let clippedOffset = min(offset, maxOffset)
        return clippedOffset / maxOffset
    }



    #elseif os(Android)
    var body: some View {
        List {
            stretchyContent
                .ignoresSafeArea(.all, edges: [.leading, .trailing])
//                .aspectRatio(1, contentMode: .fill)
                .overlay(alignment: .bottomLeading) {
                    StretchyHeaderListTitleView(titleContent: titleContent)
                }

            listContent
        }
        .ignoresSafeArea(.all, edges: .top)
//        .navigationTitle(titleContent)
        .navigationBarTitleDisplayMode(.inline)
    }
    #else

#endif
}

#if SKIP
import SkipFuse
#endif

struct StretchyHeaderListTitleView: View {
    var titleContent: Text

    @Environment(\.colorScheme) var colorScheme
    var mainColor: Color  {
        switch colorScheme {
        case .dark: .black
        case .light: .white
        @unknown default: .black
        }
    }

    var body: some View {
        self.titleContent
            .shadow(color: Color.black.opacity(0.5), radius: 5, x: 0.5, y: 2)
            .font(.largeTitle)
            .fontDesign(.default)
//            #if !SKIP
//            .safeAreaPadding()
//            #endif
            .opacity(0.9)
            .padding(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                LinearGradient(
                    colors: [mainColor, .clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
            }

    }
}
//
//#if os(iOS)
//#Preview {
//    StretchyHeaderList(title: Text("Blobs Your Uncle")) {
//        if #available(iOS 18.0, *) {
//            AnimatedMeshView()
//                .frame(width: 500)
//        } else {
//            // Fallback on earlier versions
//        }
//    } listContent: {
//        Text("Hello, World!")
//    }
//    .listStyle(.plain)
//}
//
//#Preview {
//    StretchyHeaderList(title: Text("Blobs Your Uncle")) {
//        if #available(iOS 18.0, *) {
//            AnimatedMeshView()
//                .frame(height: 1000)
//        } else {
//            // Fallback on earlier versions
//        }
//    } listContent: {
//        Text("Hello, World!")
//    }
//    .listStyle(.plain)
//}
//#endif
