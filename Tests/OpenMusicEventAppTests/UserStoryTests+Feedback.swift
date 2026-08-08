import ATProto
import ComposableAtmosphereUserInput
import ComposableAtmosphereUserInputUI
import ComposableArchitecture2
import CustomDump
import Dependencies
import Foundation
import OpenMusicEventAuthentication
import SQLiteData
import SwiftUI
import TCATProtoAuthentication
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
            try #require(store.destination?.feedbackBoard?.board),
            loadedBoard
        )
    }

    @MainActor
    @Test
    func `a person posts feedback through the authenticated settings route`() async throws {
        let boardConfiguration = OpenMusicEventFeedbackBoardConfiguration(
            spaceURI: ATProto.URI(
                authority: "did:plc:feedback-owner",
                collection: UserInputCollection.space.nsid,
                rkey: ATProto.Record.Key(rawValue: "open-music-event")
            )
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
        let authorizationRequirement = UserInputAuthorization.authFullRequirement
        let database = try UserStory.makePreparedStoryDatabase()
        let authorizationRequestCenter = AuthorizationRequestCenter()
        let observedAuthorizationRequest = Task<AuthorizationRequestCenter.Request?, Never> {
            let requests = await authorizationRequestCenter.requests()
            for await request in requests {
                if let request { return request }
            }
            return nil
        }
        let browserStore = withDependencies {
            $0.context = .test
            $0.date = .constant(Date(timeIntervalSince1970: 1_754_587_200))
            $0.defaultDatabase = database
            $0.openMusicEventAppConfiguration = OpenMusicEventAppConfiguration(
                productFeedbackBoard: boardConfiguration
            )
            $0.oauthAuthorizationBroker = authorizationRequestCenter.broker
            $0.userInputFeedbackBoardClient = UserInputFeedbackBoardClient(
                loadBoard: { _ in loadedBoard },
                createDiscussion: { configuration, draft, createdAt in
                    @Dependency(\.oauthAuthorizationBroker) var authorizationBroker
                    try await authorizationBroker.authorize(authorizationRequirement)
                    return UserInputDiscussionProjection(
                        uri: ATProto.URI(
                            authority: "did:plc:feedback-author",
                            collection: UserInputCollection.discussion.nsid,
                            rkey: ATProto.Record.Key(rawValue: "created-discussion")
                        ),
                        record: draft.record(
                            space: configuration.space,
                            createdAt: createdAt
                        )
                    )
                }
            )
        } operation: {
            Store(initialState: OpenMusicEventBrowser.State()) {
                OpenMusicEventBrowser()
            }
        }
        let settingsStore = browserStore.scope(\.settings, action: \.settings)

        await settingsStore.send(.feedbackButtonTapped)?.value

        let settingsDestinationStore = try #require(
            settingsStore.scope(\.destination, action: \.destination)
        )
        let boardStore: StoreOf<UserInputFeedbackBoard>
        switch Settings.Destination.switch(store: settingsDestinationStore) {
        case .aboutOpenMusicEvent:
            Issue.record("Expected feedback board destination.")
            return
        case .feedbackBoard(let store):
            boardStore = store
        }

        boardStore.send(.addDiscussionButtonTapped)
        let boardDestinationStore = try #require(
            boardStore.scope(\.destination, action: \.destination)
        )
        let composerStore: StoreOf<UserInputDiscussionComposer>
        switch UserInputFeedbackBoard.Destination.switch(store: boardDestinationStore) {
        case .discussionDetail:
            Issue.record("Expected discussion composer destination.")
            return
        case .discussionComposer(let store):
            composerStore = store
        }

        @Bindable var editableComposerStore = composerStore
        $editableComposerStore.draft.title.wrappedValue = "Offline schedule mode"
        $editableComposerStore.draft.body.wrappedValue = "Festival service can be spotty."
        let creation = composerStore.send(.createDiscussionButtonTapped)

        let observedAuthorizationRequestValue = await observedAuthorizationRequest.value
        expectNoDifference(
            try #require(observedAuthorizationRequestValue).requirement,
            authorizationRequirement
        )

        // Presenting root authorization dismounts the composer, not the board-owned operation.
        @Bindable var editableBoardStore = boardStore
        $editableBoardStore.destination.wrappedValue = nil

        await authorizationRequestCenter.succeed()
        await creation?.value

        expectNoDifference(
            boardStore.visibleDiscussions.map(\.record.title),
            ["Offline schedule mode"]
        )
    }
}
