#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif
import Testing

@testable import SwiftUITabFeatures

struct SwiftUITabFeaturesTests {
    @Test
    @MainActor
    func `feature sections and tab bar policy are declared in the feature tree`() {
        let features = TabFeatures<DemoTab> {
            Section("Event") {
                TabFeature(
                    .schedule,
                    title: "Schedule",
                    systemImage: "calendar"
                ) {
                    EmptyView()
                }

                TabFeature(
                    .settings,
                    title: "Settings",
                    systemImage: "gear"
                ) {
                    EmptyView()
                }
            }

            TabFeature(
                .about,
                title: "About",
                systemImage: "info.circle"
            ) {
                EmptyView()
            }
            .allowedOnTabBar(false)
        }

        let resolved = features.resolve(
            layout: .init(),
            policy: .init(maxVisibleTabs: 1)
        )

        #expect(features.tabFeatureMetadata.map(\.value) == [.schedule, .settings, .about])
        #expect(resolved.visibleFeatures.map(\.value) == [.schedule])
        #expect(resolved.overflowFeatures.map(\.value) == [.settings])

        let moreContent = features.moreContent(
            for: Set(resolved.overflowFeatures.map(\.id))
        )
        #expect(moreContent.flatMap(\.featureMetadata).map(\.value) == [.settings, .about])
        guard case let .section(title, content) = moreContent[0] else {
            #expect(Bool(false))
            return
        }
        #expect(title == "Event")
        #expect(content.flatMap(\.featureMetadata).map(\.value) == [.settings])
    }

