import ATProto
import ATProtoOAuth
import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventAuthentication
import OpenMusicEventDatabase
import SwiftUI

public struct CommsPostingConfiguration: Equatable, Sendable {
    public var emergencyChannelIDs: Set<OMERecord.Channel.ID>
    public var publisherDID: DID

    public init(
        publisherDID: DID,
        emergencyChannelIDs: Set<OMERecord.Channel.ID> = []
    ) {
        self.emergencyChannelIDs = emergencyChannelIDs
        self.publisherDID = publisherDID
    }
}

public enum CommsPostPublicationKind: Equatable, Sendable {
    case direct
    case proposal

    var authorizationRequirement: OAuth.AuthRequirement {
        switch self {
        case .direct:
            OpenMusicEventOAuth.commsAnnouncementAuthRequirement
        case .proposal:
            OpenMusicEventOAuth.commsAnnouncementProposalAuthRequirement
        }
    }

    var submitTitle: String {
        switch self {
        case .direct: "Post"
        case .proposal: "Propose"
        }
    }
}

public enum CommsPostDelivery: Equatable, Sendable {
    case standard
    case silent
    case emergency(osEmergencyAlert: Bool)
}

public struct CommsPostDraft: Equatable, Sendable {
    public var delivery: CommsPostDelivery
    public var markdown: String
    public var title: String

    public init(
        title: String = "",
        markdown: String = "",
        delivery: CommsPostDelivery = .standard
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

public enum CommsPostMutation: Equatable, Sendable {
    case create
    case delete(CommsPost.ID)
    case update(CommsPost.ID)
}

public struct CommsPostSubmission: Equatable, Sendable {
    public var channelID: OMERecord.Channel.ID
    public var draft: CommsPostDraft?
    public var kind: CommsPostPublicationKind
    public var mutation: CommsPostMutation

    public init(
        channelID: OMERecord.Channel.ID,
        kind: CommsPostPublicationKind,
        mutation: CommsPostMutation,
        draft: CommsPostDraft? = nil
    ) {
        self.channelID = channelID
        self.draft = draft
        self.kind = kind
        self.mutation = mutation
    }
}

public struct CommsPostPublisherClient: Sendable {
    public var submit: @Sendable (
        CommsPostingConfiguration,
        CommsPostSubmission
    ) async throws -> Void

    public init(
        submit: @escaping @Sendable (
            CommsPostingConfiguration,
            CommsPostSubmission
        ) async throws -> Void
    ) {
        self.submit = submit
    }
}

public enum CommsPostPublishingError: Error, Equatable, Sendable {
    case unconfiguredClient
}

private enum CommsPostingConfigurationKey: DependencyKey {
    static var liveValue: CommsPostingConfiguration? { nil }
    static var testValue: CommsPostingConfiguration? { nil }
}

private enum CommsPostPublisherClientKey: DependencyKey {
    static var liveValue: CommsPostPublisherClient {
        CommsPostPublisherClient { _, _ in
            throw CommsPostPublishingError.unconfiguredClient
        }
    }

    static var testValue: CommsPostPublisherClient { liveValue }
}

public extension DependencyValues {
    var commsPostingConfiguration: CommsPostingConfiguration? {
        get { self[CommsPostingConfigurationKey.self] }
        set { self[CommsPostingConfigurationKey.self] = newValue }
    }

    var commsPostPublisher: CommsPostPublisherClient {
        get { self[CommsPostPublisherClientKey.self] }
        set { self[CommsPostPublisherClientKey.self] = newValue }
    }
}

struct CommsPostSubmissionRequested: FeatureEventKey {
    typealias Value = CommsPostSubmission
}

struct CommsPostPublishingFailed: FeatureEventKey {
    struct Value: Sendable {
        var submission: CommsPostSubmission
        var underlyingError: any Error
    }
}

@Feature
public struct CommsPostComposer {
    public init() {}

    public struct State {
        public init(
            channelID: OMERecord.Channel.ID,
            kind: CommsPostPublicationKind,
            emergencyAvailable: Bool,
            mutation: CommsPostMutation = .create,
            draft: CommsPostDraft = CommsPostDraft()
        ) {
            self.channelID = channelID
            self.draft = draft
            self.emergencyAvailable = emergencyAvailable
            self.kind = kind
            self.mutation = mutation
        }

        public var channelID: OMERecord.Channel.ID
        public var draft: CommsPostDraft
        public var emergencyAvailable: Bool
        public var hasAcknowledgedEmergencyAlert = false
        public var isPreviewing = false
        public var isSubmitting = false
        public var kind: CommsPostPublicationKind
        public var mutation: CommsPostMutation
        public var showsEmergencyConfirmation = false

        public var canSubmit: Bool {
            draft.canSubmit && !isSubmitting && (!isEmergency || hasAcknowledgedEmergencyAlert)
        }

        public var isEmergency: Bool {
            if case .emergency = draft.delivery { return true }
            return false
        }

        public var navigationTitle: String {
            switch mutation {
            case .create:
                kind == .direct ? "New Post" : "New Proposal"
            case .update:
                kind == .direct ? "Edit Post" : "Edit Proposal"
            case .delete:
                "Delete Post"
            }
        }

        public var submitTitle: String {
            kind.submitTitle
        }
    }

    public enum Action {
        case cancelButtonTapped
        case deliveryChanged(CommsPostDelivery)
        case emergencyAcknowledgementChanged(Bool)
        case emergencyConfirmationCancelled
        case emergencyConfirmationConfirmed
        case previewChanged(Bool)
        case submitButtonTapped
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .cancelButtonTapped:
                store.addTask { try store.dismiss() }

            case let .deliveryChanged(delivery):
                if case .emergency = delivery, !state.emergencyAvailable {
                    return
                }
                state.draft.delivery = delivery
                if !state.isEmergency {
                    state.hasAcknowledgedEmergencyAlert = false
                }

            case let .emergencyAcknowledgementChanged(acknowledged):
                state.hasAcknowledgedEmergencyAlert = acknowledged

            case .emergencyConfirmationCancelled:
                state.showsEmergencyConfirmation = false

            case .emergencyConfirmationConfirmed:
                state.showsEmergencyConfirmation = false
                submit(state: state)

            case let .previewChanged(isPreviewing):
                state.isPreviewing = isPreviewing

            case .submitButtonTapped:
                guard state.canSubmit else { return }
                if state.isEmergency {
                    state.showsEmergencyConfirmation = true
                } else {
                    submit(state: state)
                }
            }
        }
    }

