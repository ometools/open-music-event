#if os(Android) || SKIP_BRIDGE
import SkipSwiftUI

public typealias ImageFocusCGFloat = SkipSwiftUI.CGFloat
public typealias ImageFocusCGPoint = SkipSwiftUI.CGPoint
public typealias ImageFocusCGSize = SkipSwiftUI.CGSize
public typealias ImageFocusCGRect = SkipSwiftUI.CGRect
#else
import CoreGraphics

public typealias ImageFocusCGFloat = CoreGraphics.CGFloat
public typealias ImageFocusCGPoint = CoreGraphics.CGPoint
public typealias ImageFocusCGSize = CoreGraphics.CGSize
public typealias ImageFocusCGRect = CoreGraphics.CGRect
#endif

public struct ImageFocusLayout: Equatable {
    public init(
        frame: ImageFocusCGRect,
        scale: ImageFocusCGFloat,
        safeRect: ImageFocusCGRect,
        usesFocus: Bool
    ) {
        self.frame = frame
        self.scale = scale
        self.safeRect = safeRect
        self.usesFocus = usesFocus
    }

    public var frame: ImageFocusCGRect
    public var scale: ImageFocusCGFloat
    public var safeRect: ImageFocusCGRect
    public var usesFocus: Bool

    public static func layout(
        imageSize: ImageFocusCGSize,
        containerSize: ImageFocusCGSize,
        focalPoint: ImageFocusCGPoint?,
        safeRect requestedSafeRect: ImageFocusCGRect? = nil
    ) -> Self {
        guard imageSize.width > 0,
              imageSize.height > 0,
              containerSize.width > 0,
              containerSize.height > 0
        else {
            return Self(
                frame: .zero,
                scale: 1,
                safeRect: .zero,
                usesFocus: false
            )
        }

        let containerRect = ImageFocusCGRect(origin: .zero, size: containerSize)
        let safeRect = normalizedSafeRect(
            requestedSafeRect ?? containerRect,
            in: containerRect
        )
        let focusRect = ruleOfThirdsRect(in: safeRect)
        let baseScale = max(
            containerSize.width / imageSize.width,
            containerSize.height / imageSize.height
        )

        guard let focalPoint else {
            return centeredFillLayout(
                imageSize: imageSize,
                containerSize: containerSize,
                scale: baseScale,
                safeRect: safeRect
            )
        }

        let normalizedFocus = ImageFocusCGPoint(
            x: focalPoint.x.clamped(to: 0...1),
            y: focalPoint.y.clamped(to: 0...1)
        )
        let imageFocus = ImageFocusCGPoint(
            x: normalizedFocus.x * imageSize.width,
            y: normalizedFocus.y * imageSize.height
        )
        let baseLayout = layout(
            imageSize: imageSize,
            containerSize: containerSize,
            imageFocus: imageFocus,
            scale: baseScale,
            safeRect: safeRect,
            focusRect: focusRect
        )
        guard !baseLayout.containsFocus else { return baseLayout.value }

        var lowerBound = baseScale
        var upperBound = baseScale
        var foundScaleThatContainsFocus = false

        for _ in 0..<32 {
            upperBound *= 1.5
            let layout = layout(
                imageSize: imageSize,
                containerSize: containerSize,
                imageFocus: imageFocus,
                scale: upperBound,
                safeRect: safeRect,
                focusRect: focusRect
            )
            if layout.containsFocus {
                foundScaleThatContainsFocus = true
                break
            }
        }

        guard foundScaleThatContainsFocus else {
            return baseLayout.value
        }

        for _ in 0..<40 {
            let scale = (lowerBound + upperBound) / 2
            let layout = layout(
                imageSize: imageSize,
                containerSize: containerSize,
                imageFocus: imageFocus,
                scale: scale,
                safeRect: safeRect,
                focusRect: focusRect
            )
            if layout.containsFocus {
                upperBound = scale
            } else {
                lowerBound = scale
            }
        }

        return layout(
            imageSize: imageSize,
            containerSize: containerSize,
            imageFocus: imageFocus,
            scale: upperBound,
            safeRect: safeRect,
            focusRect: focusRect
        )
        .value
    }

    private static func centeredFillLayout(
        imageSize: ImageFocusCGSize,
        containerSize: ImageFocusCGSize,
        scale: ImageFocusCGFloat,
        safeRect: ImageFocusCGRect
    ) -> Self {
        let renderedSize = ImageFocusCGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        return Self(
            frame: ImageFocusCGRect(
                x: (containerSize.width - renderedSize.width) / 2,
                y: (containerSize.height - renderedSize.height) / 2,
                width: renderedSize.width,
                height: renderedSize.height
            ),
            scale: scale,
            safeRect: safeRect,
            usesFocus: false
        )
    }

