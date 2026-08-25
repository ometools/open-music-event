#if os(Android) || ROBOLECTRIC || SKIP_BRIDGE
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

public struct NavigationLinkButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme
    let verticalPadding: CGFloat

    public init(verticalPadding: CGFloat = 0) {
        self.verticalPadding = verticalPadding
    }

    func background(_ configuration: Configuration) -> Color {
        #if os(iOS)
        configuration.isPressed ? Color(.tertiarySystemFill) : Color.clear
        #elseif os(Android) || ROBOLECTRIC || os(macOS)
        Color.clear
        #else
        Color.clear
        #endif
    }

    public func makeBody(configuration: Configuration) -> some View {
        #if os(iOS)
        HStack {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
                .tint(.primary)
            Spacer()
            NavigationArrow()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, verticalPadding)
        .contentShape(Rectangle())
        .background(background(configuration))
        .padding(.vertical, -verticalPadding)
        #elseif os(Android) || ROBOLECTRIC
        configuration.label
        #else
        configuration.label
        #endif
    }

    struct NavigationArrow: View {
        var height: CGFloat = 12

        var body: some View {
            #if os(iOS)
            Image(systemName: "chevron.forward")
                .resizable()
                .foregroundStyle(.tertiary)
                .aspectRatio(contentMode: .fit)
                .fontWeight(.bold)
                .frame(width: 6, height: self.height)
            #else
            EmptyView()
            #endif
        }
    }
}

public extension View {
    func navigationLinkListRowStyle() -> some View {
        #if os(Android) || ROBOLECTRIC
        self
        #else
        self
            .buttonStyle(NavigationLinkButtonStyle(verticalPadding: 12))
        #endif
    }
}

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
                    .tint(.primary)
                #if os(iOS)
                Spacer()
                NavigationLinkButtonStyle.NavigationArrow()
                #endif
            }
            .frame(maxWidth: .infinity)
            #if os(iOS)
            .contentShape(Rectangle())
            #endif
        }
    }
}
