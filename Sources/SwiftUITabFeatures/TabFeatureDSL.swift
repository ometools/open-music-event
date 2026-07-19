import Foundation
import SwiftUI

public protocol TabFeatureValue: Hashable, LosslessStringConvertible, Sendable {}

extension String: TabFeatureValue {}

public enum TabFeatureNavigation: Equatable, Sendable {
    case stack
}

public enum TabFeatureRole: Equatable, Sendable {
    case search

    var title: String {
        switch self {
        case .search:
            "Search"
        }
    }

    var systemImage: TabFeatureSymbolName {
        switch self {
        case .search:
            .init("magnifyingglass")
        }
    }
}

public enum TabFeaturePlatform: Sendable {
    case iOS
    case macOS
    case tvOS
    case visionOS
    case watchOS
}

public enum TabFeaturePresentationStyle: Equatable, Sendable {
    case automatic
    case tabs
    case sidebar
}

public struct TabFeatureMaxVisibleTabsContext: Sendable {
    public var platform: TabFeaturePlatform
    public var operatingSystemVersion: OperatingSystemVersion
    public var horizontalSizeClass: UserInterfaceSizeClass?
    public var verticalSizeClass: UserInterfaceSizeClass?

    public init(
        platform: TabFeaturePlatform,
        operatingSystemVersion: OperatingSystemVersion,
        horizontalSizeClass: UserInterfaceSizeClass? = nil,
        verticalSizeClass: UserInterfaceSizeClass? = nil
    ) {
        self.platform = platform
        self.operatingSystemVersion = operatingSystemVersion
        self.horizontalSizeClass = horizontalSizeClass
        self.verticalSizeClass = verticalSizeClass
    }
}

public typealias TabFeatureMaxVisibleTabsResolver = @Sendable (TabFeatureMaxVisibleTabsContext) -> Int

func defaultTabFeatureMaxVisibleTabs(
    for context: TabFeatureMaxVisibleTabsContext
) -> Int {
    switch context.platform {
    case .macOS:
        .max
    case .iOS where context.horizontalSizeClass == .regular:
        .max
    default:
        3
    }
}

func defaultTabFeaturePresentationStyle(
    for context: TabFeatureMaxVisibleTabsContext
) -> TabFeaturePresentationStyle {
    switch context.platform {
    case .macOS:
        .sidebar
    case .iOS where context.horizontalSizeClass == .regular:
        .sidebar
    default:
        .tabs
    }
}

func resolvedTabFeaturePresentationStyle(
    _ presentationStyle: TabFeaturePresentationStyle,
    for context: TabFeatureMaxVisibleTabsContext
) -> TabFeaturePresentationStyle {
    switch presentationStyle {
    case .automatic:
        defaultTabFeaturePresentationStyle(for: context)
    case .tabs, .sidebar:
        presentationStyle
    }
}

private struct TabFeatureMaxVisibleTabsResolverKey: EnvironmentKey {
    static let defaultValue: TabFeatureMaxVisibleTabsResolver = defaultTabFeatureMaxVisibleTabs
}

extension EnvironmentValues {
    var tabFeatureMaxVisibleTabsResolver: TabFeatureMaxVisibleTabsResolver {
        get { self[TabFeatureMaxVisibleTabsResolverKey.self] }
        set { self[TabFeatureMaxVisibleTabsResolverKey.self] = newValue }
    }
}

struct AnyTabFeaturesMoreContent: @unchecked Sendable {
    let content: AnyView
    let applyToolbar: (AnyView) -> AnyView
}

private struct TabFeaturesMoreContentKey: EnvironmentKey {
    static let defaultValue: AnyTabFeaturesMoreContent? = nil
}

extension EnvironmentValues {
    var tabFeaturesMoreContent: AnyTabFeaturesMoreContent? {
        get { self[TabFeaturesMoreContentKey.self] }
        set { self[TabFeaturesMoreContentKey.self] = newValue }
    }
}

public extension View {
    func tabFeatureMaxVisibleTabs(
        _ resolver: @escaping TabFeatureMaxVisibleTabsResolver
    ) -> some View {
        environment(\.tabFeatureMaxVisibleTabsResolver, resolver)
    }
}

public struct TabFeatureMetadata<Value: TabFeatureValue>: Sendable {
    public var value: Value
    public var title: String?
    public var systemImage: TabFeatureSymbolName?
    public var labelTint: Color?
    public var badgeValue: Int?
    public var role: TabFeatureRole?
    public var navigation: TabFeatureNavigation?
    public var isAllowedOnTabBar: Bool

