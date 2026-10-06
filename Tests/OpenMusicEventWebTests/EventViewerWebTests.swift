import Testing
@testable import OpenMusicEventWeb

@Suite struct EventViewerWebTests {
    @Test func publicPageUsesRealContentAndEscapesMarkup() {
        let model = EventModel(name: "Woods <script>", location: "Fairmont", performances: [])
        let html = EventViewerHTMLPage(model: model).render()
        #expect(html.contains("Woods &lt;script&gt;"))
        #expect(!html.contains("feature=workspace"))
        #expect(!html.contains("feature=settings"))
        #expect(!html.contains("Summer Signals"))
        #expect(html.contains("No timed items published"))
        #expect(html.contains("<details class=\"event-menu\">"))
        #expect(html.contains("?feature=site-map#viewer"))
        #expect(html.contains("?feature=communications#viewer"))
    }
}
