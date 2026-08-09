import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventDatabase
import SwiftUI

public struct CommsPostDraft: Equatable, Sendable {
    public var markdown: String
    public var title: String

    public init(
        title: String = "",
        markdown: String = ""
    ) {
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
        }

        public var channelID: OMERecord.Channel.ID
        public var draft: CommsPostDraft
        public var errorMessage: String?
        public var isPreviewing = false
        public var isSaving = false

        public var canSubmit: Bool {
            draft.canSubmit && !isSaving
        }
    }

    public enum Action {
        case cancelButtonTapped
        case saveButtonTapped
    }

    @Dependency(\.date.now) var now
    @Dependency(\.defaultDatabase) var database

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .cancelButtonTapped:
                store.addTask { try store.dismiss() }

            case .saveButtonTapped:
                guard state.canSubmit else { return }
                let channelID = state.channelID
                let draft = state.draft
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
                            try CommsPost.insert {
                                Self.newPost(
                                    channelID: channelID,
                                    draft: draft,
                                    existingPosts: existingPosts,
                                    timestamp: timestamp
                                )
                            }
                            .execute(db)
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

            if let errorMessage = store.errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                formattingButton("Bold", intent: .stronglyEmphasized)
                formattingButton("Italic", intent: .emphasized)
                formattingButton("Code", intent: .code)
            }

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

    @ViewBuilder
    private func formattingButton(_ title: String, intent: InlinePresentationIntent) -> some View {
        Button(title) {
            toggle(intent)
        }
        .buttonStyle(.bordered)
    }

    private func toggle(_ intent: InlinePresentationIntent) {
        var selection = selection

        richText.transformAttributes(in: &selection) { attributes in
            var intents = attributes.inlinePresentationIntent ?? []
            if intents.contains(intent) {
                intents.remove(intent)
            } else {
                intents.insert(intent)
            }
            attributes.inlinePresentationIntent = intents
        }
        self.selection = selection
        markdown = CommsMarkdown.markdown(from: richText)
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
