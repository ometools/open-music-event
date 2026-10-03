import ComposableArchitecture2
import OpenMusicEventComponents
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

struct EventMediaFormSection: View {
    @Bindable var store: StoreOf<EventForm>

    var body: some View {
        Section("Media") {
            ForEach(store.mediaEntries) { entry in
                let index = store.mediaEntries.firstIndex(where: { $0.id == entry.id })
                if let image = entry.imageValue {
                    ImageAssetPickerRowView(
                        recordID: store.eventID,
                        image: image,
                        canMoveUp: index.map { $0 > 0 } ?? false,
                        canMoveDown: index.map { $0 + 1 < store.mediaEntries.count } ?? false
                    ) {
                        store.send(.mediaImageInfoButtonTapped(entry.id))
                    } onRemove: {
                        store.send(.mediaDeleteButtonTapped(entry.id))
                    } onMoveUp: {
                        store.send(.mediaMoveButtonTapped(entry.id, -1))
                    } onMoveDown: {
                        store.send(.mediaMoveButtonTapped(entry.id, 1))
                    }
                } else {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title)
                            if let subtitle = entry.subtitle {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Menu {
                            if entry.canEditLink {
                                Button("Edit") { store.send(.mediaEditButtonTapped(entry.id)) }
                            }
                            Button("Move Up") { store.send(.mediaMoveButtonTapped(entry.id, -1)) }
                                .disabled(index == 0)
                            Button("Move Down") { store.send(.mediaMoveButtonTapped(entry.id, 1)) }
                                .disabled(index == store.mediaEntries.count - 1)
                            Button("Delete", role: .destructive) {
                                store.send(.mediaDeleteButtonTapped(entry.id))
                            }
                        } label: {
                            Label("Media Actions", systemImage: "ellipsis.circle")
                                .labelStyle(.iconOnly)
                        }
                    }
                }
            }

            if store.mediaDraft == nil {
                Menu {
                    Button("Image") { store.send(.addImageButtonTapped) }
                    Button("External Link") { store.send(.addExternalMediaButtonTapped) }
                    Button("AT Protocol Record") { store.send(.addRecordMediaButtonTapped) }
                } label: {
                    Label("Add Media", systemImage: "plus")
                }
            }

            if let draft = store.mediaDraft {
                Text(draft.kind == .external ? "External Media" : "AT Protocol Record")
                    .font(.headline)
                TextField("URL", text: mediaDraftBinding.uri)
                    .accessibilityIdentifier("field.event-media.url")
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                if draft.kind == .external {
                    TextField("Title", text: mediaDraftBinding.title)
                        .accessibilityIdentifier("field.event-media.title")
                    PortableTextField("Description", text: mediaDraftBinding.description, axis: .vertical)
                        .portableLineLimit(2...5)
                    TextField("Media Kind", text: mediaDraftBinding.mediaKind)
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                    TextField("Thumbnail URL", text: mediaDraftBinding.thumbnailURL)
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                    if !draft.removeThumbnail,
                       draft.thumbnail != nil || !draft.thumbnailURL.isEmpty {
                        TextField("Thumbnail Alt Text", text: mediaDraftBinding.thumbnailAlt)
                        Button("Remove Thumbnail", role: .destructive) {
                            store.send(.mediaDraftRemoveThumbnailButtonTapped)
                        }
                    }
                }
                if let validationMessage = draft.validationMessage {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                HStack {
                    Button("Cancel") { store.send(.mediaDraftCancelButtonTapped) }
                    Spacer()
                    Button("Done") { store.send(.mediaDraftSaveButtonTapped) }
                        .accessibilityIdentifier("button.event-media.done")
                        .disabled(draft.validationMessage != nil)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var mediaDraftBinding: Binding<EventForm.MediaDraft> {
        Binding(
            get: { store.mediaDraft ?? EventForm.MediaDraft(kind: .external) },
            set: { store.send(.mediaDraftChanged($0)) }
        )
    }
}
