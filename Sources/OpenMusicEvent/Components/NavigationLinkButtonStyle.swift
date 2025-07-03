//
//  NavigationLinkButtonStyle.swift
//  open-music-event
//
//  Created by Woodrow Melling on 5/11/25.
//


//
//  File.swift
//  
//
//  Created by Woodrow Melling on 6/15/24.
//

import SwiftUI; import SkipFuse

public struct NavigationLinkButtonStyle: ButtonStyle {
    func background(_ configuration: Configuration) -> Color {
        #if os(iOS)
        configuration.isPressed ? Color(.tertiarySystemBackground) : Color.systemBackground
        #elseif os(Android)
        Color.systemBackground
        #endif
    }

    public func makeBody(configuration: Configuration) -> some View {
        #if os(iOS)
        HStack {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            Spacer()
            NavigationArrow()
        }

        .listRowBackground(background(configuration))
        .background(background(configuration))
        #elseif os(Android)
        configuration.label
        #endif


    }


    struct NavigationArrow: View {

        init() {}

        var height: CGFloat = 12
        var body: some View {
            #if os(iOS)
            Image(systemName: "chevron.forward")
                .resizable()
                .foregroundStyle(.tertiary)
                .aspectRatio(contentMode: .fit)
                .fontWeight(.bold)
                .frame(width: 6, height: self.height)

            #endif
        }
    }
}

// Need to do this instead of a ButtonStyle because you can't apply
// .listRowBackground inside of a ButtonStyle, and have it work in the view.
// 
struct NavigationLinkButton<Label: View>: View {

    var action: () -> Void
    var label: Label

    init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            HStack {
                label
                    .frame(maxWidth: .infinity, alignment: .leading)
                    #if os(iOS)
                    .contentShape(Rectangle())
                    #endif
                    .tint(.primary)
                #if os(iOS)
                Spacer()
                NavigationLinkButtonStyle.NavigationArrow()
                #endif
            }
            .frame(maxWidth: .infinity)
        }
    }
}

public extension ButtonStyle where Self == NavigationLinkButtonStyle {
    static var navigationLink: Self {
        NavigationLinkButtonStyle()
    }
}


//#Preview {
//    List {
//
//        NavigationLinkButton {
//            print("press")
//        } label: {
//            Text("Press me!")
//        }
////        .buttonStyle(.navigationLink)
//    }
//}