    public init(
        value: Value,
        title: String? = nil,
        systemImage: TabFeatureSymbolName? = nil,
        labelTint: Color? = nil,
        badgeValue: Int? = nil,
        role: TabFeatureRole? = nil,
        navigation: TabFeatureNavigation? = nil,
        isAllowedOnTabBar: Bool = true
    ) {
        self.value = value
        self.title = title
        self.systemImage = systemImage
        self.labelTint = labelTint
        self.badgeValue = badgeValue
        self.role = role
        self.navigation = navigation
        self.isAllowedOnTabBar = isAllowedOnTabBar
    }

    public var id: TabFeatureID {
        .init(String(self.value))
    }

    public var item: TabFeatureItem {
        TabFeatureItem(
            id: self.id,
            title: self.effectiveTitle,
            systemImage: self.effectiveSystemImage
        )
    }

    public var effectiveTitle: String {
        self.title ?? self.role?.title ?? ""
    }

    public var effectiveSystemImage: TabFeatureSymbolName {
        self.systemImage ?? self.role?.systemImage ?? .init("")
    }
}

public protocol TabFeatureContent {
    associatedtype Value: TabFeatureValue

    var tabFeatureMetadata: [TabFeatureMetadata<Value>] { get }
}

public struct TabFeatureGroup<Value: TabFeatureValue>: TabFeatureContent {
    let content: TabFeatureBuilder<Value>.Content

    public init(tabFeatureMetadata: [TabFeatureMetadata<Value>] = []) {
        self.content = .metadata(tabFeatureMetadata)
    }

    init(content: TabFeatureBuilder<Value>.Content) {
        self.content = content
    }

    public var tabFeatureMetadata: [TabFeatureMetadata<Value>] {
        self.content.tabFeatureMetadata
    }

    func featureBody(for id: TabFeatureID) -> AnyView? {
        self.content.featureBody(for: id)
    }

    func moreContent(for ids: Set<TabFeatureID>) -> [AnyTabFeatureMoreContent<Value>] {
        self.content.moreContent(for: ids)
    }
}

public struct TabFeatures<Value: TabFeatureValue>: TabFeatureContent {
    private let group: TabFeatureGroup<Value>

    public init(
        @TabFeatureBuilder<Value> content: () -> TabFeatureGroup<Value>
    ) {
        self.group = content()
    }

    public var tabFeatureMetadata: [TabFeatureMetadata<Value>] {
        self.group.tabFeatureMetadata
    }

    func featureBody(for id: TabFeatureID) -> AnyView? {
        self.group.featureBody(for: id)
    }

    func moreContent(for ids: Set<TabFeatureID>) -> [AnyTabFeatureMoreContent<Value>] {
        self.group.moreContent(for: ids)
    }
}

public struct ResolvedDeclaredTabFeatures<Value: TabFeatureValue>: Sendable {
    public var visibleFeatures: [TabFeatureMetadata<Value>]
    public var overflowFeatures: [TabFeatureMetadata<Value>]
    public var searchTab: TabFeatureMetadata<Value>?

    public init(
        visibleFeatures: [TabFeatureMetadata<Value>],
        overflowFeatures: [TabFeatureMetadata<Value>],
        searchTab: TabFeatureMetadata<Value>? = nil
    ) {
        self.visibleFeatures = visibleFeatures
        self.overflowFeatures = overflowFeatures
        self.searchTab = searchTab
    }

    public var showsMore: Bool {
        !self.overflowFeatures.isEmpty
    }

    public var overflowBadgeValue: Int? {
        let value = self.overflowFeatures.reduce(0) {
            $0 + ($1.badgeValue ?? 0)
        }
        return value > 0 ? value : nil
    }
}

public struct TabFeature<Value: TabFeatureValue, Content: View>: TabFeatureContent {
    public let value: Value
    public let title: String?
    public let systemImage: TabFeatureSymbolName?
    public let labelTint: Color?
    public let badgeValue: Int?
    public let role: TabFeatureRole?
    public let navigation: TabFeatureNavigation?
    public private(set) var isAllowedOnTabBar: Bool
    public let content: Content

