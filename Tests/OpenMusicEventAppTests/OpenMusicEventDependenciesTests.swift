import Dependencies
import OpenMusicEventSourceEditing
import Testing

@testable import OpenMusicEventApp

struct OpenMusicEventDependenciesTests {
    @Test
    func preparedDependenciesUseConstellationBackfillForTangledPullReviews() throws {
        let source = try withDependencies {
            $0.context = .test
            try OpenMusicEventDependencies.prepare(&$0)
        } operation: {
            @Dependency(\.tangledPullReviewListSource) var source
            return source
        }

        #expect(source == .constellationBackfill)
    }
}
