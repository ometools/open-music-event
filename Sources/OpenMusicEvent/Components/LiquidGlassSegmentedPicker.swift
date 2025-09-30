//
//  LiquidGlassSegmentedPicker.swift
//  open-music-event
//
//  Created by Woodrow Melling on 9/29/25.
//

import  SwiftUI


#if os(iOS)

// MARK: - Container Values Extension

@available(iOS 26, *)
extension ContainerValues {
    @Entry var pickerItemColor: Color = .accentColor
}

// MARK: - View Extension for Picker Item Color
@available(iOS 26, *)
extension View {
    public func pickerItemColor(_ color: Color) -> some View {
        containerValue(\.pickerItemColor, color)
    }
}
@available(iOS 26, *)
public struct LiquidGlassSegmentedPicker<PickerValue: Hashable, Content: View>: View {
    // MARK: - Properties

    // MARK: - Init
    public init(
        selection: Binding<PickerValue>,
        @ViewBuilder content: () -> Content = { EmptyView() }
    ) {
        self.content = content()
        self._selection = selection
    }

    @Binding var selection: PickerValue
    var content: Content


    private let capsuleHeight: CGFloat = 4


    // MARK: Body

    public var body: some View {
        picker
    }


    @Namespace var namespace


    @State var hoveringItem: PickerValue?

    @State var coordinateSpace = NamedCoordinateSpace.named("picker")

    @State var valueFrames: [PickerValue: CGRect] = [:]
    @State var valueColors: [PickerValue: Color] = [:]

    @State var capsuleState: CapsuleState = .idle

    enum CapsuleState {
        case idle       // Normal state
        case dragging   // User is actively dragging
        case switching  // Programmatic tab switch (tap gesture)
    }


    var height: CGFloat = 80

    @ViewBuilder
    var picker: some View {
        GlassEffectContainer(spacing: 20) {
            pickerContent
                .overlay(alignment: .leading) {
                    draggableCapsule
                }
//                .glassEffectUnion(id: "capsule", namespace: namespace)
        }
        .coordinateSpace(coordinateSpace)
        .frame(height: height)
        .gesture(dragGesture)
        .animation(.snappy, value: selection)
//        .background {
//            Capsule()
//                .glassEffect()
//                .glassEffectID("background", in: namespace)
//        }
//        .scaleEffect(dragging ? 1.1 : 1)
    }

    @ViewBuilder
    private var pickerContent: some View {
        HStack(alignment: .center) {
            ForEach(subviews: content) { subview in
                let tag = subview.containerValues.tag(for: PickerValue.self) ?? subview.id as? PickerValue
                let itemColor = subview.containerValues.pickerItemColor
                let idleSelected = tag == selection && capsuleState == .idle
                Spacer()

                if let tag {
                    subview
                        .opacity(idleSelected ? 0.0 : 1.0)
                        .foregroundStyle(itemColor)
                        .background(frameReportingBackground(for: tag))
                        .background(colorReportingBackground(for: tag, color: itemColor))
                        .onTapGesture {
                            handleTap(for: tag)
                        }
                        .background {
                            if idleSelected {
                                Capsule()
                                    .fill(itemColor)
//                                    .frame(
//                                        width: 80,
//                                        height: 80
//                                    )
    //                                 selection)
                            }
                        }
//                        .glassEffect(.clear)
//                        .glassEffectID("background", in: namespace)
                } else {
                    subview
                        .foregroundStyle(itemColor)
                }
            }
            
            Spacer()
        }
        .coordinateSpace(coordinateSpace)
        .onPreferenceChange(PickerFramesPreferenceKey.self) { frames in
            self.valueFrames = frames
        }
        .onPreferenceChange(PickerColorsPreferenceKey.self) { colors in
            self.valueColors = colors
        }

        .onChange(of: selection) { oldValue, newValue in
            handleTap(for: newValue)
        }
    }

    private func handleTap(for value: PickerValue) {
        capsuleState = .switching
        withAnimation {
            selection = value
        }

        // Brief animation to show selection, then return to idle
        Task { @MainActor in
            try await Task.sleep(for: .milliseconds(400))
            withAnimation(.snappy) {
                capsuleState = .idle
            }
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


    @ViewBuilder
    private var draggableCapsule: some View {
        let selectedFrame = valueFrames[selection] ?? .zero
//        let selectedColor = valueColors[selection] ?? .primary
//        let hoveringColor = hoveringItem.flatMap { valueColors[$0] } ?? selectedColor

        Group {
            if capsuleState == .idle {
                ForEach(subviews: content) { subview in
                    if subview.containerValues.tag(for: PickerValue.self) == selection {
                        subview
                            .foregroundStyle(.white)
                    }
                }
            } else {
                Capsule()
                    .stroke(Color.black.opacity(0.01))
            }

        }
        .glassEffectID("capsule", in: namespace)
        .glassEffect(
            .clear.interactive(), in: .capsule
        )
        .frame(
            width: selectedFrame.width,
            height: selectedFrame.height
        )
        .offset(CGSize(
            width: selectedFrame.minX + offset,
            height: 0
        ))

    }

    private var capsuleGlassEffect: Glass  {
        switch capsuleState {
        case .idle:
            return .identity
        case .dragging, .switching:
            return .regular
        }
    }

    @State var offset: CGFloat = .zero
    @GestureState var location: CGPoint = .zero
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: coordinateSpace)
            .onChanged { value in
                withAnimation {
                    if capsuleState != .dragging {
                        capsuleState = .dragging
                    }
                }
                offset = value.translation.width
                updateHoveringItem(at: value.location)
            }
            .onEnded { finalState in
                withAnimation(.snappy) {
                    offset = .zero
                    selection = hoveringItem ?? selection
                    hoveringItem = nil
                    capsuleState = .idle
                }
            }
    }