    public init(
        _ value: Value,
        title: String,
        systemImage: String,
        labelTint: Color? = nil,
        badgeValue: Int? = nil,
        navigation: TabFeatureNavigation? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.value = value
        self.title = title
        self.systemImage = .init(systemImage)
        self.labelTint = labelTint
        self.badgeValue = badgeValue
        self.role = nil
        self.navigation = navigation
        self.isAllowedOnTabBar = true
        self.content = content()
    }

    public init(
        _ value: Value,
        role: TabFeatureRole? = nil,
        labelTint: Color? = nil,
        badgeValue: Int? = nil,
        navigation: TabFeatureNavigation? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.value = value
        switch role {
        case .search:
            self.title = "Search"
            self.systemImage = "magnifyingglass"
        case .none:
            self.title = nil
            self.systemImage = nil
        }
        self.labelTint = labelTint
        self.badgeValue = badgeValue
        self.role = role
        self.navigation = navigation
        self.isAllowedOnTabBar = true
        self.content = content()
    }

    public var tabFeatureMetadata: [TabFeatureMetadata<Value>] {
        [self.metadata]
    }

    public var metadata: TabFeatureMetadata<Value> {
        TabFeatureMetadata(
            value: self.value,
            title: self.title,
            systemImage: self.systemImage,
            labelTint: self.labelTint,
            badgeValue: self.badgeValue,
            role: self.role,
            navigation: self.navigation,
            isAllowedOnTabBar: self.isAllowedOnTabBar
        )
    }

    public var id: TabFeatureID {
        self.metadata.id
    }

    public var item: TabFeatureItem {
        self.metadata.item
    }

    public func allowedOnTabBar(_ allowed: Bool) -> Self {
        var feature = self
        feature.isAllowedOnTabBar = allowed
        return feature
    }

    func makeBody() -> Content {
        self.content
    }

    var anyNode: TabFeatureBuilder<Value>.AnyTabFeatureNode {
        .init(
            metadata: self.metadata,
            content: AnyView(self.content)
        )
    }
}

extension TabFeatureMetadata {
    var isSearchTab: Bool {
        self.role == .search
    }
}

indirect enum AnyTabFeatureMoreContent<Value: TabFeatureValue> {
    case feature(TabFeatureBuilder<Value>.AnyTabFeatureNode)
    case section(String, [AnyTabFeatureMoreContent<Value>])
    case group([AnyTabFeatureMoreContent<Value>])

    var featureMetadata: [TabFeatureMetadata<Value>] {
        switch self {
        case .feature(let node):
            [node.metadata]
        case .section(_, let content), .group(let content):
            content.flatMap(\.featureMetadata)
        }
    }
}

@resultBuilder
public enum TabFeatureBuilder<Value: TabFeatureValue> {
    indirect enum Content {
        case feature(AnyTabFeatureNode)
        case section(String, Content)
        case group([Content])
        case metadata([TabFeatureMetadata<Value>])

        var tabFeatureMetadata: [TabFeatureMetadata<Value>] {
            switch self {
            case .feature(let node):
                [node.metadata]
            case .section(_, let content):
                content.tabFeatureMetadata
            case .group(let children):
                children.flatMap(\.tabFeatureMetadata)
            case .metadata(let metadata):
                metadata
            }
        }

        func featureBody(for id: TabFeatureID) -> AnyView? {
            switch self {
            case .feature(let node):
                return node.metadata.id == id ? node.content : nil
            case .section(_, let content):
                return content.featureBody(for: id)
            case .group(let children):
                for child in children {
                    if let body = child.featureBody(for: id) {
                        return body
                    }
                }
                return nil
            case .metadata:
                return nil
            }
        }

        func moreContent(for ids: Set<TabFeatureID>) -> [AnyTabFeatureMoreContent<Value>] {
            switch self {
            case .feature(let node):
                guard !node.metadata.isAllowedOnTabBar || ids.contains(node.metadata.id) else {
                    return []
                }
                return [.feature(node)]
            case .section(let title, let content):
                let content = content.moreContent(for: ids)
                return content.isEmpty ? [] : [.section(title, content)]
            case .group(let children):
                return children.flatMap { $0.moreContent(for: ids) }
            case .metadata:
                return []
            }
        }
    }

    struct AnyTabFeatureNode {
        let metadata: TabFeatureMetadata<Value>
        let content: AnyView
    }

