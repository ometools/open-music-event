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
            .init(title: "Workshops", url: "?program=workshops", selected: true, icon: .personDoingYoga)
        ]
        let html = EventViewerHTMLPage(model: model).render()
        #expect(html.contains("href=\"?program=music#viewer\""))
        #expect(!html.contains("class=\"sidebar-link selected\" href=\"?program=music#viewer\""))
        #expect(html.contains("class=\"sidebar-link selected\" href=\"?program=workshops#viewer\""))
        #expect(html.contains("class=\"feature-nav-link selected\" href=\"?program=workshops#viewer\""))
        #expect(html.contains("data-icon='person-doing-yoga'"))
        #expect(html.contains("aria-current=\"page\""))
        #expect(html.contains("<h1>Workshops</h1>"))
        #expect(!html.contains("aria-label=\"Program\""))
        #expect(!html.contains("<h1>Schedule</h1>"))
    }

    @Test func responsiveNavigationPreservesTheAttendeeHierarchy() {
        var model = EventModel(name: "Woods", location: "Fairmont", performances: [])
        model.programChoices = [
            .init(title: "Workshops", url: "?program=workshops", selected: false, icon: .personDoingYoga),
            .init(title: "Schedule", url: "?program=music", selected: true)
        ]
        let html = EventViewerHTMLPage(model: model, feature: .contributors).render()

        #expect(html.contains("aria-label=\"Primary\""))
        #expect(html.contains("--feature-count: 5"))
        #expect(html.contains("class=\"feature-nav-more selected\""))
        #expect(html.contains(">More</span>"))
        #expect(html.contains("class=\"feature-nav-more-link selected\" href=\"?feature=contributors#viewer\""))
        #expect(html.contains("class=\"feature-nav-link\" href=\"?feature=communications#viewer\""))
        #expect(html.contains("class=\"feature-nav-link\" href=\"?feature=search#viewer\""))
        #expect(!html.contains("class=\"feature-nav-link selected\" href=\"?feature=contributors#viewer\""))
        #expect(html.contains(">Places</span>"))
    }

    @Test func contributorDirectoryDefersBiographyAndAppearancesToDetail() {
        let performance = Performance(
            id: "sunset-set",
            title: "Sunset Set",
            stage: "Forest Stage",
            time: "7:00 PM"
        )
        let contributor = Contributor(
            id: "ivy",
            name: "Ivy",
            role: "Artist",
            bio: "A biography that belongs on the detail screen.",
            handle: "@ivy.example",
            accentColor: "#123456",
            performanceIDs: [performance.id]
        )
        var model = EventModel(
            name: "Woods",
            location: "Fairmont",
            contributors: [contributor],
            performances: [performance]
        )
        model.schedulePerformances = [performance]

        let directoryHTML = EventViewerHTMLPage(model: model, feature: .contributors).render()
        #expect(directoryHTML.contains("Ivy"))
        #expect(directoryHTML.contains("Artist"))
        #expect(directoryHTML.contains("@ivy.example"))
        #expect(!directoryHTML.localizedLowercase.contains(contributor.bio.localizedLowercase))
        #expect(!directoryHTML.contains("Sunset Set · 7:00 PM"))

        let detailHTML = EventViewerHTMLPage(
            model: model,
            feature: .contributors,
            selectedContributorID: contributor.id
        ).render()
        #expect(detailHTML.contains(contributor.bio))
        #expect(detailHTML.contains("Sunset Set · 7:00 PM"))
    }

}
