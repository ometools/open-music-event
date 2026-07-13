#if os(iOS) || os(macOS)
import SwiftUI

@available(iOS 26, macOS 26, *)
public extension ContainerValues {
    @Entry var pickerItemColor: Color = .accentColor
}

@available(iOS 26, macOS 26, *)
public extension View {
    func pickerItemColor(_ color: Color) -> some View {
        containerValue(\.pickerItemColor, color)
    }
}

@available(iOS 26, macOS 26, *)
public struct LiquidGlassSegmentedPicker<PickerValue: Hashable, Content: View>: View {
    @Binding var selection: PickerValue
    let content: Content

    @Namespace var namespace
    @State var capsuleState: CapsuleState = .idle
    @State var coordinateSpace = NamedCoordinateSpace.named("picker")
    @State var hoveringItem: PickerValue?
    @State var releasedCapsuleFrame: CGRect?
    @GestureState var dragState: CapsuleDragState = .inactive
    @State var switchingGeneration = 0
    @State var valueColors: [PickerValue: Color] = [:]
    @State var valueFrames: [PickerValue: CGRect] = [:]

    let circleSize: CGFloat = 70
    let iconOnlyItemWidth: CGFloat = 82
    let itemSpacing: CGFloat = 8
    let labeledItemWidth: CGFloat = 124
    let labelHeight: CGFloat = 36
    let scrollContentMargin: CGFloat = 20

    @Environment(\.labelsVisibility) var labelVisibility

    public init(
        selection: Binding<PickerValue>,
        @ViewBuilder content: () -> Content = { EmptyView() }
    ) {
        self._selection = selection
        self.content = content()
    }

    public var body: some View {
        GlassEffectContainer(spacing: 20) {
            Group(subviews: content) { subviews in
                ViewThatFits(in: .horizontal) {
                    fittedPicker(itemCount: subviews.count)
                    scrollingPicker
                }
            }
            .frame(height: scrollHeight)
        }
        .animation(.snappy, value: selection)
        .onChange(of: selection) { _, newValue in
            guard capsuleState == .idle, !dragState.isActive else { return }
            beginSwitching()
        }
        .onChange(of: dragState.isActive) { _, isActive in
            if isActive {
                releasedCapsuleFrame = nil
            } else {
                hoveringItem = nil
            }
        }
    }

    enum CapsuleState {
        case idle
        case switching
    }

    struct CapsuleDragState {
        var translation: CGSize
        var location: CGPoint?

        static var inactive: Self {
            Self(translation: .zero, location: nil)
        }

        var isActive: Bool {
            location != nil
        }
    }

    @ViewBuilder
    private func fittedPicker(itemCount: Int) -> some View {
        ZStack(alignment: .leading) {
            pickerContent(distributesItems: true)
            draggableCapsule
        }
        .frame(minWidth: minimumPickerWidth(for: itemCount), maxWidth: .infinity)
        .coordinateSpace(coordinateSpace)
    }

    @ViewBuilder
    private var scrollingPicker: some View {
        ScrollView(.horizontal) {
            ZStack(alignment: .leading) {
                pickerContent(distributesItems: false)
                draggableCapsule
            }
            .coordinateSpace(coordinateSpace)
        }
        .scrollIndicators(.never, axes: .horizontal)
        .scrollTargetBehavior(.viewAligned)
        .contentMargins(.horizontal, scrollContentMargin, for: .scrollContent)
        .scrollEdgeEffectStyle(.soft, for: [.leading, .trailing])
        .scrollClipDisabled()
    }

