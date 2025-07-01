////
////  File.swift
////  
////
////  Created by Woodrow Melling on 5/16/22.
////
//
//import Foundation
//import  SwiftUI; import SkipFuse
//
//struct ArrowPopover<Content: View>: View {
//    /// Which side to place the arrow on.
//    public var arrowSide: Templates.ArrowSide?
//
//    /// The container's corner radius.
//    public var cornerRadius = CGFloat(12)
//
//    /// The padding around the content view.
//    public var padding = CGFloat(16)
//
//    /// The content view.
//    @ViewBuilder public var view: Content
//
//    /**
//     A standard container for popovers, complete with arrow.
//     - parameter arrowSide: Which side to place the arrow on.
//     - parameter cornerRadius: The container's corner radius.
//     - parameter backgroundColor: The container's background/fill color.
//     - parameter padding: The padding around the content view.
//     - parameter view: The content view.
//     */
//    public init(
//        arrowSide: Templates.ArrowSide? = nil,
//        cornerRadius: CGFloat = CGFloat(12),
//        padding: CGFloat = CGFloat(16),
//        @ViewBuilder view: () -> Content
//    ) {
//        self.arrowSide = arrowSide
//        self.cornerRadius = cornerRadius
//        self.padding = padding
//        self.view = view()
//    }
//
//    public var body: some View {
//        PopoverReader { context in
//            view
//                .padding(padding)
//                .background(
//                    BackgroundWithArrow(
//                        arrowSide: arrowSide ?? context.attributes.position.getArrowPosition(),
//                        cornerRadius: cornerRadius
//                    )
//                    .fill(.regularMaterial)
//                )
//        }
//    }
//}
//
//struct BackgroundWithArrow: Shape {
//    /// The side of the rectangle to have the arrow
//    public var arrowSide: Templates.ArrowSide
//
//    /// The shape's corner radius
//    public var cornerRadius: CGFloat
//
//    /// The rectangle's width.
//    public static var width = CGFloat(48)
//
//    /// The rectangle's height.
//    public static var height = CGFloat(12)
//
//    /// The corner radius for the arrow's tip.
//    public static var tipCornerRadius = CGFloat(4)
//
//    /// The inverse corner radius for the arrow's base.
//    public static var edgeCornerRadius = CGFloat(10)
//
//    /// Offset the arrow from the sides - otherwise it will overflow out of the corner radius.
//    /// This is multiplied by the `cornerRadius`.
//    /**
//
//                  /\
//                 /_ \
//        ----------     <---- Avoid this gap.
//                    \
//         rectangle  |
//     */
//    public static var arrowSidePadding = CGFloat(1.8)
//
//    /// Path for the triangular arrow.
//    public func arrowPath() -> Path {
//        let arrowHalfWidth = (BackgroundWithArrow.width / 2) * 0.6
//
//        let arrowPath = Path { path in
//            let arrowRect = CGRect(x: 0, y: 0, width: BackgroundWithArrow.width, height: BackgroundWithArrow.height)
//
//            path.move(to: CGPoint(x: arrowRect.minX, y: arrowRect.maxY))
//            path.addArc(
//                tangent1End: CGPoint(x: arrowRect.midX - arrowHalfWidth, y: arrowRect.maxY),
//                tangent2End: CGPoint(x: arrowRect.midX, y: arrowRect.minX),
//                radius: BackgroundWithArrow.edgeCornerRadius
//            )
//            path.addArc(
//                tangent1End: CGPoint(x: arrowRect.midX, y: arrowRect.minX),
//                tangent2End: CGPoint(x: arrowRect.midX + arrowHalfWidth, y: arrowRect.maxY),
//                radius: BackgroundWithArrow.tipCornerRadius
//            )
//            path.addArc(
//                tangent1End: CGPoint(x: arrowRect.midX + arrowHalfWidth, y: arrowRect.maxY),
//                tangent2End: CGPoint(x: arrowRect.maxX, y: arrowRect.maxY),
//                radius: BackgroundWithArrow.edgeCornerRadius
//            )
//            path.addLine(to: CGPoint(x: arrowRect.maxX, y: arrowRect.maxY))
//        }
//        return arrowPath
//    }
//
//    /// Draw the shape.
//    public func path(in rect: CGRect) -> Path {
//        var arrowPath = arrowPath()
//        arrowPath = arrowPath.applying(
//            .init(translationX: -(BackgroundWithArrow.width / 2), y: -(BackgroundWithArrow.height))
//        )
//
//        var path = Path()
//        path.addRoundedRect(in: rect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
//
//        /// Rotation transform to make the arrow hit a different side.
//        let arrowTransform: CGAffineTransform
//
//        /// Half of the rectangle's smallest side length, used for the arrow's alignment.
//        let popoverRadius: CGFloat
//
//        let alignment: Templates.ArrowSide.ArrowAlignment
//        switch arrowSide {
//        case let .top(arrowAlignment):
//            alignment = arrowAlignment
//            arrowTransform = .init(translationX: rect.midX, y: 0)
//            popoverRadius = (rect.width / 2) - BackgroundWithArrow.arrowSidePadding * cornerRadius
//        case let .right(arrowAlignment):
//            alignment = arrowAlignment
//            arrowTransform = .init(rotationAngle: 90.degreesToRadians)
//                .translatedBy(x: rect.midY, y: -rect.maxX)
//            popoverRadius = (rect.height / 2) - BackgroundWithArrow.arrowSidePadding * cornerRadius
//        case let .bottom(arrowAlignment):
//            alignment = arrowAlignment
//            arrowTransform = .init(rotationAngle: 180.degreesToRadians)
//                .translatedBy(x: -rect.midX, y: -rect.maxY)
//            popoverRadius = (rect.width / 2) - BackgroundWithArrow.arrowSidePadding * cornerRadius
//        case let .left(arrowAlignment):
//            alignment = arrowAlignment
//            arrowTransform = .init(rotationAngle: 270.degreesToRadians)
//                .translatedBy(x: -rect.midY, y: 0)
//            popoverRadius = (rect.height / 2) - BackgroundWithArrow.arrowSidePadding * cornerRadius
//        }
//
//        switch alignment {
//        case .mostCounterClockwise:
//            arrowPath = arrowPath.applying(
//                .init(translationX: -popoverRadius, y: 0)
//            )
//        case .centered:
//            break
//        case .mostClockwise:
//            arrowPath = arrowPath.applying(
//                .init(translationX: popoverRadius, y: 0)
//            )
//        }
//
//        path.addPath(arrowPath, transform: arrowTransform)
//
//        return path
//    }
//}
//
//