    public static func buildExpression<Content: View>(
        _ expression: TabFeature<Value, Content>
    ) -> TabFeatureGroup<Value> {
        TabFeatureGroup(content: .feature(expression.anyNode))
    }

    public static func buildExpression(
        _ expression: TabFeatureGroup<Value>
    ) -> TabFeatureGroup<Value> {
        expression
    }

    public static func buildBlock(
        _ components: TabFeatureGroup<Value>...
    ) -> TabFeatureGroup<Value> {
        TabFeatureGroup(content: .group(components.map(\.content)))
    }

    public static func buildOptional(
        _ component: TabFeatureGroup<Value>?
    ) -> TabFeatureGroup<Value> {
        component ?? TabFeatureGroup()
    }

    public static func buildEither(
        first component: TabFeatureGroup<Value>
    ) -> TabFeatureGroup<Value> {
        component
    }

    public static func buildEither(
        second component: TabFeatureGroup<Value>
    ) -> TabFeatureGroup<Value> {
        component
    }

    public static func buildArray(
        _ components: [TabFeatureGroup<Value>]
    ) -> TabFeatureGroup<Value> {
        TabFeatureGroup(content: .group(components.map(\.content)))
    }

    public static func buildLimitedAvailability(
        _ component: TabFeatureGroup<Value>
    ) -> TabFeatureGroup<Value> {
        component
    }
}

public func Section<Value: TabFeatureValue>(
    _ title: String,
    @TabFeatureBuilder<Value> content: () -> TabFeatureGroup<Value>
) -> TabFeatureGroup<Value> {
    TabFeatureGroup(content: .section(title, content().content))
}

public extension TabFeatureContent {
    var tabFeatureItems: [TabFeatureItem] {
        self.tabFeatureMetadata.map(\.item)
    }

    func resolve(
        layout: TabFeatureLayout,
        policy: TabFeaturePolicy
    ) -> ResolvedDeclaredTabFeatures<Value> {
        let allowedMetadata = self.tabFeatureMetadata.filter(\.isAllowedOnTabBar)
        let searchTab = allowedMetadata.first(where: \.isSearchTab)
        let nonSearchMetadata = allowedMetadata.filter { !$0.isSearchTab }
        let metadataByID = Dictionary(
            uniqueKeysWithValues: nonSearchMetadata.map { ($0.id, $0) }
        )
        let nonSearchItems = nonSearchMetadata.map(\.item)
        let resolved = TabFeatureResolver.resolve(
            availableItems: nonSearchItems,
            layout: layout,
            policy: policy
        )

        return ResolvedDeclaredTabFeatures(
            visibleFeatures: resolved.visibleIDs.compactMap { metadataByID[$0] },
            overflowFeatures: resolved.overflowIDs.compactMap { metadataByID[$0] },
            searchTab: searchTab
        )
    }

    func defaultPolicy(
        for context: TabFeatureMaxVisibleTabsContext
    ) -> TabFeaturePolicy {
        self.defaultPolicy(
            for: context,
            maxVisibleTabsResolver: defaultTabFeatureMaxVisibleTabs
        )
    }

    func defaultPolicy(
        for context: TabFeatureMaxVisibleTabsContext,
        maxVisibleTabsResolver: TabFeatureMaxVisibleTabsResolver
    ) -> TabFeaturePolicy {
        TabFeaturePolicy(
            fixedVisibleIDs: self.tabFeatureMetadata
                .filter { $0.isAllowedOnTabBar && $0.isSearchTab }
                .map(\.id),
            maxVisibleTabs: maxVisibleTabsResolver(context)
        )
    }
}




struct DemoTab: TabFeatureValue {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init?(_ description: String) {
        self.rawValue = description
    }

    var description: String { self.rawValue }

    static let schedule = Self(rawValue: "schedule")
    static let search = Self(rawValue: "search")
    static let mainStage = Self(rawValue: "stage:main")
}


@MainActor
let features = TabFeatures<DemoTab> {
    TabFeature(
        .schedule,
        title: "Schedule",
        systemImage: "calendar",
        navigation: .stack
    ) {
        Text("Schedule TAB")
            .navigationTitle("Schedule")
    }

    TabFeature(.search, role: .search, navigation: .stack) {
        Text("Search View")
            .navigationTitle("Search")
    }

    TabFeature(.init(rawValue: "stage1"), title: "Stage1", systemImage: "square", navigation: .stack) {
        Text("Stage1 View")
    }

    TabFeature(.init(rawValue: "stage2"), title: "Stage2", systemImage: "square", navigation: .stack) {
        Text("Stage2 View")
    }

    TabFeature(.init(rawValue: "stage3"), title: "Stage3", systemImage: "square", navigation: .stack) {
        Text("Stage3 View")
    }
    TabFeature(.init(rawValue: "stage4"), title: "Stage4", systemImage: "square", navigation: .stack) {
        Text("Stage4 View")
    }
}

