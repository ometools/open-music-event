import ComposableArchitecture2
import Dependencies
import Foundation
import ATProto
import ATProtoTypes
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import Sharing
import SQLiteData
import SwiftUI

public struct CommsPostDraft: Equatable, Sendable {
    public var delivery: Social.Post.Delivery?
    public var markdown: String
    public var title: String

    public init(
        title: String = "",
        markdown: String = "",
        delivery: Social.Post.Delivery? = .standard
    ) {
        self.delivery = delivery
        self.markdown = markdown
        self.title = title
    }

    public var trimmedMarkdown: String {
        markdown.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@Feature
public struct SocialPostForm {
    public init() {}

    public struct State {
        public init(
            eventID: Event.ID,
            categoryID: Social.Category.ID?,
            author: DID,
            draft: CommsPostDraft = CommsPostDraft()
        ) {
            self.eventID = eventID
            self.categoryID = categoryID
            self.author = author
            self.editingPost = nil
            self.draft = draft
            self.imagePicker = ImageAssetPicker.State(
                configuration: .communicationPostPhotos
            )
            self._categories = FetchAll(Social.Category.where { $0.event.eq(eventID) })
        }

        public init(post: Social.Post, eventID: Event.ID, author: DID) {
            self.eventID = eventID
            self.categoryID = post.category
            self.author = author
            self.editingPost = post
            let delivery: Social.Post.Delivery?
            if case let .some(.known(known)) = post.delivery {
                delivery = known
            } else {
                delivery = nil
            }
            self.draft = CommsPostDraft(
                title: post.title ?? "",
                markdown: post.text,
                delivery: delivery
            )
            self.imagePicker = ImageAssetPicker.State(
                configuration: .communicationPostPhotos
            )
            self._categories = FetchAll(Social.Category.where { $0.event.eq(eventID) })
        }

        public var eventID: Event.ID
        public var categoryID: Social.Category.ID?
        @FetchAll public var categories: [Social.Category]
        public var author: DID
        public var editingPost: Social.Post?
        public var destination: Destination.State?
        public var draft: CommsPostDraft
        public var errorMessage: String?
        public var imagePicker: ImageAssetPicker.State
        public var isPreviewing = false
        public var isSaving = false
        public var removedEmbed = false

        public var canSubmit: Bool {
            (editingPost != nil || !draft.trimmedTitle.isEmpty)
                && (!draft.trimmedMarkdown.isEmpty
                    || !imagePicker.images.isEmpty
                    || (editingPost?.embed != nil && !removedEmbed))
                && !isSaving
                && (draft.delivery != .emergency || canRequestEmergency)
        }

        public var hasUnknownDelivery: Bool {
            guard let delivery = editingPost?.delivery else { return false }
            if case .unknown = delivery { return true }
            return false
        }

        public var canRequestEmergency: Bool {
            eventID.authority == .did(author)
        }
    }

    public enum Action {
        case cancelButtonTapped
        case destination(Destination.Action)
        case imagePicker(ImageAssetPicker.Action)
        case removeEmbedButtonTapped
        case saveButtonTapped
    }

    @Feature
    public enum Destination {
        case imageInfo(Spawn<ImageInfo>)
        case importImages(Spawn<ImportImages>)
    }

    @Dependency(\.date) var date
    @Dependency(\.defaultDatabase) var database

    public var body: some Feature {
        Scope(\.imagePicker) {
            ImageAssetPicker()
        }
        Update { state, action in
            switch action {
            case .cancelButtonTapped:
                store.addTask { try store.dismiss() }

            case .destination:
                break

            case .imagePicker(.addButtonTapped):
                state.destination = .importImages(
                    Spawn(state.imagePicker.importImagesState())
                )

            case let .imagePicker(.imageInfoButtonTapped(id)):
                guard let imageInfoState = state.imagePicker.imageInfoState(for: id) else {
                    return
                }
                state.destination = .imageInfo(Spawn(imageInfoState))

            case .imagePicker:
                break

            case .removeEmbedButtonTapped:
                state.removedEmbed = true

            case .saveButtonTapped:
                guard state.canSubmit else { return }
                let eventID = state.eventID
                let categoryID = state.categoryID
                let author = state.author
                let draft = state.draft
                let editingPost = state.editingPost
                let images = state.imagePicker.images
                let removedEmbed = state.removedEmbed
                let hasUnknownDelivery = state.hasUnknownDelivery
                let timestamp = date()
                state.errorMessage = nil
                state.isSaving = true
                store.addTask {
                    do {
                        let embed = try Self.preparedEmbed(
                            images: images,
                            existing: editingPost?.embed,
                            removed: removedEmbed
                        )
                        try await database.write { db in
                            var fields = SocialPostRecordEditing.Fields(
                                title: draft.trimmedTitle.isEmpty ? nil : draft.trimmedTitle,
                                text: editingPost?.text == draft.markdown
                                    ? draft.markdown : draft.trimmedMarkdown,
                                delivery: draft.delivery
                            )
                            if let editingPost {
                                fields.facets = fields.text == editingPost.text
                                    ? editingPost.facets : nil
                                fields.embed = embed
                                if hasUnknownDelivery {
                                    fields.delivery = editingPost.delivery
                                }
                                try SocialPostRecordEditing.update(
                                    editingPost.id,
                                    eventID: eventID,
                                    categoryID: categoryID,
                                    author: author,
                                    fields: fields,
                                    updatedAt: timestamp,
                                    in: db
                                )
                            } else {
                                fields.embed = embed
                                _ = try SocialPostRecordEditing.create(
                                    eventID: eventID,
                                    categoryID: categoryID,
                                    author: author,
                                    fields: fields,
                                    createdAt: timestamp,
                                    in: db
                                )
                            }
                        }
                        try store.modify {
                            $0.errorMessage = nil
                            $0.isSaving = false
                        }
                        try store.dismiss()
                    } catch {
                        try store.modify {
                            $0.errorMessage = "Unable to save this post."
                            $0.isSaving = false
                        }
                    }
                }
            }
        }
        .ifLet(\.destination) {
            EmptyFeature()
                .ifCaseLet(\.importImages) {
                    ImportImages()
                }
                .ifCaseLet(\.imageInfo) {
                    ImageInfo { imageID, image in
                        try store.modify {
                            $0.imagePicker.updateImageInfo(
                                imageID: imageID,
                                image: image
                            )
                        }
                    }
                }
        }
        .onEvent(ImportedImagesSubmitted.self) { images, state in
            guard case .importImages = state.destination else { return }
            state.imagePicker.append(images)
        }
    }

    private enum EmbedError: Error {
        case imageUnavailable
    }

    private static func preparedEmbed(
        images: [ImageAssetPicker.ImageValue],
        existing: Social.Post.Embed?,
        removed: Bool
    ) throws -> Social.Post.Embed? {
        guard !images.isEmpty else { return removed ? nil : existing }
        let entries: [Lexicon.JSONValue] = try images.map { value in
            let blob: ATProto.Blob
            if let imported = value.importedImage {
                blob = try stageLocalImageBlob(
                    imported.data,
                    mimeType: ATProto.MIMEType(rawValue: imported.mimeType)
                )
            } else if case let .known(.blob(existingBlob)) = value.image.source {
                blob = existingBlob
            } else {
                throw EmbedError.imageUnavailable
            }
            var blobObject: [String: Lexicon.JSONValue] = [
                "$type": "blob",
                "ref": .object(["$link": .string(blob.ref.rawValue)]),
                "mimeType": .string(blob.mimeType.rawValue),
            ]
            if let size = blob.size { blobObject["size"] = .integer(Int64(size)) }
            return .object([
                "alt": .string(value.image.alt?.rawValue ?? ""),
                "image": .object(blobObject),
            ])
        }
        return Social.Post.Embed([
            "$type": "app.bsky.embed.images",
            "images": .array(entries),
        ])
    }

}

public struct SocialPostFormView: View {
    @Bindable var store: StoreOf<SocialPostForm>

    public init(store: StoreOf<SocialPostForm>) {
        self.store = store
    }

    public var body: some View {
        let emergencyLifetimeInMinutes = 15

        Form {
            Section {
                Picker(
                    "Editor",
                    selection: $store.isPreviewing
                ) {
                    Text("Write").tag(false)
                    Text("Preview").tag(true)
                }
                .pickerStyle(.segmented)
            }

            if store.isPreviewing {
                Section("Preview") {
                    Text(store.draft.trimmedTitle)
                        .font(.headline)
                    CommsMarkdownText(store.draft.trimmedMarkdown)
                }
            } else {
                Section("Post") {
                    TextField("Title", text: $store.draft.title)
                    CommsMarkdownEditor(markdown: $store.draft.markdown)
                }
            }

            Section("Category") {
                Picker("Category", selection: $store.categoryID) {
                    Text("None").tag(Social.Category.ID?.none)
                    ForEach(store.categories, id: \.id) { category in
                        Text(category.name).tag(Optional(category.id))
                    }
                }
            }

            Section("Notification") {
                if store.hasUnknownDelivery {
                    Text("This post uses an unrecognized delivery setting. It will be preserved.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Delivery", selection: $store.draft.delivery) {
                        Text("Unspecified").tag(Social.Post.Delivery?.none)
                        Text("Silent").tag(Social.Post.Delivery?.some(.silent))
                        Text("Standard").tag(Social.Post.Delivery?.some(.standard))
                        Text("Emergency").tag(Social.Post.Delivery?.some(.emergency))
                            .disabled(!store.canRequestEmergency)
                    }
                }
                Text(
                    "Emergency alerts use the operating system's urgent presentation and expire after \(emergencyLifetimeInMinutes) minutes."
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = store.errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if store.editingPost?.embed != nil && !store.removedEmbed && store.imagePicker.images.isEmpty {
                Section("Embed") {
                    Text("This post has an existing embed.")
                    Button("Remove Embed", role: .destructive) {
                        store.send(.removeEmbedButtonTapped)
                    }
                }
            }

            ImageAssetPickerSection(
                store: store.scope(\.imagePicker)
            )
        }
        .navigationTitle(store.editingPost == nil ? "New Post" : "Edit Post")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { store.send(.cancelButtonTapped) }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { store.send(.saveButtonTapped) }
                    .disabled(!store.canSubmit)
            }
        }
        .sheet(item: $store.scope(\.destination).importImages) { importStore in
            NavigationStack {
                ImportImagesView(store: importStore)
            }
        }
        .sheet(item: $store.scope(\.destination).imageInfo) { imageInfoStore in
            NavigationStack {
                ImageInfoView(store: imageInfoStore)
            }
        }
    }
}

struct CommsMarkdownEditor: View {
    @Binding var markdown: String

    var body: some View {
        #if os(Android)
        CommsMarkdownSourceEditor(markdown: $markdown)
        #else
        if #available(iOS 26.0, macOS 26.0, *) {
            CommsRichMarkdownEditor(markdown: $markdown)
        } else {
            CommsMarkdownSourceEditor(markdown: $markdown)
        }
        #endif
    }
}

#if !os(Android)
@available(iOS 26.0, macOS 26.0, *)
private struct CommsRichMarkdownEditor: View {
    @Binding var markdown: String
    @State private var richText: AttributedString
    @State private var selection = AttributedTextSelection()

