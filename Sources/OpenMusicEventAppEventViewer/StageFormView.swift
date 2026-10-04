import ComposableArchitecture2
import ComposableForms
import OpenMusicEventComponents
import SwiftUI

public struct StageFormView: View {
    @Bindable var store: StoreOf<StageForm>

    public init(store: StoreOf<StageForm>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if store.hasLoadedDraft {
                form
            } else {
                ViewerPlaceholderView(
                    title: store.navigationTitle,
                    systemImage: "square.grid.2x2",
                    description: "This stage profile could not be loaded."
                )
            }
        }
        .disabled(store.isSaving)
        .navigationTitle(store.navigationTitle)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    store.send(.cancelButtonTapped)
                } label: {
                    Label("Cancel", systemImage: "xmark").labelStyle(.iconOnly)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                SubmitButton(isInProgress: store.isSaving, isDisabled: !store.canSubmit) {
                    store.send(.saveButtonTapped)
                }
            }
        }
        .confirmationDialog(
            "Delete this stage profile?",
            isPresented: $store.showsDeleteConfirmation
        ) {
            Button("Delete Stage Profile", role: .destructive) {
                store.send(.deleteConfirmed)
            }
        } message: {
            Text("A profile linked to an event place cannot be deleted.")
        }
        .sheet(item: $store.scope(\.destination).logoImportImages) { importStore in
            NavigationStack { ImportImagesView(store: importStore) }
        }
        .sheet(item: $store.scope(\.destination).logoImageInfo) { imageInfoStore in
            NavigationStack { ImageInfoView(store: imageInfoStore) }
        }
        .sheet(item: $store.scope(\.destination).mediaImportImages) { importStore in
            NavigationStack { ImportImagesView(store: importStore) }
        }
        .sheet(item: $store.scope(\.destination).mediaImageInfo) { imageInfoStore in
            NavigationStack { ImageInfoView(store: imageInfoStore) }
        }
        .sheet(item: $store.scope(\.destination).heroImportImages) { importStore in
            NavigationStack { ImportImagesView(store: importStore) }
        }
        .sheet(item: $store.scope(\.destination).heroImageInfo) { imageInfoStore in
            NavigationStack { ImageInfoView(store: imageInfoStore) }
        }
        .sheet(item: $store.scope(\.destination).posterImportImages) { importStore in
            NavigationStack { ImportImagesView(store: importStore) }
        }
        .sheet(item: $store.scope(\.destination).posterImageInfo) { imageInfoStore in
            NavigationStack { ImageInfoView(store: imageInfoStore) }
        }
    }

    private var form: some View {
        Form {
            Section("Stage Profile") {
                TextField("Name", text: $store.form.value.name)
                FormFieldValidationStatus(
                    validation: store.form.validation[AnyHashable(\StageForm.FormValue.name)]
                )
                PortableTextField(
                    "Description", text: $store.form.value.description, axis: .vertical
                )
                .portableLineLimit(2...6)
            }
            linkSection
            ImageAssetPickerSection(store: store.scope(\.logoImagePicker))
            ImageAssetPickerSection(store: store.scope(\.heroImagePicker))
            ImageAssetPickerSection(store: store.scope(\.posterImagePicker))
            additionalMediaSection
            if store.mode.stageID != nil {
                Section {
                    Button("Delete Stage Profile", role: .destructive) {
                        store.send(.deleteButtonTapped)
                    }
                }
            }
            if let validationMessage = store.validationMessage {
                Section {
                    Text(verbatim: validationMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            if let errorMessage = store.errorMessage {
                Section {
                    Text(verbatim: errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.immediately)
        #endif
    }

    private var linkSection: some View {
        Group {
            Section("Links") {
                ForEach(store.form.value.links) { link in
                    HStack {
                        Text(link.title.isEmpty ? (link.url.isEmpty ? "New Link" : link.url) : link.title)
                            .lineLimit(1)
                        Spacer()
                        Menu {
                            Button("Edit") { store.send(.editLinkButtonTapped(link.id)) }
                            Button("Move Up") { store.send(.moveLinkButtonTapped(link.id, -1)) }
                                .disabled(store.form.value.links.first?.id == link.id)
                            Button("Move Down") { store.send(.moveLinkButtonTapped(link.id, 1)) }
                                .disabled(store.form.value.links.last?.id == link.id)
                            Button("Delete", role: .destructive) {
                                store.send(.removeLinkButtonTapped(link.id))
                            }
                        } label: {
                            Label("Link Actions", systemImage: "ellipsis.circle")
                                .labelStyle(.iconOnly)
                        }
                    }
                }
                Button("Add Link") { store.send(.addLinkButtonTapped) }
            }
            if let index = store.form.value.links.firstIndex(where: { $0.id == store.editingLinkID }) {
                Section("Edit Link") {
                    EditLinkFields(link: $store.form.value.links[index])
                }
            }
        }
    }

    private var additionalMediaSection: some View {
        Section("Additional Media") {
            ForEach(store.additionalMediaEntries) { entry in
                let visibleIDs = store.additionalMediaEntries.map(\.id)
                let index = visibleIDs.firstIndex(of: entry.id)
                if let image = entry.imageValue {
                    ImageAssetPickerRowView(
                        recordID: store.eventID,
                        image: image,
                        canMoveUp: index.map { $0 > 0 } ?? false,
                        canMoveDown: index.map { $0 + 1 < visibleIDs.count } ?? false
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
                                .disabled(index == visibleIDs.count - 1)
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
                    Button("Image") { store.send(.addImageMediaButtonTapped) }
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
                    .accessibilityIdentifier("field.stage-media.url")
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                if draft.kind == .external {
                    TextField("Title", text: mediaDraftBinding.title)
                        .accessibilityIdentifier("field.stage-media.title")
                    PortableTextField(
                        "Description", text: mediaDraftBinding.description, axis: .vertical
                    )
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
                        if draft.thumbnailImageInfoState(recordID: store.eventID) != nil {
                            Button("Thumbnail Info") {
                                store.send(.mediaImageInfoButtonTapped(draft.thumbnailID))
                            }
                        }
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
                        .accessibilityIdentifier("button.stage-media.done")
                        .disabled(draft.validationMessage != nil)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var mediaDraftBinding: Binding<StageForm.MediaDraft> {
        Binding(
            get: { store.mediaDraft ?? StageForm.MediaDraft(kind: .external) },
            set: { store.send(.mediaDraftChanged($0)) }
        )
    }
}
