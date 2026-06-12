import ComposableArchitecture2
import Dependencies
import ErrorHandling
import Foundation

public struct SourceDataRefreshRequested: FeatureEventKey {
    public init() {}
    public typealias Value = SourceDataRefreshRequest
}

public struct SourceDataRefreshRequest: Equatable, Sendable {
    public var eventID: OMERecord.Event.ID
    public var sourceBaselineID: SourceBaselineRecord.ID

    public init(
        eventID: OMERecord.Event.ID,
        sourceBaselineID: SourceBaselineRecord.ID
    ) {
        self.eventID = eventID
        self.sourceBaselineID = sourceBaselineID
    }
}

public struct SourceDataRefreshClient: Sendable {
    public var refresh: @Sendable (SourceBaselineRecord.ID) async throws -> Void

    public init(
        refresh: @escaping @Sendable (SourceBaselineRecord.ID) async throws -> Void
    ) {
        self.refresh = refresh
    }
}

public extension SourceDataRefreshClient {
    static let noop = Self { _ in }
}

private enum SourceDataRefreshClientKey: DependencyKey {
    static var liveValue: SourceDataRefreshClient {
        SourceDataRefreshClient { _ in
            unimplemented("DependencyValues.sourceDataRefresh.refresh")
        }
    }

    static var testValue: SourceDataRefreshClient {
        .noop
    }
}

public extension DependencyValues {
    var sourceDataRefresh: SourceDataRefreshClient {
        get { self[SourceDataRefreshClientKey.self] }
        set { self[SourceDataRefreshClientKey.self] = newValue }
    }
}

extension UserFacingText {
    static let sourceDataRefreshFailed = Self(
        "Unable to refresh source.",
        fallback: "Unable to refresh source."
    )
}

extension ErrorOperation {
    static let sourceDataRefresh = Self("source.refresh")
}
