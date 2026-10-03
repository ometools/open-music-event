import ComposableArchitecture2
import OpenMusicEventComponents
import OpenMusicEventImages
import OpenMusicEventLexicon
import SwiftUI

struct StageDetail: View {
    @Bindable var store: StoreOf<EventPlaceForm>
    let stageID: Stage.ID

    var stage: Stage? {
        store.persistentStages.first { $0.id == stageID }
    }

    var body: some View {
        Group {
            if let stage {
                List {
                    Section("Stage Profile") {
                        Text(stage.name)
                            .font(.title2)
                            .fontWeight(.semibold)
                        if let description = stage.description, !description.isEmpty {
                            Text(description)
                        }
                    }

                    if let links = stage.links, !links.isEmpty {
                        Section("Links") {
                            ForEach(links.indices, id: \.self) { index in
                                let link = links[index]
                                Link(link.title ?? link.url.absoluteString, destination: link.url)
                            }
                        }
                    }

                    let images = (stage.media ?? []).compactMap { medium -> OME.Image? in
                        guard case let .known(.image(image)) = medium else { return nil }
                        return image
                    }
                    if !images.isEmpty {
                        Section("Media") {
                            ForEach(images.indices, id: \.self) { index in
                                ImageAssetAsyncImage(
                                    image: .record(images[index], stage.id),
                                    contentMode: .fit
                                ) {
                                    Image(systemName: "photo")
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 180)
                                .accessibilityLabel(
                                    images[index].alt?.rawValue
                                        ?? images[index].title
                                        ?? "Stage profile image"
                                )
                            }
                        }
                    }

                    Section {
                        if store.form.value.persistentStageID == stage.id {
                            LabeledContent("This Event Place", value: "Linked")
                            Button("Unlink Stage", role: .destructive) {
                                store.send(.unlinkPersistentStageTapped)
                            }
                        } else {
                            Button("Use for This Place") {
                                store.send(.linkPersistentStageTapped(stage.id))
                            }
                        }
                    }
                }
                .navigationTitle(stage.name)
                .toolbar {
                    if stage.id.authority == store.eventID.authority {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Edit") {
                                store.send(.editPersistentStageTapped(stage.id))
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "Stage profile unavailable",
                    systemImage: "square.grid.2x2"
                )
            }
        }
        .accessibilityIdentifier("view.stage-profile.\(stageID.description)")
    }
}
