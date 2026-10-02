import OpenMusicEventLexicon
import ATProto
import ComposableArchitecture2
import ComposableForms
import Dependencies
import Foundation
import OpenMusicEventComponents
import OpenMusicEventDatabase
import SQLiteData
import SwiftUI

@Feature
public struct SocialCategoryForm {
    public init() {}

    public struct FormValue: Equatable, Sendable {
        public enum NotificationChoice: String, CaseIterable, Hashable, Sendable {
            case unspecified
            case subscribed
            case unsubscribed
            case unrecognized
        }

        public init(
            name: String = "",
            description: String = "",
            defaultNotificationState: NotificationChoice = .subscribed,
            notificationsRequired: Bool? = nil
        ) {
            self.name = name
            self.description = description
            self.defaultNotificationState = notificationsRequired == true ? .subscribed : defaultNotificationState
            self.notificationsRequired = notificationsRequired
        }

        public var defaultNotificationState: NotificationChoice
        public var description: String
        public var name: String
        public var notificationsRequired: Bool? {
            didSet {
                if notificationsRequired == true {
                    defaultNotificationState = .subscribed
                }
            }
        }

        public var requiresNotifications: Bool {
            get { notificationsRequired == true }
            set { notificationsRequired = newValue }
        }

        var trimmedDescription: String {
            description.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var trimmedName: String {
            name.trimmingCharacters(in: .whitespacesAndNewlines)
        }

    }

    public typealias FormFeature = ComposableForms.Form<FormValue>

    public struct State {
        public typealias MediaEntry = RecordMediaEditing.MediaEntry
        public typealias MediaDraft = RecordMediaEditing.MediaDraft

        public init(
            eventID: Event.ID,
            categoryID: Social.Category.ID? = nil,
            formValue: FormValue = FormValue()
        ) {
            self.categoryID = categoryID
            self.eventID = eventID
            self.form = FormFeature.State(value: formValue)
        }

        public init(category: Social.Category) {
            let choice: FormValue.NotificationChoice = switch category.defaultNotificationState {
            case nil: .unspecified
            case .some(.known(.subscribed)): .subscribed
            case .some(.known(.unsubscribed)): .unsubscribed
            case .some(.unknown): .unrecognized
            }
            self.init(
                eventID: category.event,
                categoryID: category.id,
                formValue: FormValue(
                    name: category.name,
                    description: category.description ?? "",
                    defaultNotificationState: choice,
                    notificationsRequired: category.notificationsRequired
                )
            )
            originalDefaultNotificationState = category.defaultNotificationState
            self.mediaEntries = (category.media ?? []).map { MediaEntry(value: $0) }
        }

        public let categoryID: Social.Category.ID?
        public let eventID: Event.ID
        public var errorMessage: String?
        public var destination: Destination.State?
        public var form: FormFeature.State
        public var isSaving = false
        public var mediaDraft: MediaDraft?
        public var mediaEntries: [MediaEntry] = []
        public var originalDefaultNotificationState: Open<Social.Category.NotificationState>? = nil

        var isEditing: Bool {
            categoryID != nil
        }

        var canSubmit: Bool {
            !isSaving && form.canSubmit && mediaDraft == nil
        }

    }

    public enum Action {
        case addExternalMediaButtonTapped
        case addImageButtonTapped
        case addRecordMediaButtonTapped
        case cancelButtonTapped
        case destination(Destination.Action)
        case form(FormFeature.Action)
        case formSubmitted(FormValue)
        case mediaDeleteButtonTapped(UUID)
        case mediaDraftAltChanged(String)
        case mediaDraftCancelButtonTapped
        case mediaDraftDescriptionChanged(String)
        case mediaDraftKindChanged(String)
        case mediaDraftRemoveThumbnailButtonTapped
        case mediaDraftSaveButtonTapped
        case mediaDraftThumbnailURLChanged(String)
        case mediaDraftTitleChanged(String)
        case mediaDraftURIChanged(String)
        case mediaEditButtonTapped(UUID)
        case mediaImageInfoButtonTapped(UUID)
        case mediaMoveButtonTapped(UUID, Int)
        case saveButtonTapped
    }

