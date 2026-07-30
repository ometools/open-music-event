#if os(Android) || ROBOLECTRIC
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif
import Tagged

public enum TabFeatureTag {}
public typealias TabFeatureID = Tagged<TabFeatureTag, String>

public enum TabFeatureSymbolTag {}
public typealias TabFeatureSymbolName = Tagged<TabFeatureSymbolTag, String>

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