    init(markdown: Binding<String>) {
        self._markdown = markdown
        self._richText = State(initialValue: CommsMarkdown.richEditorText(markdown.wrappedValue))
    }

    var body: some View {
        TextEditor(text: $richText, selection: $selection)
            .frame(minHeight: 180)
            .onChange(of: richText) { _, value in
                markdown = CommsMarkdown.markdown(from: value)
            }
            .onChange(of: markdown) { _, value in
                guard value != CommsMarkdown.markdown(from: richText) else { return }
                richText = CommsMarkdown.richEditorText(value)
            }
    }
}
#endif

struct CommsMarkdownSourceEditor: View {
    @Binding var markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    formatButton("Bold", template: "**bold text**")
                    formatButton("Italic", template: "*emphasized text*")
                    formatButton("Heading", template: "## Heading")
                    formatButton("List", template: "- List item")
                    formatButton("Link", template: "[link text](https://)")
                }
            }

            TextEditor(text: $markdown)
                .frame(minHeight: 180)

            Text("Markdown is saved as entered. Use Preview to see the published post.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func formatButton(_ title: String, template: String) -> some View {
        Button(title) {
            if markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                markdown = template
            } else {
                markdown += "\n\n" + template
            }
        }
        .buttonStyle(.bordered)
    }
}
