//
//  OMEContextMenu.swift
//  open-music-event
//
//  Context menu component that works on both iOS and Android
//

import SwiftUI
#if os(Android)
import SkipFuse
#endif

public struct OMEContextMenu<Content: View, MenuContent: View>: View {
    private let content: Content
    private let menuContent: MenuContent
    let primaryAction: () -> Void

    public init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder menuContent: () -> MenuContent,
        primaryAction: @escaping () -> Void
    ) {
        self.content = content()
        self.menuContent = menuContent()
        self.primaryAction = primaryAction
    }
    
    public var body: some View {
        #if os(Android)
        AndroidContextMenu(content: content, menuContent: menuContent, primaryAction: primaryAction)
        #else
        DarwinContextMenu(content: content, menuContent: menuContent, primaryAction: primaryAction)
        #endif
    }
}

#if !os(Android)
internal struct DarwinContextMenu<Content: View, MenuContent: View>: View {
    let content: Content
    let menuContent: MenuContent
    let primaryAction: () -> Void

    var body: some View {
        content
            .onTapGesture {
                primaryAction()
            }
            .contextMenu {
                menuContent
            }
    }
}
#endif

#if os(Android)
internal struct AndroidContextMenu<Content: View, MenuContent: View>: View {
    let content: Content
    let menuContent: MenuContent
    let primaryAction: () -> Void
    @State var showingContextMenu = false
    @State var isPressed = false

    var body: some View {
        Menu {
            self
                .frame(height: 60)

            menuContent
        } label: {
            content
        } primaryAction: {
            primaryAction()
        }

//        ZStack {
//            content
//                .scaleEffect(isPressed ? 0.97 : 1.0)
//                .opacity(isPressed ? 0.8 : 1.0)
//                .animation(.easeInOut(duration: 0.1), value: isPressed)
//                .onLongPressGesture(
//                    minimumDuration: 0.5,
//                    maximumDistance: 10,
//                    perform: {
//                        showingContextMenu = true
//                    },
//                    onPressingChanged: { pressing in
//                        isPressed = pressing
//                    }
//                )
//
//            Group {
//                if showingContextMenu {
//                    VStack(spacing: 8) {
//                        content
//                            .cornerRadius(12)
//
//                        List {
//                            Text("Press me!")
//                        }
//                        .cornerRadius(12)
//                    }
//                    .shadow(radius: 8)
//                    .padding(.horizontal, 20)
//                    .transition(.scale.combined(with: .opacity))
//                }
//            }
//            .animation(.easeInOut(duration: 0.2), value: showingContextMenu)
//        }
    }
}
#endif

// MARK: - Convenience Extensions

extension View {
    public func omeContextMenu<MenuContent: View>(
        @ViewBuilder _ menuContent: @escaping () -> MenuContent,
        primaryAction: @escaping () -> Void = {}
    ) -> some View {
        OMEContextMenu(
            content: { self },
            menuContent: {
                menuContent()
            },
            primaryAction: primaryAction
        )
    }
}

struct LabeledMenuButton: View {
    init(
        title: String,
        label: String,
        systemImage: Image,
        action: @escaping () -> Void,

    ) {
        self.title = title
        self.action = action
        self.label = label
        self.systemImage = systemImage
    }

    var action: () -> Void
    var label: String
    var title: String
    var systemImage: Image

    var body: some View {
        Button(action: action) {
            #if os(Android)
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                    Text(label)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()

                systemImage
            }
            #else
            Label {
                Text(title)
            } icon: {
                systemImage
            }
            Text(label)
            #endif
        }
        #if os(Android)
        .buttonStyle(.plain)
        #endif
    }
}
