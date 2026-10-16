import ComposableArchitecture2
import OpenMusicEventLexicon
import SwiftUI

struct StageList: View {
    @Bindable var store: StoreOf<EventPlaceForm>

    var body: some View {
        List {
            ForEach(store.persistentStages) { stage in
                NavigationLink {
                    StageDetail(store: store, stageID: stage.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(stage.name)
                            if let description = stage.description, !description.isEmpty {
                                Text(description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        if store.form.value.persistentStageID == stage.id {
                            Text("Linked")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityIdentifier("button.stage-profile.\(stage.id.description)")
                .contextMenu {
                    if store.form.value.persistentStageID != stage.id {
                        Button("Use for This Place") {
                            store.send(.linkPersistentStageTapped(stage.id))
                        }
                    }
                    if stage.id.authority == store.eventID.authority {
                        Button("Edit Stage Profile") {
                            store.send(.editPersistentStageTapped(stage.id))
                        }
                    }
                }
            }
        }
        .navigationTitle("Stage Profiles")
        .accessibilityIdentifier("view.stage-profiles")
    }
}
