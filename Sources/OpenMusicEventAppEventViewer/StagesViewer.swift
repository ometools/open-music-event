import ComposableArchitecture2
import Tagged
import SwiftUI

@Feature
public struct StageDetail {
    public init() {}

    public struct State: Identifiable {
        public let stageID: OMERecord.ID<OMERecord.Stage>

        public init(stageID: OMERecord.ID<OMERecord.Stage>) {
            self.stageID = stageID
        }

        public var id: OMERecord.ID<OMERecord.Stage> { stageID }
    }

    public enum Action {}

    public var body: some Feature {
        Update { _, _ in }
    }
}

public struct StageDetailView: View {
    let store: StoreOf<StageDetail>

    public init(store: StoreOf<StageDetail>) {
        self.store = store
    }

    public var body: some View {
        ContentUnavailableView(
            "Stage",
            systemImage: "square.grid.2x2",
            description: Text(verbatim: store.stageID.rawValue.rawValue)
        )
        .navigationTitle("Stage")
    }
}
