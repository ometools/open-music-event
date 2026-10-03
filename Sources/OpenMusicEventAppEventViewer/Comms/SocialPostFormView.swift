import ComposableArchitecture2
import Foundation
import OpenMusicEventLexicon
import SwiftUI

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
                    if store.hasLinkCard, let url = store.externalCard.url {
                        Link(store.externalCard.title, destination: url)
                    }
                }
            } else {
                Section("Post") {
                    TextField("Title", text: $store.draft.title)
                        .accessibilityIdentifier("field.social-post.title")
                    CommsMarkdownEditor(markdown: $store.draft.markdown)
                }
            }

            annotationsSection

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

            SocialPostEmbedFormSection(store: store)
            SocialPostSyndicationFormSection(store: store.scope(\.syndications))
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

    private var annotationsSection: some View {
        Section("Text Annotations") {
            ForEach(store.facets) { entry in
                if let index = store.facets.firstIndex(where: { $0.id == entry.id }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.isSupported ? entry.kind.title : "Unsupported Annotation")
                                .font(.headline)
                            if !entry.selectedText.isEmpty {
                                Text(entry.selectedText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Menu {
                            if entry.isSupported {
                                Button("Edit") {
                                    store.send(.editFacetButtonTapped(entry.id))
                                }
                            }
                            Button("Delete", role: .destructive) {
                                store.send(.removeFacetButtonTapped(entry.id))
                            }
                        } label: {
                            Label("Annotation Actions", systemImage: "ellipsis.circle")
                                .labelStyle(.iconOnly)
                        }
                    }

                    if store.editingFacetID == entry.id {
                        Picker("Type", selection: $store.facets[index].kind) {
                            ForEach(SocialPostFacetEntry.Kind.allCases, id: \.rawValue) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }
                        TextField("Text in post", text: $store.facets[index].selectedText)
                            .accessibilityIdentifier("field.social-post.facet-text")
                        TextField(entry.kind.targetTitle, text: $store.facets[index].target)
                            .accessibilityIdentifier("field.social-post.facet-target")
                        Stepper(
                            "Occurrence \(entry.occurrence + 1)",
                            value: $store.facets[index].occurrence,
                            in: 0...max(0, entry.occurrenceCount(in: store.effectiveText) - 1)
                        )
                        if let message = entry.validationMessage(
                            in: store.effectiveText,
                            originalText: store.editingPost?.text
                        ) {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        Button("Done") { store.send(.finishFacetButtonTapped) }
                            .accessibilityIdentifier("button.social-post.facet-done")
                            .disabled(entry.validationMessage(
                                in: store.effectiveText,
                                originalText: store.editingPost?.text
                            ) != nil)
                    } else if let message = entry.validationMessage(
                        in: store.effectiveText,
                        originalText: store.editingPost?.text
                    ) {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            Menu {
                ForEach(SocialPostFacetEntry.Kind.allCases, id: \.rawValue) { kind in
                    Button(kind.title) { store.send(.addFacetButtonTapped(kind)) }
                }
            } label: {
                Label("Add Annotation", systemImage: "plus")
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
            .accessibilityIdentifier("field.social-post.markdown")
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
                .accessibilityIdentifier("field.social-post.markdown")

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
