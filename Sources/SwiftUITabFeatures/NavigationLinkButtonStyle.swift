import SwiftUI

public struct NavigationLinkButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme

    func background(_ configuration: Configuration) -> Color {
        #if os(iOS)
        configuration.isPressed ? Color(.tertiarySystemBackground) : Color(.systemBackground)
        #elseif os(Android) || os(macOS)
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
                .contentShape(Rectangle())
            Spacer()
            NavigationArrow()
        }
        .listRowBackground(background(configuration))
        .background(background(configuration))
        #elseif os(Android)
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
