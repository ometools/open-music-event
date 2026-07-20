import Dependencies
import OpenMusicEventAppEventViewer
import OpenMusicEventSourceEditing

struct SourceAuthoringEntryClient: Sendable {
    var enter: @Sendable (Authoring.Request) async throws -> Authoring.Scope
}

extension SourceAuthoringEntryClient {
    static var live: Self {
        Self { request in
            @Dependency(\.authoringPolicy) var authoringPolicy
            @Dependency(\.sourceEditModePreparation) var sourceEditModePreparation

            let scope = try await authoringPolicy.authorize(request)
            if case let .sourceBaseline(sourceBaselineID) = request.subject {
                try await sourceEditModePreparation.prepare(sourceBaselineID)
            }
            return scope
        }
    }
}

extension DependencyValues {
    var sourceAuthoringEntry: SourceAuthoringEntryClient {
        get { self[SourceAuthoringEntryClientKey.self] }
        set { self[SourceAuthoringEntryClientKey.self] = newValue }
    }
}

private enum SourceAuthoringEntryClientKey: DependencyKey {
    static var liveValue: SourceAuthoringEntryClient {
        .live
    }

    static var testValue: SourceAuthoringEntryClient {
        .live
    }
}
