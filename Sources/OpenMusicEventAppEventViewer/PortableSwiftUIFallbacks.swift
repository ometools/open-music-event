#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

#if os(Android)
typealias CGFloat = SkipSwiftUI.CGFloat
typealias CGPoint = SkipSwiftUI.CGPoint
typealias CGSize = SkipSwiftUI.CGSize
typealias CGRect = SkipSwiftUI.CGRect
public typealias OMEViewerCGFloat = SkipSwiftUI.CGFloat
typealias OMECGFloat = Double
typealias OMECGPoint = SkipSwiftUI.CGPoint
typealias OMECGRect = SkipSwiftUI.CGRect

struct ContentUnavailableView: View {
    private let label: AnyView
    private let description: AnyView
    private let actions: AnyView

    init(_ title: String, systemImage: String) {
        self.init(title, systemImage: systemImage, description: nil)
    }

    init(_ title: String, systemImage: String, description: Text) {
        self.init(title, systemImage: systemImage, description: Optional(description))
    }

    private init(_ title: String, systemImage: String, description: Text?) {
        self.label = AnyView(Label(title, systemImage: systemImage))
        self.description = AnyView(description ?? Text(""))
        self.actions = AnyView(EmptyView())
    }

    init<LabelContent: View, DescriptionContent: View, ActionsContent: View>(
        @ViewBuilder label: () -> LabelContent,
        @ViewBuilder description: () -> DescriptionContent,
        @ViewBuilder actions: () -> ActionsContent
    ) {
        self.label = AnyView(label())
        self.description = AnyView(description())
        self.actions = AnyView(actions())
    }

    init<LabelContent: View, DescriptionContent: View>(
        @ViewBuilder label: () -> LabelContent,
        @ViewBuilder description: () -> DescriptionContent
    ) {
        self.label = AnyView(label())
        self.description = AnyView(description())
        self.actions = AnyView(EmptyView())
    }

    init<LabelContent: View>(
        @ViewBuilder label: () -> LabelContent
    ) {
        self.label = AnyView(label())
        self.description = AnyView(EmptyView())
        self.actions = AnyView(EmptyView())
    }

    var body: some View {
        VStack(spacing: 12) {
            label
                .font(.headline)
            description
                .font(.subheadline)
                .foregroundStyle(.secondary)
            actions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .multilineTextAlignment(.center)
        .padding()
    }
}
#else
public typealias OMEViewerCGFloat = CGFloat
typealias OMECGFloat = CGFloat
#endif

extension View {
    @ViewBuilder
    func portableContentShape<S: Shape>(_ shape: S) -> some View {
        #if os(Android) && SKIP_BRIDGE
        self
        #else
        self.contentShape(shape)
        #endif
    }

    @ViewBuilder
    func portableLineLimit(_ range: ClosedRange<Int>) -> some View {
        #if os(Android)
        self.lineLimit(range.upperBound)
        #else
        self.lineLimit(range)
        #endif
    }

    @ViewBuilder
    func portableLayoutPriority(_ value: Double) -> some View {
        #if os(Android) && SKIP_BRIDGE
        self
        #else
        self.layoutPriority(value)
        #endif
    }

    @ViewBuilder
    func selectableText() -> some View {
        #if os(Android) && SKIP_BRIDGE
        self
        #else
        self.textSelection(.enabled)
        #endif
    }

    @ViewBuilder
    func portableTruncationMode(_ mode: Text.TruncationMode) -> some View {
        #if os(Android) && SKIP_BRIDGE
        self
        #else
        self.truncationMode(mode)
        #endif
    }

    @ViewBuilder
    func portableMonospacedDigit() -> some View {
        #if os(Android)
        self
        #else
        self.monospacedDigit()
        #endif
    }

    @ViewBuilder
    func portableAccessibilityHint(_ hint: Text) -> some View {
        #if os(Android) && SKIP_BRIDGE
        self
        #else
        self.accessibilityHint(hint)
        #endif
    }

    @ViewBuilder
    func portableAccessibilityElement() -> some View {
        #if os(Android) && SKIP_BRIDGE
        self
        #else
        self.accessibilityElement(children: .combine)
        #endif
    }

    @ViewBuilder
    func portableAccessibilityElementIgnoringChildren() -> some View {
        #if os(Android) && SKIP_BRIDGE
        self
        #else
        self.accessibilityElement(children: .ignore)
        #endif
    }

    @ViewBuilder
    func portableSafeAreaTopInset<Content: View>(
        spacing: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        #if os(Android) && SKIP_BRIDGE
        self
        #else
        self.safeAreaInset(edge: .top, spacing: spacing, content: content)
        #endif
    }
}

extension Binding {
    func portableAnimation() -> Binding<Value> {
        #if os(Android)
        self
        #else
        self.animation()
        #endif
    }
}

@ViewBuilder
func PortableTextField(_ title: String, text: Binding<String>, axis: Axis) -> some View {
    #if os(Android)
    TextField(title, text: text)
    #else
    TextField(title, text: text, axis: axis)
    #endif
}

@ViewBuilder
func PortableDisclosureGroup<Content: View>(
    _ title: String,
    @ViewBuilder content: @escaping () -> Content
) -> some View {
    #if os(Android) && SKIP_BRIDGE
    VStack(alignment: .leading) {
        Text(title)
        content()
    }
    #else
    DisclosureGroup(title, content: content)
    #endif
}

@ViewBuilder
func PortableDisclosureGroup<Content: View, Label: View>(
    @ViewBuilder content: @escaping () -> Content,
    @ViewBuilder label: () -> Label
) -> some View {
    #if os(Android) && SKIP_BRIDGE
    VStack(alignment: .leading) {
        label()
        content()
    }
    #else
    DisclosureGroup(content: content, label: label)
    #endif
}

@ViewBuilder
@MainActor
func PortableLabeledContent(_ title: String, value: String) -> some View {
    #if os(Android)
    HStack(alignment: .firstTextBaseline) {
        Text(title)
        Spacer()
        Text(value)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.trailing)
    }
    #else
    LabeledContent(title, value: value)
    #endif
}
