import ComposableArchitecture2
import ComposableForms
import OpenMusicEventComponents
import SwiftUI

public struct EditPersistentStageView: View {
    @Bindable var store: StoreOf<EditPersistentStage>

    public init(store: StoreOf<EditPersistentStage>) {
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
                    validation: store.form.validation[AnyHashable(\EditPersistentStage.FormValue.name)]
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
}