    @Feature
    public enum Destination {
        case imageInfo(Spawn<ImageInfo>)
        case importImages(Spawn<ImportImages>)
    }

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.date.now) var now

    public var body: some Feature {
        Scope(\.form) {
            FormFeature()
                .onSubmit { value in
                    try store.send(.formSubmitted(value))
                }
        }
        Update { state, action in
            switch action {
            case .addExternalMediaButtonTapped:
                state.mediaDraft = State.MediaDraft(kind: .external)

            case .addImageButtonTapped:
                state.destination = .importImages(Spawn(ImportImages.State(
                    configuration: .socialCategoryMedia
                )))

            case .addRecordMediaButtonTapped:
                state.mediaDraft = State.MediaDraft(kind: .record)

            case .cancelButtonTapped:
                store.addTask { try store.dismiss() }

            case .destination:
                break

            case .form:
                break

            case let .formSubmitted(value):
                guard !state.isSaving else { return }
                guard state.canSubmit else {
                    state.errorMessage = "Fix the highlighted fields."
                    return
                }

                let categoryID = state.categoryID
                let eventID = state.eventID
                let createdAt = now
                let mediaEntries = state.mediaEntries
                let originalDefaultNotificationState = state.originalDefaultNotificationState
                state.errorMessage = nil
                state.isSaving = true

                store.addTask {
                    do {
                        let defaultState: Open<Social.Category.NotificationState>? = switch value.defaultNotificationState {
                        case .unspecified: nil
                        case .subscribed: .known(.subscribed)
                        case .unsubscribed: .known(.unsubscribed)
                        case .unrecognized: originalDefaultNotificationState
                        }
                        let fields = try SocialCategoryRecordEditing.Fields(
                            name: value.trimmedName,
                            description: value.trimmedDescription.isEmpty ? nil : value.trimmedDescription,
                            media: RecordMediaEditing.preparedMedia(mediaEntries),
                            defaultNotificationState: defaultState,
                            notificationsRequired: value.notificationsRequired
                        )
                        try await database.write { db in
                            if let categoryID {
                                try SocialCategoryRecordEditing.update(
                                    categoryID,
                                    eventID: eventID,
                                    fields: fields,
                                    in: db
                                )
                            } else {
                                _ = try SocialCategoryRecordEditing.create(
                                    eventID: eventID,
                                    fields: fields,
                                    createdAt: createdAt,
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
                            $0.errorMessage = "Unable to save this channel."
                            $0.isSaving = false
                        }
                    }
                }

            case .saveButtonTapped:
                guard !state.isSaving else { return }
                store.addTask {
                    try store.send(.form(.submittedForm))
                }

            case let .mediaDeleteButtonTapped(id):
                state.mediaEntries.removeAll { $0.id == id }

            case let .mediaDraftAltChanged(value):
                state.mediaDraft?.thumbnailAlt = value

            case .mediaDraftCancelButtonTapped:
                state.mediaDraft = nil

            case let .mediaDraftDescriptionChanged(value):
                state.mediaDraft?.description = value

            case let .mediaDraftKindChanged(value):
                state.mediaDraft?.mediaKind = value

            case .mediaDraftRemoveThumbnailButtonTapped:
                state.mediaDraft?.removeThumbnail = true
                state.mediaDraft?.thumbnailURL = ""

            case .mediaDraftSaveButtonTapped:
                guard let draft = state.mediaDraft, let value = draft.value() else { return }
                if let id = draft.entryID,
                   let index = state.mediaEntries.firstIndex(where: { $0.id == id }) {
                    state.mediaEntries[index].value = value
                } else {
                    state.mediaEntries.append(State.MediaEntry(value: value))
                }
                state.mediaDraft = nil

            case let .mediaDraftThumbnailURLChanged(value):
                state.mediaDraft?.thumbnailURL = value
                state.mediaDraft?.removeThumbnail = false

            case let .mediaDraftTitleChanged(value):
                state.mediaDraft?.title = value

            case let .mediaDraftURIChanged(value):
                state.mediaDraft?.uri = value

            case let .mediaEditButtonTapped(id):
                guard let entry = state.mediaEntries.first(where: { $0.id == id }) else { return }
                switch entry.value {
                case let .known(.external(value)):
                    state.mediaDraft = State.MediaDraft(entryID: id, external: value)
                case let .known(.record(value)):
                    state.mediaDraft = State.MediaDraft(entryID: id, reference: value)
                case .known(.image), .unknown:
                    break
                }

            case let .mediaImageInfoButtonTapped(id):
                guard let entry = state.mediaEntries.first(where: { $0.id == id }),
                      let image = entry.imageValue else { return }
                state.destination = .imageInfo(Spawn(ImageInfo.State(
                    id: id,
                    image: image.image,
                    configuration: .allImages,
                    sourceLabel: image.displaySource,
                    recordID: state.eventID,
                    previewData: entry.importedImage?.data
                )))

            case let .mediaMoveButtonTapped(id, offset):
                guard let index = state.mediaEntries.firstIndex(where: { $0.id == id }),
                      state.mediaEntries.indices.contains(index + offset) else { return }
                state.mediaEntries.swapAt(index, index + offset)
            }
        }
        .ifLet(\.destination) {
            EmptyFeature()
                .ifCaseLet(\.importImages) { ImportImages() }
                .ifCaseLet(\.imageInfo) {
                    ImageInfo { imageID, image in
                        try store.modify {
                            guard let index = $0.mediaEntries.firstIndex(where: { $0.id == imageID }),
                                  case .known(.image) = $0.mediaEntries[index].value
                            else { return }
                            $0.mediaEntries[index].value = .known(.image(image))
                            $0.mediaEntries[index].importedImage?.image = image
                        }
                    }
                }
        }
        .onEvent(ImportedImagesSubmitted.self) { images, state in
            guard case .importImages = state.destination else { return }
            state.mediaEntries.append(contentsOf: images.map { State.MediaEntry(importedImage: $0) })
        }
    }
}

public struct SocialCategoryFormView: View {
    @Bindable var store: StoreOf<SocialCategoryForm>

    public init(store: StoreOf<SocialCategoryForm>) {
        self.store = store
    }

    public var body: some View {
        Form {
            Section("Channel") {
                TextField("Name", text: $store.form.value.name)
                    #if os(iOS)
                    .textInputAutocapitalization(.words)
                    #endif
                    .onSubmit {
                        store.send(.form(.fieldSubmitted(SocialCategoryFormFieldID.name)))
                    }

                FormFieldValidationStatus(
                    validation: store.form.validation[SocialCategoryFormFieldID.name]
                )

                TextField(
                    "What is this channel for?",
                    text: $store.form.value.description,
                    axis: .vertical
                )
                    .portableLineLimit(2...5)
                    #if os(iOS)
                    .textInputAutocapitalization(.sentences)
                    #endif
            }

            Section("Notifications") {
                Picker("Default subscription", selection: $store.form.value.defaultNotificationState) {
                    Text("Unspecified").tag(SocialCategoryForm.FormValue.NotificationChoice.unspecified)
                    Text("Subscribed").tag(SocialCategoryForm.FormValue.NotificationChoice.subscribed)
                    Text("Unsubscribed").tag(SocialCategoryForm.FormValue.NotificationChoice.unsubscribed)
                    if store.form.value.defaultNotificationState == .unrecognized {
                        Text("Unrecognized value").tag(SocialCategoryForm.FormValue.NotificationChoice.unrecognized)
                    }
                }
                .disabled(store.form.value.requiresNotifications)

                Toggle("Notifications are required", isOn: $store.form.value.requiresNotifications)

                if store.form.value.requiresNotifications {
                    Text("People cannot turn off notifications for this channel.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("People can choose whether to receive notifications from this channel.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            mediaSection

            if let errorMessage = store.errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .disabled(store.isSaving)
        .navigationTitle(store.isEditing ? "Edit Channel" : "New Channel")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { store.send(.cancelButtonTapped) }
            }
            ToolbarItem(placement: .confirmationAction) {
                SubmitButton(
                    isInProgress: store.isSaving,
                    isDisabled: !store.canSubmit
                ) {
                    store.send(.saveButtonTapped)
                }
            }
        }
        .sheet(item: $store.scope(\.destination).importImages) { importStore in
            NavigationStack { ImportImagesView(store: importStore) }
        }
        .sheet(item: $store.scope(\.destination).imageInfo) { imageInfoStore in
            NavigationStack { ImageInfoView(store: imageInfoStore) }
        }
    }

    var mediaSection: some View {
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
                    HStack {
                        VStack(alignment: .leading) {
                            Text(entry.title)
                            if let subtitle = entry.subtitle {
                                Text(subtitle).font(.caption).foregroundStyle(.secondary)
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
                TextField("URL", text: mediaDraftURIBinding)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                if draft.kind == .external {
                    TextField("Title", text: mediaDraftTitleBinding)
                    PortableTextField("Description", text: mediaDraftDescriptionBinding, axis: .vertical)
                        .portableLineLimit(2...5)
                    TextField("Media Kind", text: mediaDraftKindBinding)
                    TextField("Thumbnail URL", text: mediaDraftThumbnailURLBinding)
                    if draft.thumbnail != nil || !draft.thumbnailURL.isEmpty {
                        TextField("Thumbnail Alt Text", text: mediaDraftAltBinding)
                        Button("Remove Thumbnail", role: .destructive) {
                            store.send(.mediaDraftRemoveThumbnailButtonTapped)
                        }
                    }
                }
                if let message = draft.validationMessage {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }
                HStack {
                    Button("Cancel") { store.send(.mediaDraftCancelButtonTapped) }
                    Spacer()
                    Button("Done") { store.send(.mediaDraftSaveButtonTapped) }
                        .disabled(draft.validationMessage != nil)
                }
            }
        }
    }

    var mediaDraftURIBinding: Binding<String> {
        Binding(get: { store.mediaDraft?.uri ?? "" }, set: { store.send(.mediaDraftURIChanged($0)) })
    }

    var mediaDraftTitleBinding: Binding<String> {
        Binding(get: { store.mediaDraft?.title ?? "" }, set: { store.send(.mediaDraftTitleChanged($0)) })
    }

    var mediaDraftDescriptionBinding: Binding<String> {
        Binding(get: { store.mediaDraft?.description ?? "" }, set: { store.send(.mediaDraftDescriptionChanged($0)) })
    }

    var mediaDraftKindBinding: Binding<String> {
        Binding(get: { store.mediaDraft?.mediaKind ?? "" }, set: { store.send(.mediaDraftKindChanged($0)) })
    }

    var mediaDraftThumbnailURLBinding: Binding<String> {
        Binding(get: { store.mediaDraft?.thumbnailURL ?? "" }, set: { store.send(.mediaDraftThumbnailURLChanged($0)) })
    }

    var mediaDraftAltBinding: Binding<String> {
        Binding(get: { store.mediaDraft?.thumbnailAlt ?? "" }, set: { store.send(.mediaDraftAltChanged($0)) })
    }
}

private enum SocialCategoryFormFieldID {
    static var name: AnyHashable { AnyHashable(\SocialCategoryForm.FormValue.name) }
}

private extension SocialCategoryForm.FormFeature {
    init() {
        self.init {
            Self.Field(\.name) {
                Validation(error: "Enter a channel name.") { value in
                    !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            }
        }
    }
}
