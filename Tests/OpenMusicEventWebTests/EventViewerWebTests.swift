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
    @Test func programsAreExploreTabsRatherThanScheduleOptions() {
        var model = EventModel(name: "Woods", location: "Fairmont", scheduleLabel: "Workshops", performances: [])
        model.programChoices = [
            .init(title: "Music", url: "?program=music", selected: false),
            .init(title: "Workshops", url: "?program=workshops", selected: true)
        ]
        let html = EventViewerHTMLPage(model: model).render()
        #expect(html.contains("href=\"?program=music#viewer\""))
        #expect(!html.contains("class=\"sidebar-link selected\" href=\"?program=music#viewer\""))
        #expect(html.contains("class=\"sidebar-link selected\" href=\"?program=workshops#viewer\""))
        #expect(html.contains("class=\"feature-nav-link selected\" href=\"?program=workshops#viewer\""))
        #expect(html.contains("<h1>Workshops</h1>"))
        #expect(!html.contains("aria-label=\"Program\""))
        #expect(!html.contains("<h1>Schedule</h1>"))
    }

}
