import ATProto
import ComposableArchitecture2
import OpenMusicEventLexicon
import Testing

@testable import OpenMusicEventAppEventViewer

@MainActor
@Suite("Comms posting", .serialized)
struct CommsPostingTests {
    @Test
    func `Android Markdown fallback is readable`() {
        #expect(
            CommsMarkdown.fallbackText("## Arrival\n\n**Bring ID** and *water*.")
                == "Arrival\n\nBring ID and water."
        )
    }

    @available(iOS 26.0, macOS 26.0, *)
    @Test
    func `rich text editor preserves canonical inline Markdown`() {
        let richText = CommsMarkdown.richEditorText("**Bold** and *italic*.")

        #expect(
            CommsMarkdown.markdown(from: richText)
                == "**Bold** and *italic*."
        )
    }

    @Test
    func `the configured publisher can post without source authoring`() throws {
        let publisherDID = try #require(DID("did:plc:wickedwoods"))

        #expect(
            CommunicationChannelDetail.postingKind(
                configuration: CommsPostingConfiguration(publisherDID: publisherDID),
                selectedAccountID: publisherDID,
                grant: nil
            ) == .direct
        )
    }

    @Test
    func `a direct post emits canonical markdown for the channel owner`() async throws {
        let channelID = channelID()
        let draft = CommsPostDraft(
            title: "  Gates are open  ",
            markdown: "  **Welcome** to Wicked Woods.  "
        )
        let store = TestStore(
            initialState: CommsPostComposer.State(
                channelID: channelID,
                kind: .direct,
                emergencyAvailable: false,
                draft: draft
            )
        ) {
            CommsPostComposer()
        }

        store.send(.submitButtonTapped)

        await store.receive(
            key: CommsPostSubmissionRequested.self,
            value: .equals(CommsPostSubmission(
                channelID: channelID,
                kind: .direct,
                mutation: .create,
                draft: draft
            ))
        )
    }

    @Test
    func `an emergency post needs acknowledgement and confirmation`() async throws {
        let channelID = channelID()
        let draft = CommsPostDraft(
            title: "Evacuate the river field",
            markdown: "Move to the north parking area now.",
            delivery: .emergency(osEmergencyAlert: true)
        )
        let store = TestStore(
            initialState: CommsPostComposer.State(
                channelID: channelID,
                kind: .direct,
                emergencyAvailable: true,
                draft: draft
            )
        ) {
            CommsPostComposer()
        }

        store.send(.submitButtonTapped)

        store.send(.emergencyAcknowledgementChanged(true)) {
            $0.hasAcknowledgedEmergencyAlert = true
        }
        store.send(.submitButtonTapped) {
            $0.showsEmergencyConfirmation = true
        }
        store.send(.emergencyConfirmationConfirmed) {
            $0.showsEmergencyConfirmation = false
        }

        await store.receive(
            key: CommsPostSubmissionRequested.self,
            value: .equals(CommsPostSubmission(
                channelID: channelID,
                kind: .direct,
                mutation: .create,
                draft: draft
            ))
        )
    }

    private func channelID() -> OME.Channel.ID {
        OME.Channel.ID(
            organizerID: OME.Organizer.ID("did:plc:wickedwoods")!,
            eventID: OME.ID<OME.Event>(rawValue: "2026"),
            channelID: OME.ID<OME.Channel>(rawValue: "announcements")
        )
    }
}
