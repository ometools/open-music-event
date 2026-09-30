import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SwiftUI

public struct CommsPostDraft: Equatable, Sendable {
    public var delivery: OME.Announcement.Delivery
    public var markdown: String
    public var title: String

    public init(
        title: String = "",
        markdown: String = "",
        delivery: OME.Announcement.Delivery = .standard
    ) {
        self.delivery = delivery
        self.markdown = markdown
        self.title = title
    }

    public var canSubmit: Bool {
        !trimmedTitle.isEmpty && !trimmedMarkdown.isEmpty
    }

    public var trimmedMarkdown: String {
        markdown.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@Feature
public struct CommsPostComposer {
    public init() {}

    public struct State {
        public init(
            channelID: OMERecord.Channel.ID,
            draft: CommsPostDraft = CommsPostDraft()
        ) {
            self.channelID = channelID
            self.draft = draft
            self.imagePicker = ImageAssetPicker.State(
                configuration: .communicationPostPhotos
            )
        }

        public var channelID: OMERecord.Channel.ID
        public var destination: Destination.State?
        public var draft: CommsPostDraft
        public var errorMessage: String?
        public var imagePicker: ImageAssetPicker.State
        public var isPreviewing = false
        public var isSaving = false

        public var canSubmit: Bool {
            draft.canSubmit && !isSaving
        }
    }

    public enum Action {
        case cancelButtonTapped
        case destination(Destination.Action)
        case imagePicker(ImageAssetPicker.Action)
        case saveButtonTapped
    }

    @Feature
    public enum Destination {
        case imageInfo(Spawn<ImageInfo>)
        case importImages(Spawn<ImportImages>)
    }

    @Dependency(\.date.now) var now
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

            case .saveButtonTapped:
                guard state.canSubmit else { return }
                let channelID = state.channelID
                let draft = state.draft
                let imagePicker = state.imagePicker
                let timestamp = now
                state.errorMessage = nil
                state.isSaving = true
                store.addTask {
                    do {
                        try await database.write { db in
                            let existingPosts = try CommsPost
                                .where { $0.id.organizerID.eq(channelID.organizerID) }
                                .where { $0.id.eventID.eq(channelID.eventID) }
                                .where { $0.id.channelID.eq(channelID.channelID) }
                                .fetchAll(db)
                            var post = Self.newPost(
                                channelID: channelID,
                                draft: draft,
                                existingPosts: existingPosts,
                                timestamp: timestamp
                            )
                            let preparedImages = try imagePicker.materializedImages(
                                context: LocalImageCacheContext(commsPostID: post.id)
                            )
                            post.images = preparedImages.images.isEmpty ? nil : preparedImages.images
                            try CommsPost.insert {
                                post
                            }
                            .execute(db)
                            if !preparedImages.blobs.isEmpty {
                                try LocalImageBlob.insert { preparedImages.blobs }.execute(db)
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
                    ImageInfo { imageID, asset in
                        try store.modify {
                            $0.imagePicker.updateImageInfo(
                                imageID: imageID,
                                asset: asset
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

    static func newPost(
        channelID: OMERecord.Channel.ID,
        draft: CommsPostDraft,
        existingPosts: [CommsPost],
        timestamp: Date
    ) -> CommsPost {
        let words = draft.trimmedTitle
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
        let baseID = words.isEmpty ? "post" : words.joined(separator: "-")
        let existingIDs = Set(existingPosts.map(\.id.postID))
        var postID = CommsPost.PostID(rawValue: baseID)
        var suffix = 2
        while existingIDs.contains(postID) {
            postID = CommsPost.PostID(rawValue: "\(baseID)-\(suffix)")
            suffix += 1
        }

        return CommsPost(
            id: CommsPost.ID(
                organizerID: channelID.organizerID,
                eventID: channelID.eventID,
                channelID: channelID.channelID,
                postID: postID
            ),
            title: draft.trimmedTitle,
            contents: draft.trimmedMarkdown,
            timestamp: timestamp,
            delivery: draft.delivery,
            sortIndex: (existingPosts.map(\.sortIndex).max() ?? -1) + 1
        )
    }
}

public struct CommsPostComposerView: View {
    @Bindable var store: StoreOf<CommsPostComposer>

    public init(store: StoreOf<CommsPostComposer>) {
        self.store = store
    }

    public var body: some View {
        let emergencyLifetimeInMinutes = Int(
            OME.Announcement.Delivery.emergencyTimeToLive / 60
        )

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

            Section("Notification") {
                Picker("Delivery", selection: $store.draft.delivery) {
                    Text("Standard").tag(OME.Announcement.Delivery.standard)
                    Text("Emergency").tag(OME.Announcement.Delivery.emergency)
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

            ImageAssetPickerSection(
                store: store.scope(\.imagePicker)
            )
        }
        .navigationTitle("New Post")
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