#if canImport(Playgrounds) && canImport(CustomDump) && !SKIP
import Playgrounds
import CustomDump

#Playground {
    let resolved = features.resolve(
        layout: .init(preferredIDs: [.init("stage4"), .init("stage2")]),
        policy: .init(fixedVisibleIDs: [.init("search")], maxVisibleTabs: 3)
    )

    customDump(features.tabFeatureMetadata)
    customDump(features.tabFeatureItems)
    customDump(resolved.visibleFeatures)
    customDump(resolved.overflowFeatures)
}
#endif

@available(iOS 18, macOS 15, tvOS 18, visionOS 2, watchOS 11, *)
public struct TabFeaturesView<Value: TabFeatureValue>: View {
    @Binding var selection: Value
    @Binding var layout: TabFeatureLayout
    @Environment(\.tabFeatureMaxVisibleTabsResolver) var maxVisibleTabsResolver
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.tabFeaturesMoreContent) var moreContent

    @State var isMoreSelected = false
    @State var localOverflowSelection: Value?
    let policy: TabFeaturePolicy?
    let overflowSelection: Binding<Value?>?
    let presentationStyle: TabFeaturePresentationStyle
    let features: TabFeatures<Value>

    public init(
        selection: Binding<Value>,
        layout: Binding<TabFeatureLayout>,
        policy: TabFeaturePolicy? = nil,
        overflowSelection: Binding<Value?>? = nil,
        presentationStyle: TabFeaturePresentationStyle = .automatic,
        @TabFeatureBuilder<Value> content: () -> TabFeatureGroup<Value>
    ) {
        self._selection = selection
        self._layout = layout
        self.policy = policy
        self.overflowSelection = overflowSelection
        self.presentationStyle = presentationStyle
        self.features = TabFeatures(content: content)
    }

    public var body: some View {
        let resolved = features.resolve(layout: layout, policy: effectivePolicy)
        let moreFeatureContent = features.moreContent(
            for: Set(resolved.overflowFeatures.map(\.id))
        )
        let showsMore = !moreFeatureContent.isEmpty || moreContent != nil

        switch effectivePresentationStyle {
        case .sidebar:
            sidebarView(
                for: resolved,
                showsMore: showsMore,
                moreFeatureContent: moreFeatureContent
            )
        case .automatic, .tabs:
            tabView(
                for: resolved,
                showsMore: showsMore,
                moreFeatureContent: moreFeatureContent
            )
        }
    }

    @ViewBuilder
    private func tabView(
        for resolved: ResolvedDeclaredTabFeatures<Value>,
        showsMore: Bool,
        moreFeatureContent: [AnyTabFeatureMoreContent<Value>]
    ) -> some View {
        TabView(
            selection: tabSelection(showsMore: showsMore)
        ) {
            if !resolved.visibleFeatures.isEmpty {
                ForEach(resolved.visibleFeatures, id: \.value) { feature in
                    Tab(
                        feature.effectiveTitle,
                        systemImage: feature.effectiveSystemImage.rawValue,
                        value: TabFeaturesSelection.feature(feature.value)
                    ) {
                        primaryFeatureDestination(for: feature)
                    }
                    .tabFeatureBadge(feature.badgeValue)
                }
            }

            if showsMore {
                Tab("More", systemImage: "ellipsis", value: TabFeaturesSelection.more) {
                    TabFeaturesMoreView(
                        overflowSelection: resolvedOverflowSelection,
                        metadata: metadata(for:),
                        overflowFeatureBody: overflowFeatureBody(for:),
                        featureContent: moreFeatureContent,
                        moreContent: moreContent
                    )
                }
                .tabFeatureBadge(resolved.overflowBadgeValue)
            }

            if let searchTab = resolved.searchTab {
                Tab(value: TabFeaturesSelection.feature(searchTab.value), role: .search) {
                    primaryFeatureDestination(for: searchTab)
                }
            }
        }
    }

    @ViewBuilder
    private func sidebarView(
        for resolved: ResolvedDeclaredTabFeatures<Value>,
        showsMore: Bool,
        moreFeatureContent: [AnyTabFeatureMoreContent<Value>]
    ) -> some View {
        #if os(watchOS)
        tabView(
            for: resolved,
            showsMore: showsMore,
            moreFeatureContent: moreFeatureContent
        )
        #else
        NavigationSplitView {
            List {
                ForEach(sidebarFeatures(for: resolved), id: \.value) { feature in
                    Button {
                        sidebarFeatureButtonTapped(feature.value)
                    } label: {
                        TabFeatureSidebarRow(
                            title: feature.effectiveTitle,
                            systemImage: feature.effectiveSystemImage,
                            badgeValue: feature.badgeValue,
                            isSelected: selectedSidebarFeature(for: resolved)?.value == feature.value
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            #if os(iOS) || os(macOS)
            .listStyle(.sidebar)
            #endif
        } detail: {
            if let selectedFeature = selectedSidebarFeature(for: resolved) {
                primaryFeatureDestination(for: selectedFeature)
            } else {
                EmptyView()
            }
        }
        #endif
    }

    private func sidebarFeatures(
        for resolved: ResolvedDeclaredTabFeatures<Value>
    ) -> [TabFeatureMetadata<Value>] {
        var features: [TabFeatureMetadata<Value>] = []
        if let searchTab = resolved.searchTab {
            features.append(searchTab)
        }
        features.append(contentsOf: resolved.visibleFeatures)
        features.append(contentsOf: resolved.overflowFeatures)
        return features
    }

    private func selectedSidebarFeature(
        for resolved: ResolvedDeclaredTabFeatures<Value>
    ) -> TabFeatureMetadata<Value>? {
        let features = sidebarFeatures(for: resolved)
        if let overflowSelection = resolvedOverflowSelection.wrappedValue,
            let overflowFeature = features.first(where: { $0.value == overflowSelection })
        {
            return overflowFeature
        }
        return features.first { $0.value == selection }
    }

    private func sidebarFeatureButtonTapped(_ value: Value) {
        isMoreSelected = false
        if resolvedOverflowSelection.wrappedValue != nil {
            resolvedOverflowSelection.wrappedValue = nil
        }
        selection = value
    }

    private func tabSelection(
        showsMore: Bool
    ) -> Binding<TabFeaturesSelection<Value>> {
        Binding {
            TabFeatureSelectionState(
                selection: selection,
                overflowSelection: resolvedOverflowSelection.wrappedValue,
                isMoreSelected: isMoreSelected
            )
            .tabSelection(showsMore: showsMore)
        } set: { newSelection in
            var state = TabFeatureSelectionState(
                selection: selection,
                overflowSelection: resolvedOverflowSelection.wrappedValue,
                isMoreSelected: isMoreSelected
            )
            state.select(newSelection)

            isMoreSelected = state.isMoreSelected
            if resolvedOverflowSelection.wrappedValue != state.overflowSelection {
                resolvedOverflowSelection.wrappedValue = state.overflowSelection
            }
            if selection != state.selection {
                selection = state.selection
            }
        }
    }

    @ViewBuilder
    private func primaryFeatureDestination(for feature: TabFeatureMetadata<Value>) -> some View {
        if let body = features.featureBody(for: feature.id) {
            switch feature.navigation {
            case .stack:
                NavigationStack {
                    body
                }
            case .none:
                body
            }
        } else {
            EmptyView()
        }
    }

    private func overflowFeatureBody(for feature: TabFeatureMetadata<Value>) -> AnyView? {
        self.features.featureBody(for: feature.id)
    }

    private func metadata(for value: Value) -> TabFeatureMetadata<Value>? {
        self.features.tabFeatureMetadata.first { $0.value == value }
    }

    private var resolvedOverflowSelection: Binding<Value?> {
        self.overflowSelection ?? $localOverflowSelection
    }

    private var effectivePolicy: TabFeaturePolicy {
        self.policy
            ?? self.features.defaultPolicy(
                for: maxVisibleTabsContext,
            maxVisibleTabsResolver: maxVisibleTabsResolver
        )
    }

    private var effectivePresentationStyle: TabFeaturePresentationStyle {
        resolvedTabFeaturePresentationStyle(
            self.presentationStyle,
            for: maxVisibleTabsContext
        )
    }

    private var maxVisibleTabsContext: TabFeatureMaxVisibleTabsContext {
        TabFeatureMaxVisibleTabsContext(
            platform: currentPlatform,
            operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersion,
            horizontalSizeClass: horizontalSizeClass,
            verticalSizeClass: verticalSizeClass
        )
    }

    private var currentPlatform: TabFeaturePlatform {
        #if os(iOS)
        .iOS
        #elseif os(macOS)
        .macOS
        #elseif os(tvOS)
        .tvOS
        #elseif os(visionOS)
        .visionOS
        #elseif os(watchOS)
        .watchOS
        #endif
    }
}

struct TabFeatureSidebarRow: View {
    let title: String
    let systemImage: TabFeatureSymbolName
    let badgeValue: Int?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage.rawValue)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 20)

            Text(title)
                .lineLimit(1)
                .foregroundStyle(.primary)

            Spacer()

            if let badgeValue, badgeValue > 0 {
                TabFeatureBadgeValueView(value: badgeValue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
            }
        }
    }
}

