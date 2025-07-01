//
//  ContentUnavailableView.swift
//  open-music-event
//
//  Created by Woodrow Melling on 7/1/25.
//

import SkipFuse
import SwiftUI

#if os(Android)
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
public struct ContentUnavailableView<LabelX, Description, Actions> : View where LabelX : View, Description : View, Actions : View {

    /// Creates an interface, consisting of a label and additional content, that you
    /// display when the content of your app is unavailable to users.
    ///
    /// - Parameters:
    ///   - label: The label that describes the view.
    ///   - description: The view that describes the interface.
    ///   - actions: The content of the interface actions.
    public init(
        @ViewBuilder label: () -> LabelX,
        @ViewBuilder description: () -> Description = { EmptyView() },
        @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) {
        self.label = label()
        self.description = description()
        self.actions = actions()
    }

    var label: LabelX
    var description: Description
    var actions: Actions

    public var body: some View {
        VStack {
            label
            description
            actions
        }
    }
}
#endif
