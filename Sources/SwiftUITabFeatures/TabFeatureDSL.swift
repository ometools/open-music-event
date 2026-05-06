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

private struct TabFeatureMaxVisibleTabsResolverKey: EnvironmentKey {
    static let defaultValue: TabFeatureMaxVisibleTabsResolver = defaultTabFeatureMaxVisibleTabs
}

extension EnvironmentValues {
    var tabFeatureMaxVisibleTabsResolver: TabFeatureMaxVisibleTabsResolver {
        get { self[TabFeatureMaxVisibleTabsResolverKey.self] }
        set { self[TabFeatureMaxVisibleTabsResolverKey.self] = newValue }
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
    public var role: TabFeatureRole?
    public var navigation: TabFeatureNavigation?

    public init(
        value: Value,
        title: String? = nil,
        systemImage: TabFeatureSymbolName? = nil,
        labelTint: Color? = nil,
        role: TabFeatureRole? = nil,
        navigation: TabFeatureNavigation? = nil
    ) {
        self.value = value
        self.title = title
        self.systemImage = systemImage
        self.labelTint = labelTint
        self.role = role
        self.navigation = navigation
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
}

public struct TabFeature<Value: TabFeatureValue, Content: View>: TabFeatureContent {
    public let value: Value
    public let title: String?
    public let systemImage: TabFeatureSymbolName?
    public let labelTint: Color?
    public let role: TabFeatureRole?
    public let navigation: TabFeatureNavigation?
    public let content: Content

    public init(
        _ value: Value,
        title: String,
        systemImage: String,
        labelTint: Color? = nil,
        navigation: TabFeatureNavigation? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.value = value
        self.title = title
        self.systemImage = .init(systemImage)
        self.labelTint = labelTint
        self.role = nil
        self.navigation = navigation
        self.content = content()
    }

    public init(
        _ value: Value,
        role: TabFeatureRole? = nil,
        labelTint: Color? = nil,
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
        self.role = role
        self.navigation = navigation
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
            role: self.role,
            navigation: self.navigation
        )
    }

    public var id: TabFeatureID {
        self.metadata.id
    }

    public var item: TabFeatureItem {
        self.metadata.item
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

@resultBuilder
public enum TabFeatureBuilder<Value: TabFeatureValue> {
    indirect enum Content {
        case feature(AnyTabFeatureNode)
        case group([Content])
        case metadata([TabFeatureMetadata<Value>])

        var tabFeatureMetadata: [TabFeatureMetadata<Value>] {
            switch self {
            case .feature(let node):
                [node.metadata]
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

public extension TabFeatureContent {
    var tabFeatureItems: [TabFeatureItem] {
        self.tabFeatureMetadata.map(\.item)
    }

    func resolve(
        layout: TabFeatureLayout,
        policy: TabFeaturePolicy
    ) -> ResolvedDeclaredTabFeatures<Value> {
        let searchTab = self.tabFeatureMetadata.first(where: \.isSearchTab)
        let nonSearchMetadata = self.tabFeatureMetadata.filter { !$0.isSearchTab }
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
                .filter(\.isSearchTab)
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

import Playgrounds
import CustomDump

#if !SKIP
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

    let policy: TabFeaturePolicy?
    let features: TabFeatures<Value>

    public init(
        selection: Binding<Value>,
        layout: Binding<TabFeatureLayout>,
        policy: TabFeaturePolicy? = nil,
        @TabFeatureBuilder<Value> content: () -> TabFeatureGroup<Value>
    ) {
        self._selection = selection
        self._layout = layout
        self.policy = policy
        self.features = TabFeatures(content: content)
    }

    public var body: some View {
        let resolved = features.resolve(layout: layout, policy: effectivePolicy)

        TabView(selection: tabSelection(for: resolved)) {
            if !resolved.visibleFeatures.isEmpty {
                ForEach(resolved.visibleFeatures, id: \.value) { feature in
                    Tab(
                        feature.effectiveTitle,
                        systemImage: feature.effectiveSystemImage.rawValue,
                        value: TabFeaturesSelection.feature(feature.value)
                    ) {
                        primaryFeatureDestination(for: feature)
                    }
                }
            }

            if resolved.showsMore {
                Tab("More", systemImage: "ellipsis", value: TabFeaturesSelection.more) {
                    TabFeaturesMoreView(
                        selection: $selection,
                        overflowFeatures: resolved.overflowFeatures,
                        metadata: metadata(for:),
                        overflowFeatureBody: overflowFeatureBody(for:)
                    )
                }
            }

            if let searchTab = resolved.searchTab {
                Tab(value: TabFeaturesSelection.feature(searchTab.value), role: .search) {
                    primaryFeatureDestination(for: searchTab)
                }
            }
        }
    }

    private func tabSelection(
        for resolved: ResolvedDeclaredTabFeatures<Value>
    ) -> Binding<TabFeaturesSelection<Value>> {
        Binding {
            if resolved.overflowFeatures.contains(where: { $0.value == selection }) {
                .more
            } else {
                .feature(selection)
            }
        } set: { newValue in
            switch newValue {
            case .feature(let value):
                selection = value
            case .more:
                break
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

    private var effectivePolicy: TabFeaturePolicy {
        self.policy
            ?? self.features.defaultPolicy(
                for: maxVisibleTabsContext,
                maxVisibleTabsResolver: maxVisibleTabsResolver
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

enum TabFeaturesSelection<Value: TabFeatureValue>: Hashable {
    case feature(Value)
    case more
}

struct TabFeaturesMoreView<Value: TabFeatureValue>: View {
    @Binding var selection: Value
    let overflowFeatures: [TabFeatureMetadata<Value>]
    let metadata: (Value) -> TabFeatureMetadata<Value>?
    let overflowFeatureBody: (TabFeatureMetadata<Value>) -> AnyView?

    @State var presentedOverflowFeature: Value?
    @State var path: [Value] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(overflowFeatures, id: \.value) { feature in
                    NavigationLinkButton {
                        navigate(to: feature.value)
                    } label: {
                        TabFeatureMoreRow(
                            title: feature.effectiveTitle,
                            systemImage: feature.effectiveSystemImage,
                            labelTint: feature.labelTint
                        )
                    }
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
            .navigationTitle("More")
            .onChange(of: selection, initial: true) { _, newValue in
                syncFromExternalSelection(newValue)
            }
            .onChange(of: path, initial: true) { _, newPath in
                syncPresentedOverflowFeature(from: newPath)
            }
            .navigationDestination(for: Value.self) { value in
                if let feature = metadata(value), let body = overflowFeatureBody(feature) {
                    body
                }
            }
        }
    }

    private func navigate(to value: Value) {
        presentedOverflowFeature = value
        path = [value]

        if selection != value {
            selection = value
        }
    }

    private func syncFromExternalSelection(_ value: Value) {
        if overflowFeatures.contains(where: { $0.value == value }) {
            presentedOverflowFeature = value

            if path != [value] {
                path = [value]
            }
        } else {
            presentedOverflowFeature = nil

            if !path.isEmpty {
                path = []
            }
        }
    }

    private func syncPresentedOverflowFeature(from path: [Value]) {
        if let value = path.first {
            presentedOverflowFeature = value
        } else {
            presentedOverflowFeature = nil
        }
    }
}

struct TabFeatureMoreRow: View {
    let title: String
    let systemImage: TabFeatureSymbolName
    let labelTint: Color?

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
