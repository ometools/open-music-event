import CoreGraphics
import CustomDump
import Testing

@testable import OpenMusicEventImages

struct ImageFocusLayoutTests {
    @Test
    func `moves a face above the visible hero to the upper-third line by zooming`() {
        let focalPoint = CGPoint(x: 0.5, y: 0.2)
        let safeRect = CGRect(x: 0, y: 100, width: 400, height: 200)

        let layout = ImageFocusLayout.layout(
            imageSize: CGSize(width: 800, height: 1_000),
            containerSize: CGSize(width: 400, height: 400),
            focalPoint: focalPoint,
            safeRect: safeRect
        )

        // The face cannot reach the upper-third line by panning alone, so the image zooms just enough.
        let displayedFocusY = layout.frame.minY + focalPoint.y * layout.frame.height
        expectClose(displayedFocusY, safeRect.minY + safeRect.height / 3)
        expectClose(layout.scale, 5 / 6)
        #expect(layout.usesFocus)
    }

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
    func `pans to the nearest horizontal third before scaling`() {
        let layout = ImageFocusLayout.layout(
            imageSize: CGSize(width: 400, height: 200),
            containerSize: CGSize(width: 200, height: 200),
            focalPoint: CGPoint(x: 0.7, y: 0.5),
            safeRect: CGRect(x: 20, y: 0, width: 160, height: 200)
        )

        expectClose(layout.frame.minX, -153.333_333)
        expectClose(layout.frame.minY, 0)
        expectClose(layout.frame.width, 400)
        expectClose(layout.frame.height, 200)
        expectClose(layout.scale, 1)
        #expect(layout.usesFocus)
    }

    @Test
    func `pans to the nearest vertical third before scaling`() {
        let layout = ImageFocusLayout.layout(
            imageSize: CGSize(width: 200, height: 400),
            containerSize: CGSize(width: 200, height: 200),
            focalPoint: CGPoint(x: 0.5, y: 0.7),
            safeRect: CGRect(x: 0, y: 20, width: 200, height: 160)
        )

        expectClose(layout.frame.minX, 0)
        expectClose(layout.frame.minY, -153.333_333)
        expectClose(layout.frame.width, 200)
        expectClose(layout.frame.height, 400)
        expectClose(layout.scale, 1)
        #expect(layout.usesFocus)
    }

    @Test
    func `protects bottom chrome by panning to the nearest third`() {
        let layout = ImageFocusLayout.layout(
            imageSize: CGSize(width: 200, height: 400),
            containerSize: CGSize(width: 200, height: 200),
            focalPoint: CGPoint(x: 0.5, y: 0.6),
            safeRect: CGRect(x: 0, y: 0, width: 200, height: 100)
        )

        expectClose(layout.frame.minX, 0)
        expectClose(layout.frame.minY, -173.333_333)
        expectClose(layout.frame.width, 200)
        expectClose(layout.frame.height, 400)
        expectClose(layout.scale, 1)
        #expect(layout.usesFocus)
    }

    @Test
    func `uses minimum extra scale when panning cannot reach the nearest third`() {
        let layout = ImageFocusLayout.layout(
            imageSize: CGSize(width: 200, height: 200),
            containerSize: CGSize(width: 200, height: 200),
            focalPoint: CGPoint(x: 0.75, y: 0.5),
            safeRect: CGRect(x: 0, y: 0, width: 100, height: 200)
        )

        expectClose(layout.frame.minX, -333.333_333)
        expectClose(layout.frame.minY, -166.666_667)
        expectClose(layout.frame.width, 533.333_333)
        expectClose(layout.frame.height, 533.333_333)
        expectClose(layout.scale, 2.666_667)
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