@available(iOS 18, macOS 15, tvOS 18, visionOS 2, watchOS 11, *)
public extension TabFeaturesView {
    func more<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        self.environment(
            \.tabFeaturesMoreContent,
            AnyTabFeaturesMoreContent(
                content: AnyView(content()),
                applyToolbar: { $0 }
            )
        )
    }

    func more<Content: View, Toolbar: ToolbarContent>(
        @ViewBuilder content: () -> Content,
        @ToolbarContentBuilder toolbar: () -> Toolbar
    ) -> some View {
        let toolbar = toolbar()
        return self.environment(
            \.tabFeaturesMoreContent,
            AnyTabFeaturesMoreContent(
                content: AnyView(content()),
                applyToolbar: { view in
                    AnyView(view.toolbar { toolbar })
                }
            )
        )
    }
}

enum TabFeaturesSelection<Value: TabFeatureValue>: Hashable {
    case feature(Value)
    case more
}

struct TabFeatureSelectionState<Value: TabFeatureValue>: Equatable {
    var selection: Value
    var overflowSelection: Value?
    var isMoreSelected: Bool

    func tabSelection(showsMore: Bool) -> TabFeaturesSelection<Value> {
        if isMoreSelected && showsMore {
            .more
        } else {
            .feature(selection)
        }
    }

