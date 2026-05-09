import ComposableArchitecture2
import Tagged
import SwiftUI

@Feature
public struct ParticipantDetail {
    public init() {}

    public struct State: Identifiable {
    public let participantID: OMERecord.ID<OMERecord.Participant>

    public init(participantID: OMERecord.ID<OMERecord.Participant>) {
        self.participantID = participantID
    }

    public var id: OMERecord.ID<OMERecord.Participant> { participantID }
    }

    public enum Action {}

    public var body: some Feature {
        Update { _, _ in }
    }
}

public struct ParticipantDetailView: View {
    let store: StoreOf<ParticipantDetail>

    public init(store: StoreOf<ParticipantDetail>) {
        self.store = store
    }

    public var body: some View {
        ContentUnavailableView(
            "Participant",
            systemImage: "person.crop.circle",
            description: Text(verbatim: store.participantID.rawValue.rawValue)
        )
        .navigationTitle("Participant")
    }
}
