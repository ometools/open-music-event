import CoreGraphics

public struct ImageFocusLayout: Equatable {
    public init(
        frame: CGRect,
        scale: CGFloat,
        safeRect: CGRect,
        usesFocus: Bool
    ) {
        self.frame = frame
        self.scale = scale
        self.safeRect = safeRect
        self.usesFocus = usesFocus
    }

    public var frame: CGRect
    public var scale: CGFloat
    public var safeRect: CGRect
    public var usesFocus: Bool

    public static func layout(
        imageSize: CGSize,
        containerSize: CGSize,
        focalPoint: CGPoint?,
        safeRect requestedSafeRect: CGRect? = nil
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

        let containerRect = CGRect(origin: .zero, size: containerSize)
        let safeRect = normalizedSafeRect(
            requestedSafeRect ?? containerRect,
            in: containerRect
        )
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

        let normalizedFocus = CGPoint(
            x: focalPoint.x.clamped(to: 0...1),
            y: focalPoint.y.clamped(to: 0...1)
        )
        let imageFocus = CGPoint(
            x: normalizedFocus.x * imageSize.width,
            y: normalizedFocus.y * imageSize.height
        )
        let baseLayout = layout(
            imageSize: imageSize,
            containerSize: containerSize,
            imageFocus: imageFocus,
            scale: baseScale,
            safeRect: safeRect
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
                safeRect: safeRect
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
                safeRect: safeRect
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
            safeRect: safeRect
        )
        .value
    }

    private static func centeredFillLayout(
        imageSize: CGSize,
        containerSize: CGSize,
        scale: CGFloat,
        safeRect: CGRect
    ) -> Self {
        let renderedSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        return Self(
            frame: CGRect(
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
        imageSize: CGSize,
        containerSize: CGSize,
        imageFocus: CGPoint,
        scale: CGFloat,
        safeRect: CGRect
    ) -> LayoutCandidate {
        let renderedSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        let defaultOrigin = CGPoint(
            x: (containerSize.width - renderedSize.width) / 2,
            y: (containerSize.height - renderedSize.height) / 2
        )
        let origin = CGPoint(
            x: origin(
                focusCoordinate: imageFocus.x,
                scale: scale,
                safeRange: safeRect.minX...safeRect.maxX,
                coverRange: min(containerSize.width - renderedSize.width, 0)...0,
                defaultOrigin: defaultOrigin.x
            ),
            y: origin(
                focusCoordinate: imageFocus.y,
                scale: scale,
                safeRange: safeRect.minY...safeRect.maxY,
                coverRange: min(containerSize.height - renderedSize.height, 0)...0,
                defaultOrigin: defaultOrigin.y
            )
        )
        let displayedFocus = CGPoint(
            x: origin.x + imageFocus.x * scale,
            y: origin.y + imageFocus.y * scale
        )
        return LayoutCandidate(
            value: Self(
                frame: CGRect(origin: origin, size: renderedSize),
                scale: scale,
                safeRect: safeRect,
                usesFocus: true
            ),
            containsFocus: safeRect.includes(displayedFocus)
        )
    }

    private static func origin(
        focusCoordinate: CGFloat,
        scale: CGFloat,
        safeRange: ClosedRange<CGFloat>,
        coverRange: ClosedRange<CGFloat>,
        defaultOrigin: CGFloat
    ) -> CGFloat {
        let scaledFocus = focusCoordinate * scale
        let requiredRange = (safeRange.lowerBound - scaledFocus)...(safeRange.upperBound - scaledFocus)
        let overlapLowerBound = max(requiredRange.lowerBound, coverRange.lowerBound)
        let overlapUpperBound = min(requiredRange.upperBound, coverRange.upperBound)
        if overlapLowerBound <= overlapUpperBound {
            return defaultOrigin.clamped(to: overlapLowerBound...overlapUpperBound)
        }

        let candidates = [
            (safeRange.lowerBound - scaledFocus).clamped(to: coverRange),
            (safeRange.upperBound - scaledFocus).clamped(to: coverRange),
            defaultOrigin.clamped(to: coverRange),
        ]
        return candidates.min { lhs, rhs in
            let lhsDistance = distance(lhs + scaledFocus, to: safeRange)
            let rhsDistance = distance(rhs + scaledFocus, to: safeRange)
            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }
            return abs(lhs - defaultOrigin) < abs(rhs - defaultOrigin)
        } ?? defaultOrigin.clamped(to: coverRange)
    }

    private static func distance(
        _ value: CGFloat,
        to range: ClosedRange<CGFloat>
    ) -> CGFloat {
        if value < range.lowerBound {
            return range.lowerBound - value
        }
        if value > range.upperBound {
            return value - range.upperBound
        }
        return 0
    }

    private static func normalizedSafeRect(
        _ safeRect: CGRect,
        in containerRect: CGRect
    ) -> CGRect {
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

private extension CGRect {
    func includes(_ point: CGPoint) -> Bool {
        point.x >= minX
            && point.x <= maxX
            && point.y >= minY
            && point.y <= maxY
    }
}