    @Test
    @MainActor
    func `More modifier accepts arbitrary views and icon toolbar content`() {
        let view = TabFeaturesView(
            selection: .constant(DemoTab.schedule),
            layout: .constant(.init())
        ) {
            TabFeature(.schedule, title: "Schedule", systemImage: "calendar") {
                EmptyView()
            }
        }
        .more {
            Section("More") {
                Text("Arbitrary More content")
            }
        } toolbar: {
            ToolbarItem(placement: .cancellationAction) {
                Button {} label: {
                    Label("Close", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                }
            }
        }

        _ = view
    }

    @Test func `More remembers its destination while visiting a tab bar tab`() {
        var state = TabFeatureSelectionState(
            selection: DemoTab.schedule,
            overflowSelection: DemoTab.settings,
            isMoreSelected: true
        )

        state.select(.feature(.about))

        #expect(state.selection == .about)
        #expect(state.overflowSelection == .settings)
        #expect(state.isMoreSelected == false)
        #expect(state.tabSelection(showsMore: true) == .feature(.about))

        state.select(.more)

        #expect(state.selection == .about)
        #expect(state.overflowSelection == .settings)
        #expect(state.isMoreSelected)
        #expect(state.tabSelection(showsMore: true) == .more)
    }

    @Test func `builder preserves declaration order`() {
        let features = TabFeatures<DemoTab> {
            TabFeature(
                .schedule,
                title: "Schedule",
                systemImage: "calendar"
            ) {
                EmptyView()
            }

            TabFeature(
                .search,
                role: .search
            ) {
                EmptyView()
            }

            TabFeature(
                .mainStage,
                title: "Main Stage",
                systemImage: "music.note"
            ) {
                EmptyView()
            }
        }

        #expect(features.tabFeatureMetadata.map(\.value) == [.schedule, .search, .mainStage])
    }

    @Test func `labeled tabs extract title symbol and value`() {
        let feature = TabFeature(
            DemoTab.schedule,
            title: "Schedule",
            systemImage: "calendar",
            composeImage: "Icons.Outlined.DateRange",
            navigation: .stack
        ) {
            EmptyView()
        }

        #expect(feature.metadata.value == .schedule)
        #expect(feature.metadata.title == "Schedule")
        #expect(feature.metadata.systemImage == symbol("calendar"))
        #expect(feature.metadata.composeImage == symbol("Icons.Outlined.DateRange"))
        #expect(feature.metadata.effectiveComposeImage == symbol("Icons.Outlined.DateRange"))
        #expect(feature.metadata.role == nil)
    }

    @Test func `search role derives metadata and identity from value`() {
        let feature = TabFeature(
            DemoTab.search,
            role: .search
        ) {
            EmptyView()
        }

        #expect(feature.metadata.value == .search)
        #expect(feature.metadata.role == .search)
        #expect(feature.metadata.title == "Search")
        #expect(feature.metadata.systemImage == symbol("magnifyingglass"))
        #expect(feature.metadata.effectiveComposeImage == symbol("magnifyingglass"))
        #expect(feature.metadata.id == id("search"))
        #expect(feature.item.title == "Search")
        #expect(feature.item.systemImage == symbol("magnifyingglass"))
    }

    @Test func `search role keeps its searchable navigation surface at the tab root`() {
        let feature = TabFeature(
            DemoTab.search,
            role: .search,
            navigation: .stack
        ) {
            EmptyView()
        }

        #expect(!feature.metadata.wrapsContentInNavigationStack)
    }

    @Test func `navigation metadata records stack when present`() {
        let stacked = TabFeature(
            DemoTab.schedule,
            title: "Schedule",
            systemImage: "calendar",
            navigation: .stack
        ) {
            EmptyView()
        }
        let plain = TabFeature(
            DemoTab.about,
            title: "About",
            systemImage: "info.circle"
        ) {
            EmptyView()
        }

        #expect(stacked.metadata.navigation == .stack)
        #expect(plain.metadata.navigation == nil)
    }

    @Test func `label tint is preserved in metadata`() {
        let feature = TabFeature(
            DemoTab.schedule,
            title: "Schedule",
            systemImage: "calendar",
            labelTint: .red
        ) {
            EmptyView()
        }

        #expect(feature.metadata.labelTint != nil)
    }

    @Test func `badge value is preserved in metadata`() {
        let feature = TabFeature(
            DemoTab.schedule,
            title: "Schedule",
            systemImage: "calendar",
            badgeValue: 4
        ) {
            EmptyView()
        }

        #expect(feature.metadata.badgeValue == 4)
    }

    @Test func `derived ID matches lossless string value`() {
        let feature = TabFeature(
            DemoTab.mainStage,
            title: "Main Stage",
            systemImage: "music.note"
        ) {
            EmptyView()
        }

        #expect(feature.id == id("stage:main"))
    }

    @Test func `open string convertible value supports custom tabs`() {
        let pinned = DemoTab(rawValue: "stage:sunrise")
        let feature = TabFeature(
            pinned,
            title: "Sunrise Stage",
            systemImage: "sun.max"
        ) {
            EmptyView()
        }

        #expect(feature.metadata.value == pinned)
        #expect(feature.id == id("stage:sunrise"))
    }

    @Test func `declared features bridge into resolver items`() {
        let features = TabFeatures<DemoTab> {
            TabFeature(.search, role: .search) {
                EmptyView()
            }

            TabFeature(
                .schedule,
                title: "Schedule",
                systemImage: "calendar",
                navigation: .stack
            ) {
                EmptyView()
            }

            TabFeature(
                .mainStage,
                title: "Main Stage",
                systemImage: "music.note"
            ) {
                EmptyView()
            }
        }
        let resolved = features.resolve(
            layout: .init(preferredIDs: [id("stage:main")]),
            policy: .init(fixedVisibleIDs: [id("search")], maxVisibleTabs: 2)
        )

        #expect(features.tabFeatureItems.map(\.id) == [id("search"), id("schedule"), id("stage:main")])
        #expect(resolved.visibleFeatures.map(\.id) == [id("stage:main"), id("schedule")])
        #expect(resolved.overflowFeatures.isEmpty)
        #expect(resolved.searchTab?.id == id("search"))
        #expect(resolved.showsMore == false)
    }

    @Test func `declared resolve keeps search out of overflow and off capacity`() {
        let features = TabFeatures<DemoTab> {
            TabFeature(.schedule, title: "Schedule", systemImage: "calendar") {
                EmptyView()
            }

            TabFeature(.search, role: .search) {
                EmptyView()
            }

            TabFeature(.mainStage, title: "Main Stage", systemImage: "music.note") {
                EmptyView()
            }

            TabFeature(.about, title: "About", systemImage: "info.circle") {
                EmptyView()
            }
        }
        let resolved = features.resolve(
            layout: .init(preferredIDs: [id("stage:main"), id("about")]),
            policy: .init(fixedVisibleIDs: [id("search")], maxVisibleTabs: 2)
        )

        #expect(resolved.visibleFeatures.map(\.id) == [id("stage:main"), id("about")])
        #expect(resolved.overflowFeatures.map(\.id) == [id("schedule")])
        #expect(resolved.searchTab?.id == id("search"))
        #expect(resolved.showsMore)
    }

    @Test func `declared resolve sums overflow badge values`() {
        let features = TabFeatures<DemoTab> {
            TabFeature(.schedule, title: "Schedule", systemImage: "calendar", badgeValue: 2) {
                EmptyView()
            }

            TabFeature(.search, role: .search) {
                EmptyView()
            }

            TabFeature(.mainStage, title: "Main Stage", systemImage: "music.note", badgeValue: 3) {
                EmptyView()
            }

            TabFeature(.about, title: "About", systemImage: "info.circle") {
                EmptyView()
            }
        }
        let resolved = features.resolve(
            layout: .init(preferredIDs: [id("about")]),
            policy: .init(maxVisibleTabs: 1)
        )

        #expect(resolved.visibleFeatures.map(\.id) == [id("about")])
        #expect(resolved.overflowFeatures.map(\.id) == [id("schedule"), id("stage:main")])
        #expect(resolved.overflowBadgeValue == 5)
    }

    @Test func `default policy infers search as fixed`() {
        let features = TabFeatures<DemoTab> {
            TabFeature(.schedule, title: "Schedule", systemImage: "calendar") {
                EmptyView()
            }

            TabFeature(.search, role: .search) {
                EmptyView()
            }

            TabFeature(.about, title: "About", systemImage: "info.circle") {
                EmptyView()
            }
        }

        let policy = features.defaultPolicy(for: compactIPhoneContext)

        #expect(policy.fixedVisibleIDs == [id("search")])
        #expect(policy.maxVisibleTabs == 3)
    }

    @Test func `default policy keeps search out of overflow`() {
        let features = TabFeatures<DemoTab> {
            TabFeature(.schedule, title: "Schedule", systemImage: "calendar") {
                EmptyView()
            }

            TabFeature(.search, role: .search) {
                EmptyView()
            }

            TabFeature(.mainStage, title: "Main Stage", systemImage: "music.note") {
                EmptyView()
            }

            TabFeature(.about, title: "About", systemImage: "info.circle") {
                EmptyView()
            }
        }
        let resolved = features.resolve(
            layout: .init(preferredIDs: [id("stage:main"), id("about")]),
            policy: features.defaultPolicy(for: compactIPhoneContext)
        )

        #expect(resolved.visibleFeatures.map(\.id) == [id("stage:main"), id("about"), id("schedule")])
        #expect(resolved.overflowFeatures.isEmpty)
        #expect(resolved.searchTab?.id == id("search"))
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

    @Test func `default max visible tabs is compact iphone friendly`() {
        #expect(defaultTabFeatureMaxVisibleTabs(for: compactIPhoneContext) == 3)
    }

    @Test func `default max visible tabs is unlimited on regular iOS`() {
        #expect(defaultTabFeatureMaxVisibleTabs(for: regularIOSContext) == .max)
    }

    @Test func `default max visible tabs is unlimited on macOS`() {
        #expect(defaultTabFeatureMaxVisibleTabs(for: macOSContext) == .max)
    }

    @Test func `default presentation style uses tabs on compact iPhone`() {
        #expect(defaultTabFeaturePresentationStyle(for: compactIPhoneContext) == .tabs)
    }

    @Test func `default presentation style uses sidebar on regular iOS`() {
        #expect(defaultTabFeaturePresentationStyle(for: regularIOSContext) == .sidebar)
    }

    @Test func `default presentation style uses sidebar on macOS`() {
        #expect(defaultTabFeaturePresentationStyle(for: macOSContext) == .sidebar)
    }

    @Test func `explicit presentation style bypasses automatic defaults`() {
        #expect(resolvedTabFeaturePresentationStyle(.tabs, for: macOSContext) == .tabs)
        #expect(resolvedTabFeaturePresentationStyle(.sidebar, for: compactIPhoneContext) == .sidebar)
    }

    @Test func `explicit policy bypasses default inference`() {
        let features = TabFeatures<DemoTab> {
            TabFeature(.schedule, title: "Schedule", systemImage: "calendar") {
                EmptyView()
            }

            TabFeature(.search, role: .search) {
                EmptyView()
            }

            TabFeature(.mainStage, title: "Main Stage", systemImage: "music.note") {
                EmptyView()
            }
        }
        let policy = TabFeaturePolicy(maxVisibleTabs: 1)
        let resolved = features.resolve(
            layout: .init(preferredIDs: [id("stage:main")]),
            policy: policy
        )

        #expect(policy.fixedVisibleIDs.isEmpty)
        #expect(resolved.visibleFeatures.map(\.id) == [id("stage:main")])
        #expect(resolved.overflowFeatures.map(\.id) == [id("schedule")])
        #expect(resolved.searchTab?.id == id("search"))
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

    private var compactIPhoneContext: TabFeatureMaxVisibleTabsContext {
        TabFeatureMaxVisibleTabsContext(
            platform: .iOS,
            operatingSystemVersion: .init(majorVersion: 18, minorVersion: 0, patchVersion: 0),
            horizontalSizeClass: .compact,
            verticalSizeClass: .regular
        )
    }

    private var regularIOSContext: TabFeatureMaxVisibleTabsContext {
        TabFeatureMaxVisibleTabsContext(
            platform: .iOS,
            operatingSystemVersion: .init(majorVersion: 18, minorVersion: 0, patchVersion: 0),
            horizontalSizeClass: .regular,
            verticalSizeClass: .regular
        )
    }

    private var macOSContext: TabFeatureMaxVisibleTabsContext {
        TabFeatureMaxVisibleTabsContext(
            platform: .macOS,
            operatingSystemVersion: .init(majorVersion: 15, minorVersion: 0, patchVersion: 0)
        )
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
    static let settings = Self(rawValue: "settings")
}
