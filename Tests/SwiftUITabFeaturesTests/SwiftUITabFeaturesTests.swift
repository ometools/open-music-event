import Testing

@testable import SwiftUITabFeatures

struct SwiftUITabFeaturesTests {
    @Test func `keeps fixed IDs first`() {
        let resolved = TabFeatureResolver.resolve(
            availableItems: makeItems("search", "schedule", "about"),
            layout: .init(preferredIDs: [id("about"), id("schedule")]),
            policy: .init(fixedVisibleIDs: [id("search")], maxVisibleTabs: 3)
        )

        #expect(resolved.visibleIDs == [id("search"), id("about"), id("schedule")])
        #expect(resolved.overflowIDs.isEmpty)
        #expect(resolved.showsMore == false)
    }

    @Test func `preserves saved order`() {
        let resolved = TabFeatureResolver.resolve(
            availableItems: makeItems("schedule", "about", "alerts"),
            layout: .init(preferredIDs: [id("alerts"), id("schedule")]),
            policy: .init(maxVisibleTabs: 3)
        )

        #expect(resolved.visibleIDs == [id("alerts"), id("schedule"), id("about")])
    }

    @Test func `removes duplicate IDs`() {
        let resolved = TabFeatureResolver.resolve(
            availableItems: makeItems("search", "schedule", "about"),
            layout: .init(preferredIDs: [id("about"), id("about"), id("schedule")]),
            policy: .init(
                fixedVisibleIDs: [id("search"), id("search")],
                maxVisibleTabs: 4
            )
        )

        #expect(resolved.visibleIDs == [id("search"), id("about"), id("schedule")])
    }

    @Test func `drops unavailable IDs`() {
        let resolved = TabFeatureResolver.resolve(
            availableItems: makeItems("schedule", "about"),
            layout: .init(preferredIDs: [id("missing"), id("about")]),
            policy: .init(
                fixedVisibleIDs: [id("search"), id("schedule")],
                maxVisibleTabs: 3
            )
        )

        #expect(resolved.visibleIDs == [id("schedule"), id("about")])
        #expect(resolved.overflowIDs.isEmpty)
    }

    @Test func `appends unsaved available IDs in source order`() {
        let resolved = TabFeatureResolver.resolve(
            availableItems: makeItems("schedule", "about", "alerts", "edit"),
            layout: .init(preferredIDs: [id("alerts")]),
            policy: .init(maxVisibleTabs: 4)
        )

        #expect(
            resolved.visibleIDs
                == [id("alerts"), id("schedule"), id("about"), id("edit")]
        )
    }

    @Test func `computes overflow from max visible tabs`() {
        let resolved = TabFeatureResolver.resolve(
            availableItems: makeItems("search", "schedule", "about", "alerts", "edit"),
            layout: .init(preferredIDs: [id("alerts"), id("edit"), id("about"), id("schedule")]),
            policy: .init(fixedVisibleIDs: [id("search")], maxVisibleTabs: 3)
        )

        #expect(resolved.visibleIDs == [id("search"), id("alerts"), id("edit")])
        #expect(resolved.overflowIDs == [id("about"), id("schedule")])
        #expect(resolved.showsMore)
    }

    @Test func `resolves deterministically with empty saved layout`() {
        let resolved = TabFeatureResolver.resolve(
            availableItems: makeItems("search", "schedule", "about", "alerts"),
            layout: .init(),
            policy: .init(fixedVisibleIDs: [id("search")], maxVisibleTabs: 3)
        )

        #expect(resolved.visibleIDs == [id("search"), id("schedule"), id("about")])
        #expect(resolved.overflowIDs == [id("alerts")])
    }

    @Test func `public identity APIs use tagged IDs`() {
        let item = TabFeatureItem(
            id: id("schedule"),
            title: "Schedule",
            systemImage: symbol("calendar")
        )
        let layout = TabFeatureLayout(preferredIDs: [item.id])
        let policy = TabFeaturePolicy(fixedVisibleIDs: [id("search")], maxVisibleTabs: 3)
        let resolved = ResolvedTabFeatures(
            visibleIDs: [id("search"), item.id],
            overflowIDs: []
        )

        acceptID(item.id)
        acceptIDs(layout.preferredIDs)
        acceptIDs(policy.fixedVisibleIDs)
        acceptIDs(resolved.visibleIDs)
        acceptIDs(resolved.overflowIDs)
        acceptSymbol(item.systemImage)
    }

    private func makeItems(_ rawValues: String...) -> [TabFeatureItem] {
        rawValues.map { rawValue in
            TabFeatureItem(
                id: id(rawValue),
                title: rawValue.capitalized,
                systemImage: symbol("\(rawValue).icon")
            )
        }
    }

    private func id(_ rawValue: String) -> TabFeatureID {
        .init(rawValue)
    }

    private func symbol(_ rawValue: String) -> TabFeatureSymbolName {
        .init(rawValue)
    }

    private func acceptID(_ id: TabFeatureID) {}
    private func acceptIDs(_ ids: [TabFeatureID]) {}
    private func acceptSymbol(_ symbol: TabFeatureSymbolName) {}
}