    mutating func select(_ selection: TabFeaturesSelection<Value>) {
        switch selection {
        case .feature(let value):
            isMoreSelected = false
            self.selection = value
        case .more:
            isMoreSelected = true
        }
    }
}

@available(iOS 18.0, macOS 15.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *)
private extension TabContent {
    @TabContentBuilder<Self.TabValue>
    func tabFeatureBadge(_ badgeValue: Int?) -> some TabContent<Self.TabValue> {
        if let badgeValue, badgeValue > 0 {
            self.badge(badgeValue)
        } else {
            self
        }
    }
}

struct TabFeaturesMoreView<Value: TabFeatureValue>: View {
    @Binding var overflowSelection: Value?
    let metadata: (Value) -> TabFeatureMetadata<Value>?
    let overflowFeatureBody: (TabFeatureMetadata<Value>) -> AnyView?
    let featureContent: [AnyTabFeatureMoreContent<Value>]
    let moreContent: AnyTabFeaturesMoreContent?
    @State var path: [Value] = []

    var body: some View {
        let view = AnyView(
            List {
                if !featureContent.isEmpty {
                    moreContentList(featureContent)
                }

                if let moreContent {
                    moreContent.content
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
            .navigationTitle("More")
            .onChange(of: path, initial: true) { _, newPath in
                onChangeOfPath(newPath)
            }
            .onChange(of: overflowSelection, initial: true) { _, newValue in
                onChangeOfOverflowSelection(newValue)
            }
            .navigationDestination(for: Value.self) { value in
                if let feature = metadata(value), let body = overflowFeatureBody(feature) {
                    body
                }
            }
        )

        NavigationStack(path: $path) {
            if let moreContent {
                moreContent.applyToolbar(view)
            } else {
                view
            }
        }
    }

    @ViewBuilder
    private func moreFeatureRow(_ feature: TabFeatureMetadata<Value>) -> some View {
        NavigationLinkButton {
            navigationLinkButtonTapped(feature.value)
        } label: {
            TabFeatureMoreRow(
                title: feature.effectiveTitle,
                systemImage: feature.effectiveSystemImage,
                labelTint: feature.labelTint,
                badgeValue: feature.badgeValue
            )
        }
    }

    @ViewBuilder
    private func moreContentList(
        _ content: [AnyTabFeatureMoreContent<Value>]
    ) -> AnyView {
        AnyView(
            ForEach(content.indices, id: \.self) { index in
                moreContentList(content[index])
            }
        )
    }

    private func moreContentList(
        _ content: AnyTabFeatureMoreContent<Value>
    ) -> AnyView {
        switch content {
        case .feature(let node):
            return AnyView(moreFeatureRow(node.metadata))
        case .section(let title, let content):
            return AnyView(
                SwiftUI.Section {
                    moreContentList(content)
                } header: {
                    Text(title)
                }
            )
        case .group(let content):
            return moreContentList(content)
        }
    }

    private func navigationLinkButtonTapped(_ value: Value) {
        overflowSelection = value
        path = [value]
    }

    private func onChangeOfOverflowSelection(_ value: Value?) {
        if let value, featureContent.flatMap(\.featureMetadata).contains(where: { $0.value == value }) {

        } else {
            if !path.isEmpty {
                path = []
            }
        }
    }

    func onChangeOfPath(_ path: [Value]) {
        if let value = path.first {
            if overflowSelection != value {
                overflowSelection = value
            }
        } else if overflowSelection != nil {
            overflowSelection = nil
        }
    }
}

struct TabFeatureMoreRow: View {
    let title: String
    let systemImage: TabFeatureSymbolName
    let labelTint: Color?
    let badgeValue: Int?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(labelTint ?? .accentColor)
                    .frame(width: 28, height: 28)

                Image(systemName: systemImage.rawValue)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Text(title)
                .foregroundStyle(.primary)

            Spacer()

            if let badgeValue, badgeValue > 0 {
                TabFeatureBadgeValueView(value: badgeValue)
            }
        }
    }
}