    private func updateHoveringItem(at location: CGPoint) {
        // Find which item (if any) contains the current location
        let newHoveringItem = valueFrames.first { _, frame in
            (frame.minX..<frame.maxX).contains(location.x)
        }?.key

        // Only update if the hovering item has changed
        if newHoveringItem != hoveringItem {
            withAnimation(.snappy) {
                self.hoveringItem = newHoveringItem
            }
        }
    }

    // Preference key to collect frames for each picker value
    internal struct PickerFramesPreferenceKey: PreferenceKey {
        static var defaultValue: [PickerValue: CGRect] { [:] }

        static func reduce(value: inout [PickerValue: CGRect], nextValue: () -> [PickerValue: CGRect]) {
            value.merge(nextValue(), uniquingKeysWith: { _, new in new })
        }
    }

    // Preference key to collect colors for each picker value
    internal struct PickerColorsPreferenceKey: PreferenceKey {
        static var defaultValue: [PickerValue: Color] { [:] }

        static func reduce(value: inout [PickerValue: Color], nextValue: () -> [PickerValue: Color]) {
            value.merge(nextValue(), uniquingKeysWith: { _, new in new })
        }
    }
}
#endif








internal struct RectPreferenceKey: PreferenceKey {
    static let defaultValue = CGRect.zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}



#Preview {
    @Previewable @State var val: String = "star"
    @Previewable @State var colorSelection: String = "blue"
    @Previewable @State var textSelection: String = "Home"

    VStack(spacing: 40) {
        Text("Testing LiquidGlassSegmentedPicker Colors")
            .font(.title2)
            .padding()

        if #available(iOS 26, *) {
            // Test 1: Icons with different colors
            VStack(alignment: .leading, spacing: 10) {
                Text("Icon Picker with Custom Colors")
                    .font(.headline)

                LiquidGlassSegmentedPicker(selection: $val) {
                    ForEach(["star", "cloud", "eye"], id: \.self) { item in
                        Image(systemName: item)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding()
                            .pickerItemColor(colorForItem(item))
                    }
                }
            }

            // Test 2: Color swatches as picker items
            VStack(alignment: .leading, spacing: 10) {
                Text("Color Swatch Picker")
                    .font(.headline)

                LiquidGlassSegmentedPicker(selection: $colorSelection) {
                    ForEach(["blue", "red", "green", "purple", "orange"], id: \.self) { color in
                        Circle()
                            .fill(colorForName(color))
                            .frame(width: 40, height: 40)
                            .pickerItemColor(colorForName(color))
                            .tag(color)
                    }
                }
            }

            // Test 3: Text labels with colors
            VStack(alignment: .leading, spacing: 10) {
                Text("Text Picker with Theme Colors")
                    .font(.headline)

                LiquidGlassSegmentedPicker(selection: $textSelection) {
                    ForEach(["Home", "Work", "Travel", "Health"], id: \.self) { item in
                        Text(item)
                            .font(.system(size: 16, weight: .medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .pickerItemColor(themeColorForCategory(item))
                            .tag(item)
                    }
                }
            }

            // Test 4: Mixed content with gradient colors
            VStack(alignment: .leading, spacing: 10) {
                Text("Mixed Content with Gradient Theme")
                    .font(.headline)

                LiquidGlassSegmentedPicker(selection: $val) {
                    ForEach(Array(zip(["star", "cloud", "eye"], ["Favorites", "Cloud", "Privacy"])), id: \.0) { icon, label in
                        VStack(spacing: 4) {
                            Image(systemName: icon)
                                .font(.system(size: 20))
                            Text(label)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .pickerItemColor(gradientColorForIcon(icon))
                        .tag(icon)
                    }
                }
            }

            // Display current selections
            VStack(alignment: .leading, spacing: 8) {
                Text("Current Selections:")
                    .font(.headline)
                Text("Icon: \(val)")
                Text("Color: \(colorSelection)")
                Text("Category: \(textSelection)")
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(12)
        }
    }
    .padding()
    .background(
        LinearGradient(
            colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
}

// Helper functions for color testing
private func colorForItem(_ item: String) -> Color {
    switch item {
    case "star": return .yellow
    case "cloud": return .cyan
    case "eye": return .purple
    default: return .blue
    }
}

private func colorForName(_ name: String) -> Color {
    switch name {
    case "blue": return .blue
    case "red": return .red
    case "green": return .green
    case "purple": return .purple
    case "orange": return .orange
    default: return .blue
    }
}

private func themeColorForCategory(_ category: String) -> Color {
    switch category {
    case "Home": return .blue
    case "Work": return .orange
    case "Travel": return .green
    case "Health": return .red
    default: return .gray
    }
}


private func gradientColorForIcon(_ icon: String) -> Color {
    switch icon {
    case "star": return .pink
    case "cloud": return .teal
    case "eye": return .indigo
    default: return .mint
    }
}




@available(iOS 26, *)
struct DragBubble: View {

    @GestureState var dragAmount: CGSize = .zero

    var body: some View {
        Capsule()
            .frame(width: 200, height: 100)
            .glassEffect(.clear.interactive())
            .offset(dragAmount)
               .gesture(
                   DragGesture().updating($dragAmount) { value, state, transaction in
                       state = value.translation
                   }
               )
    }
}