    private static func layout(
        imageSize: ImageFocusCGSize,
        containerSize: ImageFocusCGSize,
        imageFocus: ImageFocusCGPoint,
        scale: ImageFocusCGFloat,
        safeRect: ImageFocusCGRect,
        focusRect: ImageFocusCGRect
    ) -> LayoutCandidate {
        let renderedSize = ImageFocusCGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        let defaultOrigin = ImageFocusCGPoint(
            x: (containerSize.width - renderedSize.width) / 2,
            y: (containerSize.height - renderedSize.height) / 2
        )
        let horizontalLayout = axisLayout(
            focusCoordinate: imageFocus.x,
            scale: scale,
            targetRange: focusRect.minX...focusRect.maxX,
            coverRange: min(containerSize.width - renderedSize.width, 0)...0,
            defaultOrigin: defaultOrigin.x
        )
        let verticalLayout = axisLayout(
            focusCoordinate: imageFocus.y,
            scale: scale,
            targetRange: focusRect.minY...focusRect.maxY,
            coverRange: min(containerSize.height - renderedSize.height, 0)...0,
            defaultOrigin: defaultOrigin.y
        )
        let origin = ImageFocusCGPoint(
            x: horizontalLayout.origin,
            y: verticalLayout.origin
        )
        return LayoutCandidate(
            value: Self(
                frame: ImageFocusCGRect(origin: origin, size: renderedSize),
                scale: scale,
                safeRect: safeRect,
                usesFocus: true
            ),
            containsFocus: horizontalLayout.containsFocus
                && verticalLayout.containsFocus
        )
    }

    private static func ruleOfThirdsRect(
        in safeRect: ImageFocusCGRect
    ) -> ImageFocusCGRect {
        ImageFocusCGRect(
            x: safeRect.minX + safeRect.width / 3,
            y: safeRect.minY + safeRect.height / 3,
            width: safeRect.width / 3,
            height: safeRect.height / 3
        )
    }

    private static func axisLayout(
        focusCoordinate: ImageFocusCGFloat,
        scale: ImageFocusCGFloat,
        targetRange: ClosedRange<ImageFocusCGFloat>,
        coverRange: ClosedRange<ImageFocusCGFloat>,
        defaultOrigin: ImageFocusCGFloat
    ) -> (origin: ImageFocusCGFloat, containsFocus: Bool) {
        let scaledFocus = focusCoordinate * scale
        let requiredRange = (targetRange.lowerBound - scaledFocus)...(targetRange.upperBound - scaledFocus)
        let overlapLowerBound = max(requiredRange.lowerBound, coverRange.lowerBound)
        let overlapUpperBound = min(requiredRange.upperBound, coverRange.upperBound)
        if overlapLowerBound <= overlapUpperBound {
            return (
                defaultOrigin.clamped(to: overlapLowerBound...overlapUpperBound),
                true
            )
        }

        let candidates = [
            (targetRange.lowerBound - scaledFocus).clamped(to: coverRange),
            (targetRange.upperBound - scaledFocus).clamped(to: coverRange),
            defaultOrigin.clamped(to: coverRange),
        ]
        let origin = candidates.min { lhs, rhs in
            let lhsDistance = distance(lhs + scaledFocus, to: targetRange)
            let rhsDistance = distance(rhs + scaledFocus, to: targetRange)
            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }
            return abs(lhs - defaultOrigin) < abs(rhs - defaultOrigin)
        } ?? defaultOrigin.clamped(to: coverRange)
        return (origin, false)
    }

    private static func distance(
        _ value: ImageFocusCGFloat,
        to range: ClosedRange<ImageFocusCGFloat>
    ) -> ImageFocusCGFloat {
        if value < range.lowerBound {
            return range.lowerBound - value
        }
        if value > range.upperBound {
            return value - range.upperBound
        }
        return 0
    }

    private static func normalizedSafeRect(
        _ safeRect: ImageFocusCGRect,
        in containerRect: ImageFocusCGRect
    ) -> ImageFocusCGRect {
        let intersection = safeRect.intersection(containerRect)
        guard !intersection.isNull,
              intersection.width >= 0,
              intersection.height >= 0
        else {
            return containerRect
        }
        return intersection
    }
}

private struct LayoutCandidate {
    var value: ImageFocusLayout
    var containsFocus: Bool
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
