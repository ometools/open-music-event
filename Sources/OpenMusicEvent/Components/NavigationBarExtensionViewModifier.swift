//
//  NavigationBarExtensionViewModifier.swift
//  OpenFestival
//
//  Created by Woodrow Melling on 1/5/25.
//

import SwiftUI
#if canImport(SkipFuse)
import SkipFuse
#endif

extension View {
    func navigationBarExtension<ExtensionContent: View>(
        dragsWithScroll: Bool = false,
        @ViewBuilder extensionContent: () -> ExtensionContent
    ) -> some View {
        self.modifier(
            NavigationBarExtensionViewModifier(
                dragsWithScroll: dragsWithScroll,
                extensionContent: extensionContent
            )
        )
    }
}

struct NavigationBarExtensionViewModifier<ExtensionContent: View>: ViewModifier {
    init(dragsWithScroll: Bool, @ViewBuilder extensionContent: () -> ExtensionContent) {
        self.dragsWithScroll = dragsWithScroll
        self.extensionContent = extensionContent()
    }

    var extensionContent: ExtensionContent
    var dragsWithScroll: Bool = false

    @State var yPosition: CGFloat = 0

    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            content.safeAreaBar(edge: .top) {
                extensionContent
            }
//            .scrollEdgeEffectStyle(.soft, for: .top)
        } else if #available(iOS 18.0, *) {

            innerBody(content: content)
                .onScrollGeometryChange(
                    for: CGFloat.self,
                    of: { geo in
                        let trueOffset = geo.contentOffset.y + geo.contentInsets.top
                        return if dragsWithScroll {
                            min(1, trueOffset)
                        } else {
                            min(1, max(0, trueOffset))
                        }
                    },
                    action: { oldValue, newValue in
                        yPosition = newValue
                    }
                )
        } else {
            innerBody(content: content)
        }
        #else
        innerBody(content: content)
        #endif
    }

    func body(_ content: Content) -> some View {
        return self.body(content: content)
    }

    func innerBody(content: Content) -> some View {
        #if os(Android)
        VStack {
            extensionContent
            content
        }
        .toolbarBackground(.hidden, for: .automatic)
        #else
        content.safeAreaInset(edge: .top) {
            if #available(iOS 26, *) {
                extensionContent
                
            } else {
                extensionContent
                    .frame(maxWidth: .infinity)
                    .background(Material.bar.opacity(min(1, max(0, yPosition))))
                    .offset(dragsWithScroll ? CGSize(width: 0, height: max(0, -yPosition)) : .zero)
            }
        }
        #if os(iOS)
        .toolbarBackground(.hidden, for: .navigationBar)
        #endif
        #endif

    }
}
