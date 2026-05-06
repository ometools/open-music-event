import SwiftUI
import Testing

@testable import SwiftUITabFeatures

struct SwiftUITabFeaturesTests {
    @Test func `builder preserves declaration order`() {
        let features = TabFeatures<DemoTab> {
            TabFeature(
                "Schedule",
                systemImage: "calendar",
                value: .schedule
            ) {
                EmptyView()
            }

            TabFeature(
                value: .search,
                role: .search
            ) {
                EmptyView()
            }

            TabFeature(
                "Main Stage",
                systemImage: "music.note",
                value: .mainStage
            ) {
                EmptyView()
            }
        }

        #expect(features.tabFeatureMetadata.map(\.value) == [.schedule, .search, .mainStage])
    }

    @Test func `labeled tabs extract title symbol and value`() {
        let feature = TabFeature(
            "Schedule",
            systemImage: "calendar",
            value: DemoTab.schedule,
            navigation: .stack
        ) {
            EmptyView()
        }

        #expect(feature.metadata.value == .schedule)
        #expect(feature.metadata.title == "Schedule")
        #expect(feature.metadata.systemImage == symbol("calendar"))
        #expect(feature.metadata.role == nil)
    }

    @Test func `search role derives metadata and identity from value`() {
        let feature = TabFeature(
            value: DemoTab.search,
            role: .search
        ) {
            EmptyView()
        }

        #expect(feature.metadata.value == .search)
        #expect(feature.metadata.role == .search)
        #expect(feature.metadata.title == nil)
        #expect(feature.metadata.systemImage == nil)
        #expect(feature.metadata.id == id("search"))
        #expect(feature.item.title == "Search")
        #expect(feature.item.systemImage == symbol("magnifyingglass"))
    }

    @Test func `navigation metadata records stack when present`() {
        let stacked = TabFeature(
            "Schedule",
            systemImage: "calendar",
            value: DemoTab.schedule,
            navigation: .stack
        ) {
            EmptyView()
        }
        let plain = TabFeature(
            "About",
            systemImage: "info.circle",
            value: DemoTab.about
        ) {
            EmptyView()
        }

        #expect(stacked.metadata.navigation == .stack)
        #expect(plain.metadata.navigation == nil)
    }

    @Test func `derived ID matches lossless string value`() {
        let feature = TabFeature(
            "Main Stage",
            systemImage: "music.note",
            value: DemoTab.mainStage
        ) {
            EmptyView()
        }

        #expect(feature.id == id("stage:main"))
    }

    @Test func `open string convertible value supports custom tabs`() {
        let pinned = DemoTab(rawValue: "stage:sunrise")
        let feature = TabFeature(
            "Sunrise Stage",
            systemImage: "sun.max",
            value: pinned
        ) {
            EmptyView()
        }

        #expect(feature.metadata.value == pinned)
        #expect(feature.id == id("stage:sunrise"))
    }

    @Test func `declared features bridge into resolver items`() {
        let features = TabFeatures<DemoTab> {
            TabFeature(value: .search, role: .search) {
                EmptyView()
            }

            TabFeature(
                "Schedule",
                systemImage: "calendar",
                value: .schedule,
                navigation: .stack
            ) {
                EmptyView()
            }

            TabFeature(
                "Main Stage",
                systemImage: "music.note",
                value: .mainStage
            ) {
                EmptyView()
            }
        }
        let resolved = TabFeatureResolver.resolve(
            availableItems: features.tabFeatureItems,
            layout: .init(preferredIDs: [id("stage:main")]),
            policy: .init(fixedVisibleIDs: [id("search")], maxVisibleTabs: 2)
        )

        #expect(features.tabFeatureItems.map(\.id) == [id("search"), id("schedule"), id("stage:main")])
        #expect(resolved.visibleIDs == [id("search"), id("stage:main")])
        #expect(resolved.overflowIDs == [id("schedule")])
    }

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

private struct DemoTab: TabFeatureValue {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init?(_ description: String) {
        self.rawValue = description
    }

    var description: String {
        self.rawValue
    }

    static let about = Self(rawValue: "about")
    static let mainStage = Self(rawValue: "stage:main")
    static let schedule = Self(rawValue: "schedule")
    static let search = Self(rawValue: "search")
}
