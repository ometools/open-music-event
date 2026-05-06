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
    public let content: Content

    public init(
        _ value: Value,
        title: String,
        systemImage: String,
        navigation: TabFeatureNavigation? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.value = value
        self.title = title
        self.systemImage = .init(systemImage)
        self.role = nil
        self.navigation = navigation
        self.content = content()
    }

    public init(
        _ value: Value,
        role: TabFeatureRole? = nil,
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


let features = TabFeatures<DemoTab> {
    TabFeature(
        .schedule,
        title: "Schedule",
        systemImage: "calendar",
        navigation: .stack
    ) {
        Text("Schedule TAB")
    }

    TabFeature(.search, role: .search, navigation: .stack) {
        Text("Search View")
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
    customDump(features.tabFeatureMetadata)
}
#endif
