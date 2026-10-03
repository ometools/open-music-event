import ComposableArchitecture2
import OpenMusicEventLexicon
import SwiftUI

struct SocialPostEmbedFormSection: View {
    @Bindable var store: StoreOf<SocialPostForm>

    var body: some View {
        Group {
            if store.hasRetainedEmbed {
                Section("Embed") {
                    Text("This post has an existing embed.")
                    Button("Remove Embed", role: .destructive) {
                        store.send(.removeEmbedButtonTapped)
                    }
                }
            }

            if store.hasLinkCard {
                Section("Link Card") {
                    TextField("URL", text: $store.externalCard.uri)
                    TextField("Link Title", text: $store.externalCard.title)
                    TextField("Description", text: $store.externalCard.summary)
                    Button("Remove Link Card", role: .destructive) {
                        store.send(.removeLinkCardButtonTapped)
                    }
                }
            } else if store.hasRecordEmbed {
                SocialPostRecordEmbedFields(store: store)
            } else {
                ImageAssetPickerSection(store: store.scope(\.imagePicker))
                if store.imagePicker.images.isEmpty {
                    Section("Embed") {
                        Button("Add Link Card") {
                            store.send(.addLinkCardButtonTapped)
                        }
                        Button("Add Referenced Record") {
                            store.send(.addRecordEmbedButtonTapped)
                        }
                    }
                }
            }
        }
    }
}

struct SocialPostSyndicationFormSection: View {
    @Bindable var store: StoreOf<SocialPostSyndications>

    var body: some View {
        Section("Syndications") {
            ForEach(store.entries) { entry in
                SocialPostSyndicationRow(store: store, entry: entry)
            }
            if store.draft == nil {
                Button("Add Syndication") {
                    store.send(.addButtonTapped)
                }
            }
            if let draft = store.draft {
                SocialPostSyndicationDraftFields(store: store, draft: draft)
            }
        }
    }
}

struct SocialPostRecordEmbedFields: View {
    @Bindable var store: StoreOf<SocialPostForm>

    var body: some View {
        Section("Referenced Record") {
            TextField("Record URI", text: $store.recordEmbed.reference.uri)
                .accessibilityIdentifier("field.social-post.record-uri")
                #if !os(macOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
            TextField("Record CID", text: $store.recordEmbed.reference.cid)
                .accessibilityIdentifier("field.social-post.record-cid")
                #if !os(macOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
            if store.recordEmbed.embed == nil {
                Text("Enter a complete DID-authored record URI and CID.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button("Remove Referenced Record", role: .destructive) {
                store.send(.removeRecordEmbedButtonTapped)
            }
        }
    }
}

struct SocialPostSyndicationRow: View {
    let store: StoreOf<SocialPostSyndications>
    let entry: SocialPostSyndicationEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.source.uri.description)
                    .lineLimit(1)
                Text(entry.source.cid.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Menu {
                Button("Edit") {
                    store.send(.editButtonTapped(entry.id))
                }
                Button("Move Up") {
                    store.send(.moveButtonTapped(entry.id, -1))
                }
                .disabled(store.entries.first?.id == entry.id)
                Button("Move Down") {
                    store.send(.moveButtonTapped(entry.id, 1))
                }
                .disabled(store.entries.last?.id == entry.id)
                Button("Delete", role: .destructive) {
                    store.send(.deleteButtonTapped(entry.id))
                }
            } label: {
                Label("Syndication Actions", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
            }
        }
    }
}

struct SocialPostSyndicationDraftFields: View {
    let store: StoreOf<SocialPostSyndications>
    let draft: SocialPostSyndicationDraft

    var body: some View {
        Group {
            TextField("Record URI", text: uriBinding)
                .accessibilityIdentifier("field.social-post.syndication-uri")
                #if !os(macOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
            TextField("Record CID", text: cidBinding)
                .accessibilityIdentifier("field.social-post.syndication-cid")
                #if !os(macOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
            if draft.reference.source == nil {
                Text("Enter a complete DID-authored record URI and CID.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Cancel") {
                    store.send(.draftCancelButtonTapped)
                }
                Spacer()
                Button("Done") {
                    store.send(.draftSaveButtonTapped)
                }
                .accessibilityIdentifier("button.social-post.syndication-done")
                .disabled(!store.canSaveDraft)
            }
            .buttonStyle(.borderless)
        }
    }

    private var uriBinding: Binding<String> {
        Binding(
            get: { store.draft?.reference.uri ?? "" },
            set: { value in
                guard var draft = store.draft else { return }
                draft.reference.uri = value
                store.send(.draftChanged(draft))
            }
        )
    }

    private var cidBinding: Binding<String> {
        Binding(
            get: { store.draft?.reference.cid ?? "" },
            set: { value in
                guard var draft = store.draft else { return }
                draft.reference.cid = value
                store.send(.draftChanged(draft))
            }
        )
    }
}
