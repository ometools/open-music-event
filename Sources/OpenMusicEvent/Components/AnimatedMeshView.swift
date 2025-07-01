//
//  AnimatedMeshView.swift
//  event-viewer
//
//  Created by Woodrow Melling on 2/21/25.
//


import  SwiftUI
import SkipFuse


////#if !SKIP
//extension EnvironmentValues {
//    @Entry public var meshBaseColors: [Color] = [.accentColor]
//    @Entry public var colorDensity: Double = 1
//    @Entry public var colorShiftAmount: Double = 0.05
//}

struct AnimatedMeshView: View {

//    let width: Int
//    let height: Int
//    let margin: CGFloat

    init(width: Int = 3, height: Int = 3, margin: CGFloat = 0.0) {
//        self.width = max(2, width)   // at least 2
//        self.height = max(2, height) // at least 2
//        self.margin = margin
//
//        self._points = State(initialValue: generatePoints(width: width, height: height, margin: margin))
    }
//
//    @State var points: [SIMD2<Float>]
//    @State var colors: [Color] = []
//
//    let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
//
//    @Environment(\.colorShiftAmount) var colorShiftAmount


    var body: some View {
//        TimelineView(.animation) {
//
//            if #available(iOS 18.0, *) {
//                MeshGradient(
//                    width: width,
//                    height: height,
//                    locations: .points(points),
//                    colors: .colors(colors.shifted(for: $0.date, colorShiftAmount: colorShiftAmount))
//                )
//            } else {
//                // Fallback on earlier versions
//            }
//        }
//        .onReceive(timer) { _ in
//            withAnimation(.easeInOut.speed(0.1)) {
//                setColors()
//            }
//        }
//        .onAppear {
//            setColors()
//        }
    }

//
//    @Environment(\.colorDensity) var density: Double
//    @Environment(\.meshBaseColors) var meshBaseColors: [Color]
    func setColors() {
//        let colorCount = Int(Double(points.count) / density)
//
//        var options = meshBaseColors
//        options.pad(toLength: colorCount, with: .clear)
//
//        self.colors = points.map { _ in
//            options.randomElement() ?? .clear
//        }
    }

}

//extension [Color] {
//    func shifted(for date: Date, colorShiftAmount: Double) -> Self {
//        let offset = Double(date.timeIntervalSince1970)
//
//        // Shift each base color. We'll create a parallel array.
//        let shiftedColors = self.enumerated().map { index, color -> Color in
//            // The hue shift is scaled by `colorRotationSpeed`.
//
//            let hueShift = cos(offset / 5 + Double(index) * 0.5) * colorShiftAmount
//
//            #if os(iOS)
//            return color.shiftHue(by: hueShift)
//            #elseif os(macOS)
//            return color
//            #endif
//        }
//
//        return shiftedColors
//
//    }
//}

//
//extension RangeReplaceableCollection {
//
//    /// If not already at least the given length, appends enough copies of a
//    /// given element to reach that length.
//    public mutating func pad(toLength count: Int, with element: Element) {
//        append(contentsOf: repeatElement(element, count: Swift.max(0, count - self.count)))
//    }
//
//    /// Ensures the collection is the given length, either by truncating a
//    /// suffix or appending copies of the given element.
//    public mutating func setLength(to count: Int, extendingWith element: Element) {
//        precondition(count >= 0)
//        if let cutoff = index(startIndex, offsetBy: count, limitedBy: endIndex) {
//            removeSubrange(cutoff...)
//        } else {
//            pad(toLength: count, with: element)
//        }
//    }
//
//}
//
//private func generatePoints(width: Int, height: Int, margin: CGFloat) -> [SIMD2<Float>] {
//    // Range from e.g. -0.1 to 1.1 if margin=0.1
//    let minVal = Float(0.0 - margin)
//    let maxVal = Float(1.0 + margin)
//
//    var points = [SIMD2<Float>]()
//    points.reserveCapacity(width * height)
//
//    for row in 0..<height {
//        for col in 0..<width {
//            // Interpolate in [minVal…maxVal]
//            let x = minVal + (maxVal - minVal) * Float(col) / Float(width - 1)
//            let y = minVal + (maxVal - minVal) * Float(row) / Float(height - 1)
//
//            points.append(SIMD2<Float>(x, y))
//        }
//    }
//
//    return points
//}
//
//
//#if os(iOS)
//private extension Color {
//    /// Shift hue by `amount` in [-1.0, 1.0].
//    func shiftHue(by amount: Double) -> Color {
//        var hue: CGFloat = 0
//        var saturation: CGFloat = 0
//        var brightness: CGFloat = 0
//        var alpha: CGFloat = 0
//
//        UIColor(self).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
//
//        hue += CGFloat(amount)
//        hue = hue.truncatingRemainder(dividingBy: 1.0)
//        if hue < 0 { hue += 1 }
//
//        return Color(hue: Double(hue),
//                     saturation: Double(saturation),
//                     brightness: Double(brightness),
//                     opacity: Double(alpha))
//    }
//}
//#endif
////#endif
