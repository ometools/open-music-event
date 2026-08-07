import ATProto
import ComposableAtmosphereUserInput
import ComposableAtmosphereUserInputUI
import ComposableArchitecture2
import CustomDump
import Dependencies
import Foundation
import Testing

@testable import OpenMusicEventApp

extension UserStoryTests {
    @MainActor
    @Test
    func `a person opens the Open Music Event feedback board`() async throws {
        let boardConfiguration = OpenMusicEventFeedbackBoardConfiguration(
            spaceURI: ATProto.URI(
                authority: "did:plc:feedback-owner",
                collection: UserInputCollection.space.nsid,
                rkey: ATProto.Record.Key(rawValue: "open-music-event")
            ),
            externalURL: URL(string: "https://userinput.app/s/feedback-owner/open-music-event")
        )
        let loadedBoard = UserInputBoardProjection(
            space: UserInputSpaceProjection(
                uri: boardConfiguration.spaceURI,
                record: UserInputSpaceRecord(
                    name: "Open Music Event Feedback",
                    createdAt: "2026-08-07T12:00:00Z"
                )
            )
        )
        let (boardLoads, boardLoadsContinuation) = AsyncStream<
            UserInputFeedbackBoardConfiguration
        >.makeStream()
        var boardLoadsIterator = boardLoads.makeAsyncIterator()
        let store = withDependencies {
            $0.openMusicEventAppConfiguration = OpenMusicEventAppConfiguration(
                productFeedbackBoard: boardConfiguration
            )
            $0.userInputFeedbackBoardClient = UserInputFeedbackBoardClient(
                loadBoard: { configuration in
                    boardLoadsContinuation.yield(configuration)
                    return loadedBoard
                }
            )
        } operation: {
            Store(initialState: Settings.State()) {
                Settings()
            }
        }

        #expect(store.showsFeedbackBoard)

        let navigation = store.send(.feedbackButtonTapped)
        let receivedConfiguration = try #require(await boardLoadsIterator.next())
        boardLoadsContinuation.finish()
        await navigation?.value

        expectNoDifference(
            receivedConfiguration,
            try #require(boardConfiguration.userInputConfiguration)
        )
        expectNoDifference(
            try #require(store.destination?.feedbackBoard?.state.board),
            loadedBoard
        )
    }
}