    @ViewBuilder
    private func pickerContent(distributesItems: Bool) -> some View {
        HStack(alignment: .top, spacing: itemSpacing) {
            ForEach(subviews: content) { subview in
                let tag = subview.containerValues.tag(for: PickerValue.self) ?? subview.id as? PickerValue
                let itemColor = subview.containerValues.pickerItemColor
                let idleSelected = tag == selection
                    && capsuleState == .idle
                    && !dragState.isActive
                    && releasedCapsuleFrame == nil

                itemContainer(tag, distributesItems: distributesItems) {
                    VStack(spacing: 4) {
                        if let tag {
                            subview
                                .labelStyle(.iconOnly)
                                .padding(4)
                                .frame(square: circleSize)
                                .opacity(idleSelected ? 0.0 : 1.0)
                                .foregroundStyle(itemColor)
                                .background(frameReportingBackground(for: tag))
                                .background(colorReportingBackground(for: tag, color: itemColor))
                                .background {
                                    if idleSelected {
                                        Capsule()
                                            .fill(itemColor)
                                    }
                                }
                        } else {
                            subview
                                .labelStyle(.iconOnly)
                                .foregroundStyle(itemColor)
                        }

                        if labelVisibility != .hidden {
                            subview
                                .font(.caption)
                                .lineLimit(2)
                                .minimumScaleFactor(0.78)
                                .multilineTextAlignment(.center)
                                .labelStyle(.titleOnly)
                                .frame(width: itemWidth, height: labelHeight, alignment: .top)
                        }
                    }
                    .frame(width: itemWidth)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let tag {
                            handleTap(for: tag)
                        }
                    }
                }
            }
        }
        .scrollTargetLayout()
        .onPreferenceChange(PickerFramesPreferenceKey.self) { frames in
            self.valueFrames = frames
        }
        .onPreferenceChange(PickerColorsPreferenceKey.self) { colors in
            self.valueColors = colors
        }
    }

    @ViewBuilder
    private var draggableCapsule: some View {
        let selectedFrame = valueFrames[selection] ?? .zero
        let capsuleFrame = if dragState.isActive {
            selectedFrame.offsetBy(dx: dragState.translation.width, dy: 0)
        } else {
            releasedCapsuleFrame ?? selectedFrame
        }
        let showsSelectedContent = capsuleState == .idle && !dragState.isActive && releasedCapsuleFrame == nil

        ZStack {
            Capsule()
                .stroke(Color.black.opacity(0.01))

            ForEach(subviews: content) { subview in
                if subview.containerValues.tag(for: PickerValue.self) == selection {
                    subview
                        .padding(4)
                        .frame(square: circleSize)
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.white)
                        .opacity(showsSelectedContent ? 1.0 : 0.0)
                }
            }
        }
        .glassEffectID("capsule", in: namespace)
        .glassEffect(.clear.interactive(), in: .capsule)
        .placement(capsuleFrame)
        .gesture(dragGesture)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: coordinateSpace)
            .updating($dragState) { value, state, _ in
                state = CapsuleDragState(
                    translation: value.translation,
                    location: value.location
                )
            }
            .onChanged { value in
                updateHoveringItem(at: value.location)
            }
            .onEnded { value in
                let newSelection = item(at: value.location) ?? hoveringItem ?? selection
                let releasedFrame = valueFrames[newSelection]
                    ?? (valueFrames[selection] ?? .zero).offsetBy(dx: value.translation.width, dy: 0)
                hoveringItem = nil

                if newSelection == selection {
                    withAnimation(.snappy) {
                        capsuleState = .idle
                    }
                } else {
                    handleDrop(for: newSelection, releasedFrame: releasedFrame)
                }
            }
    }

    private func handleTap(for value: PickerValue) {
        hoveringItem = nil
        releasedCapsuleFrame = nil
        beginSwitching()
        withAnimation {
            selection = value
        }
    }

    private func handleDrop(for value: PickerValue, releasedFrame: CGRect) {
        hoveringItem = nil

        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            releasedCapsuleFrame = releasedFrame
        }

        beginSwitching()
        withAnimation {
            selection = value
        }
    }

    private func minimumPickerWidth(for itemCount: Int) -> CGFloat {
        guard itemCount > 0 else { return .zero }
        return CGFloat(itemCount) * itemWidth + CGFloat(itemCount - 1) * itemSpacing
    }

    private var itemWidth: CGFloat {
        labelVisibility == .hidden ? iconOnlyItemWidth : labeledItemWidth
    }

    private var scrollHeight: CGFloat {
        labelVisibility == .hidden ? circleSize : circleSize + itemSpacing / 2 + labelHeight
    }

    private func beginSwitching() {
        switchingGeneration += 1
        let generation = switchingGeneration
        capsuleState = .switching
        Task { @MainActor in
            try await Task.sleep(for: .milliseconds(400))
            guard generation == switchingGeneration else { return }
            withAnimation(.snappy) {
                capsuleState = .idle
            }
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                releasedCapsuleFrame = nil
            }
        }
    }

    @ViewBuilder
    private func itemContainer<ItemContent: View>(
        _ tag: PickerValue?,
        distributesItems: Bool,
        @ViewBuilder content: () -> ItemContent
    ) -> some View {
        if let tag {
            distributedItem(distributesItems) {
                content()
                    .id(tag)
            }
        } else {
            distributedItem(distributesItems) {
                content()
            }
        }
    }

    @ViewBuilder
    private func distributedItem<ItemContent: View>(
        _ distributesItems: Bool,
        @ViewBuilder content: () -> ItemContent
    ) -> some View {
        if distributesItems {
            content()
                .frame(maxWidth: .infinity)
        } else {
            content()
        }
    }

    @ViewBuilder
    private func frameReportingBackground(for value: PickerValue) -> some View {
        GeometryReader { geometry in
            Color.clear
                .preference(
                    key: PickerFramesPreferenceKey.self,
                    value: [value: geometry.frame(in: coordinateSpace)]
                )
        }
    }

    @ViewBuilder
    private func colorReportingBackground(for value: PickerValue, color: Color) -> some View {
        Color.clear
            .preference(
                key: PickerColorsPreferenceKey.self,
                value: [value: color]
            )
    }

    private func item(at location: CGPoint) -> PickerValue? {
        valueFrames.first { _, frame in
            (frame.minX..<frame.maxX).contains(location.x)
        }?.key
    }

    private func updateHoveringItem(at location: CGPoint) {
        let newHoveringItem = item(at: location)

        if newHoveringItem != hoveringItem {
            withAnimation(.snappy) {
                self.hoveringItem = newHoveringItem
            }
        }
    }

    struct PickerFramesPreferenceKey: PreferenceKey {
        static var defaultValue: [PickerValue: CGRect] { [:] }

        static func reduce(value: inout [PickerValue: CGRect], nextValue: () -> [PickerValue: CGRect]) {
            value.merge(nextValue(), uniquingKeysWith: { _, new in new })
        }
    }

    struct PickerColorsPreferenceKey: PreferenceKey {
        static var defaultValue: [PickerValue: Color] { [:] }

        static func reduce(value: inout [PickerValue: Color], nextValue: () -> [PickerValue: Color]) {
            value.merge(nextValue(), uniquingKeysWith: { _, new in new })
        }
    }
}

private extension View {
    func frame(square length: CGFloat) -> some View {
        frame(width: length, height: length)
    }

    func placement(_ frame: CGRect) -> some View {
        self
            .frame(width: frame.width, height: frame.height)
            .position(frame.offsetBy(dx: frame.size.width / 2, dy: frame.size.height / 2).origin)
    }
}
#endif