struct TabFeatureBadgeValueView: View {
    let value: Int

    var body: some View {
        Text(value, format: .number)
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .frame(minWidth: 20, minHeight: 20)
            .background {
                Capsule(style: .continuous)
                    .fill(.red)
            }
    }
}

#if !SKIP
#Preview {
    @Previewable @State var selection: DemoTab = .schedule
    @Previewable @State var layout: TabFeatureLayout = .init(preferredIDs: [
        "stage1",
        "stage4"
    ])


    if #available(iOS 18, macOS 15, tvOS 18, visionOS 2, watchOS 11, *) {
        TabFeaturesView(
            selection: $selection,
            layout: $layout,
            policy: .init(
                fixedVisibleIDs: ["schedule"],
                maxVisibleTabs: 3
            )
        ) {

            TabFeature(.search, role: .search) {
                NavigationStack {
                    Text("Search View")
                        .navigationTitle("Search")
                }
                .searchable(text: .constant(""))
            }

            TabFeature(
                .schedule,
                title: "Schedule",
                systemImage: "calendar",
                navigation: .stack
            ) {
                Text("Schedule TAB")
                    .toolbar {
                        NavigationLink("Go") {

                        }
                    }
                    .navigationTitle("Schedule")
                    .tint(.red)
            }

            TabFeature(.init(rawValue: "stage1"), title: "Stage1", systemImage: "square", navigation: .stack) {
                Text("Stage1 View")
                    .navigationTitle("Stage 1")
            }
            
            TabFeature(.init(rawValue: "stage2"), title: "Stage2", systemImage: "square", navigation: .stack) {
                Text("Stage2 View")
                    .navigationTitle("Stage 2")
            }

            TabFeature(
                .init(
                    rawValue: "stage3"
                ),
                title: "Stage3",
                systemImage: "square",
                labelTint: .red,
                navigation: .stack
            ) {
                VStack {
                    List {
                        NavigationLink("Forward") {
                            Text("Huzzah")
                                .navigationTitle("Deeper")
                        }
                    }

                }
                .navigationTitle("Stage 3")
            }

            TabFeature(.init(rawValue: "stage4"), title: "Stage4", systemImage: "square", navigation: .stack) {
                Text("Stage4 View")
                    .navigationTitle("Stage 4")
            }


        }
    } else {
        // Fallback on earlier versions
    }
}
#endif
