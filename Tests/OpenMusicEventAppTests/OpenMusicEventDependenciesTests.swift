import Dependencies
import OpenMusicEventSourceEditing
import Testing

@testable import OpenMusicEventApp

struct OpenMusicEventDependenciesTests {
    @Test
    func preparedDependenciesUseTangledXRPCForTangledPullReviews() throws {
        let source = try withDependencies {
            $0.context = .test
            try OME.prepareDependencies(&$0)
        } operation: {
            @Dependency(\.tangledPullReviewListSource) var source
            return source
        }

        #expect(source == .tangledXRPC)
    }
}
