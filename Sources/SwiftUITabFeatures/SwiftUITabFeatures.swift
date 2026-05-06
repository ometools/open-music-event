import SwiftUI
import Tagged

public protocol TabFeatureValue: Hashable, LosslessStringConvertible, Sendable {}

extension String: TabFeatureValue {}

public enum TabFeatureTag {}
public typealias TabFeatureID = Tagged<TabFeatureTag, String>

public enum TabFeatureSymbolTag {}
public typealias TabFeatureSymbolName = Tagged<TabFeatureSymbolTag, String>

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

public struct TabFeatureMetadata<Value: TabFeatureValue>: Equatable, Sendable {
    public var value: Value
    public var title: String?
    public var systemImage: TabFeatureSymbolName?
    public var role: TabFeatureRole?
    public var navigation: TabFeatureNavigation?

    public init(
        value: Value,
        title: String? = nil,
        systemImage: TabFeatureSymbolName? = nil,
        role: TabFeatureRole? = nil,
        navigation: TabFeatureNavigation? = nil
    ) {
        self.value = value
        self.title = title
        self.systemImage = systemImage
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

public struct TabFeatureGroup<Value: TabFeatureValue>: TabFeatureContent, Equatable, Sendable {
    public var tabFeatureMetadata: [TabFeatureMetadata<Value>]

    public init(tabFeatureMetadata: [TabFeatureMetadata<Value>] = []) {
        self.tabFeatureMetadata = tabFeatureMetadata
    }
}

public struct TabFeatures<Value: TabFeatureValue>: TabFeatureContent, Equatable, Sendable {
    private let group: TabFeatureGroup<Value>

    public init(
        @TabFeatureBuilder<Value> content: () -> TabFeatureGroup<Value>
    ) {
        self.group = content()
    }

    public var tabFeatureMetadata: [TabFeatureMetadata<Value>] {
        self.group.tabFeatureMetadata
    }
}

public struct TabFeature<Value: TabFeatureValue, Content: View>: TabFeatureContent {
    public let value: Value
    public let title: String?
    public let systemImage: TabFeatureSymbolName?
    public let role: TabFeatureRole?
    public let navigation: TabFeatureNavigation?
    private let makeContent: () -> Content

    public init(
        _ title: String,
        systemImage: String,
        value: Value,
        navigation: TabFeatureNavigation? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.value = value
        self.title = title
        self.systemImage = .init(systemImage)
        self.role = nil
        self.navigation = navigation
        self.makeContent = content
    }

    public init(
        value: Value,
        role: TabFeatureRole,
        navigation: TabFeatureNavigation? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.value = value
        self.title = nil
        self.systemImage = nil
        self.role = role
        self.navigation = navigation
        self.makeContent = content
    }

    public var tabFeatureMetadata: [TabFeatureMetadata<Value>] {
        [self.metadata]
    }

    public var metadata: TabFeatureMetadata<Value> {
        TabFeatureMetadata(
            value: self.value,
            title: self.title,
            systemImage: self.systemImage,
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
        self.makeContent()
    }
}

@resultBuilder
public enum TabFeatureBuilder<Value: TabFeatureValue> {
    public static func buildExpression<Content: View>(
        _ expression: TabFeature<Value, Content>
    ) -> TabFeatureGroup<Value> {
        TabFeatureGroup(tabFeatureMetadata: expression.tabFeatureMetadata)
    }

    public static func buildExpression(
        _ expression: TabFeatureGroup<Value>
    ) -> TabFeatureGroup<Value> {
        expression
    }

    public static func buildBlock(
        _ components: TabFeatureGroup<Value>...
    ) -> TabFeatureGroup<Value> {
        TabFeatureGroup(
            tabFeatureMetadata: components.flatMap(\.tabFeatureMetadata)
        )
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
        TabFeatureGroup(
            tabFeatureMetadata: components.flatMap(\.tabFeatureMetadata)
        )
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
}

public struct TabFeatureItem: Equatable, Sendable {
    public var id: TabFeatureID
    public var title: String
    public var systemImage: TabFeatureSymbolName

    public init(
        id: TabFeatureID,
        title: String,
        systemImage: TabFeatureSymbolName
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
    }
}

public struct TabFeatureLayout: Equatable, Sendable {
    public var preferredIDs: [TabFeatureID]

    public init(preferredIDs: [TabFeatureID] = []) {
        self.preferredIDs = preferredIDs
    }
}

public struct TabFeaturePolicy: Equatable, Sendable {
    public var fixedVisibleIDs: [TabFeatureID]
    public var maxVisibleTabs: Int

    public init(
        fixedVisibleIDs: [TabFeatureID] = [],
        maxVisibleTabs: Int
    ) {
        self.fixedVisibleIDs = fixedVisibleIDs
        self.maxVisibleTabs = maxVisibleTabs
    }
}

public struct ResolvedTabFeatures: Equatable, Sendable {
    public var visibleIDs: [TabFeatureID]
    public var overflowIDs: [TabFeatureID]

    public init(
        visibleIDs: [TabFeatureID],
        overflowIDs: [TabFeatureID]
    ) {
        self.visibleIDs = visibleIDs
        self.overflowIDs = overflowIDs
    }

    public var showsMore: Bool {
        !self.overflowIDs.isEmpty
    }
}

public enum TabFeatureResolver {
    public static func resolve(
        availableItems: [TabFeatureItem],
        layout: TabFeatureLayout,
        policy: TabFeaturePolicy
    ) -> ResolvedTabFeatures {
        let availableIDs = availableItems.map(\.id)
        let availableIDSet = Set(availableIDs)

        let fixedIDs = deduplicated(
            policy.fixedVisibleIDs.filter { availableIDSet.contains($0) }
        )

        let preferredIDs = deduplicated(
            layout.preferredIDs.filter { availableIDSet.contains($0) }
        )
        .filter { !fixedIDs.contains($0) }

        let appendedIDs = availableIDs.filter { id in
            !fixedIDs.contains(id) && !preferredIDs.contains(id)
        }

        let orderedNonFixedIDs = preferredIDs + appendedIDs
        let remainingCapacity = max(policy.maxVisibleTabs - fixedIDs.count, 0)

        let visibleNonFixedIDs = Array(orderedNonFixedIDs.prefix(remainingCapacity))
        let overflowIDs = Array(orderedNonFixedIDs.dropFirst(remainingCapacity))

        return ResolvedTabFeatures(
            visibleIDs: fixedIDs + visibleNonFixedIDs,
            overflowIDs: overflowIDs
        )
    }

    private static func deduplicated(
        _ ids: [TabFeatureID]
    ) -> [TabFeatureID] {
        var seen: Set<TabFeatureID> = []
        var result: [TabFeatureID] = []

        for id in ids where seen.insert(id).inserted {
            result.append(id)
        }

        return result
    }
}
