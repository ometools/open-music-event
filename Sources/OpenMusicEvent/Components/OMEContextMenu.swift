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
    
    public init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder menuContent: () -> MenuContent
    ) {
        self.content = content()
        self.menuContent = menuContent()
    }
    
    public var body: some View {
        #if os(Android)
        AndroidContextMenu(content: content, menuContent: menuContent)
        #else
        DarwinContextMenu(content: content, menuContent: menuContent)
        #endif
    }
}

#if !os(Android)
internal struct DarwinContextMenu<Content: View, MenuContent: View>: View {
    let content: Content
    let menuContent: MenuContent
    
    var body: some View {
        content
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
            // noop for long press menu only
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
        @ViewBuilder _ menuContent: @escaping () -> MenuContent
    ) -> some View {
        OMEContextMenu(
            content: { self },
            menuContent: {

                menuContent()
            }
        )
    }
}

struct LabeledMenuButton: View {
    init(
        title: String,
        label: String,
        systemImage: String,
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
    var systemImage: String

    var body: some View {
        Button(action: action) {
            #if os(Android)
            HStack {
                Image(systemName: systemImage)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                    Text(label)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            #else
                Label(title, systemImage: systemImage)
                Text(label)
            #endif
        }
        #if os(Android)
        .buttonStyle(.plain)
        #endif
    }
}
