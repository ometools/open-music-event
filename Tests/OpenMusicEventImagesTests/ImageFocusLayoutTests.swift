import CoreGraphics
import CustomDump
import Testing

@testable import OpenMusicEventImages

struct ImageFocusLayoutTests {
    @Test
    func centeredFocusUsesNormalAspectFill() {
        let layout = ImageFocusLayout.layout(
            imageSize: CGSize(width: 400, height: 200),
            containerSize: CGSize(width: 200, height: 200),
            focalPoint: CGPoint(x: 0.5, y: 0.5)
        )

        expectNoDifference(layout.frame, CGRect(x: -100, y: 0, width: 400, height: 200))
        expectClose(layout.scale, 1)
        expectNoDifference(layout.safeRect, CGRect(x: 0, y: 0, width: 200, height: 200))
        #expect(layout.usesFocus)
    }

    @Test
    func pansHorizontallyBeforeScaling() {
        let layout = ImageFocusLayout.layout(
            imageSize: CGSize(width: 400, height: 200),
            containerSize: CGSize(width: 200, height: 200),
            focalPoint: CGPoint(x: 0.9, y: 0.5),
            safeRect: CGRect(x: 20, y: 0, width: 160, height: 200)
        )

        expectNoDifference(layout.frame, CGRect(x: -180, y: 0, width: 400, height: 200))
        expectClose(layout.scale, 1)
        #expect(layout.usesFocus)
    }

    @Test
    func pansVerticallyBeforeScaling() {
        let layout = ImageFocusLayout.layout(
            imageSize: CGSize(width: 200, height: 400),
            containerSize: CGSize(width: 200, height: 200),
            focalPoint: CGPoint(x: 0.5, y: 0.9),
            safeRect: CGRect(x: 0, y: 20, width: 200, height: 160)
        )

        expectNoDifference(layout.frame, CGRect(x: 0, y: -180, width: 200, height: 400))
        expectClose(layout.scale, 1)
        #expect(layout.usesFocus)
    }

    @Test
    func protectsBottomChromeByPanning() {
        let layout = ImageFocusLayout.layout(
            imageSize: CGSize(width: 200, height: 400),
            containerSize: CGSize(width: 200, height: 200),
            focalPoint: CGPoint(x: 0.5, y: 0.75),
            safeRect: CGRect(x: 0, y: 0, width: 200, height: 100)
        )

        expectNoDifference(layout.frame, CGRect(x: 0, y: -200, width: 200, height: 400))
        expectClose(layout.scale, 1)
        #expect(layout.usesFocus)
    }

    @Test
    func usesMinimumExtraScaleWhenPanningCannotReachSafeArea() {
        let layout = ImageFocusLayout.layout(
            imageSize: CGSize(width: 200, height: 200),
            containerSize: CGSize(width: 200, height: 200),
            focalPoint: CGPoint(x: 0.75, y: 0.5),
            safeRect: CGRect(x: 0, y: 0, width: 100, height: 200)
        )

        expectClose(layout.frame.minX, -200)
        expectClose(layout.frame.minY, -100)
        expectClose(layout.frame.width, 400)
        expectClose(layout.frame.height, 400)
        expectClose(layout.scale, 2)
        #expect(layout.usesFocus)
    }

    @Test
    func impossibleEdgeFocusStaysAsCloseAsCoverageAllows() {
        let layout = ImageFocusLayout.layout(
            imageSize: CGSize(width: 200, height: 200),
            containerSize: CGSize(width: 200, height: 200),
            focalPoint: CGPoint(x: 0, y: 0.5),
            safeRect: CGRect(x: 50, y: 0, width: 100, height: 200)
        )

        expectNoDifference(layout.frame, CGRect(x: 0, y: 0, width: 200, height: 200))
        expectClose(layout.scale, 1)
        #expect(layout.usesFocus)
    }

    @Test
    func missingFocusFallsBackToNormalAspectFill() {
        let layout = ImageFocusLayout.layout(
            imageSize: CGSize(width: 400, height: 200),
            containerSize: CGSize(width: 200, height: 200),
            focalPoint: nil,
            safeRect: CGRect(x: 40, y: 40, width: 120, height: 120)
        )

        expectNoDifference(layout.frame, CGRect(x: -100, y: 0, width: 400, height: 200))
        expectClose(layout.scale, 1)
        expectNoDifference(layout.safeRect, CGRect(x: 40, y: 40, width: 120, height: 120))
        #expect(!layout.usesFocus)
    }

    private func expectClose(
        _ actual: CGFloat,
        _ expected: CGFloat,
        accuracy: CGFloat = 0.001,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(abs(actual - expected) <= accuracy, sourceLocation: sourceLocation)
    }
}