    private func submit(state: State) {
        guard state.canSubmit else { return }
        let submission = CommsPostSubmission(
            channelID: state.channelID,
            kind: state.kind,
            mutation: state.mutation,
            draft: state.draft
        )
        store.addTask {
            let task = try store.post(key: CommsPostSubmissionRequested.self, value: submission)
            await task?.value
        }
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
                    selection: Binding(
                        get: { store.isPreviewing },
                        set: { store.send(.previewChanged($0)) }
                    )
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

            Section("Delivery") {
                Toggle(
                    "Post silently",
                    isOn: Binding(
                        get: {
                            if case .silent = store.draft.delivery { return true }
                            return false
                        },
                        set: { isSilent in
                            store.send(.deliveryChanged(isSilent ? .silent : .standard))
                        }
                    )
                )

                if store.emergencyAvailable {
                    Toggle(
                        "Emergency alert",
                        isOn: Binding(
                            get: { store.isEmergency },
                            set: { enabled in
                                store.send(
                                    .deliveryChanged(
                                        enabled
                                            ? .emergency(osEmergencyAlert: true)
                                            : .standard
                                    )
                                )
                            }
                        )
                    )
                }
            }

            if store.isEmergency {
                Section("Critical alerts") {
                    Text("Critical alerts bypass Silent mode and Focus. Use them only for urgent health or safety information that directly affects people and needs immediate attention. They are extremely rare. Never use them for routine updates, schedule changes, or ordinary operational notices.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Toggle(
                        "I confirm this is an urgent health or safety alert.",
                        isOn: Binding(
                            get: { store.hasAcknowledgedEmergencyAlert },
                            set: { store.send(.emergencyAcknowledgementChanged($0)) }
                        )
                    )
                }
            }
        }
        .navigationTitle(store.navigationTitle)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { store.send(.cancelButtonTapped) }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(store.submitTitle) { store.send(.submitButtonTapped) }
                    .disabled(!store.canSubmit)
            }
        }
        .alert("Send critical alert?", isPresented: Binding(
            get: { store.showsEmergencyConfirmation },
            set: { isPresented in
                if !isPresented { store.send(.emergencyConfirmationCancelled) }
            }
        )) {
            Button("Send alert", role: .destructive) {
                store.send(.emergencyConfirmationConfirmed)
            }
            Button("Cancel", role: .cancel) {
                store.send(.emergencyConfirmationCancelled)
            }
        } message: {
            Text("This may bypass Silent mode and Focus for people who receive it.")
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
