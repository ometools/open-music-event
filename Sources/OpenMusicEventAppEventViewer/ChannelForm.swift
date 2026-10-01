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
public struct ChannelForm {
    public init() {}

    public struct FormValue: Equatable, Sendable {
        public init(
            name: String = "",
            description: String = "",
            defaultNotificationState: Social.Category.NotificationState = .subscribed,
            notificationsRequired: Bool = false
        ) {
            self.name = name
            self.description = description
            self.defaultNotificationState = notificationsRequired ? .subscribed : defaultNotificationState
            self.notificationsRequired = notificationsRequired
        }

        public var defaultNotificationState: Social.Category.NotificationState
        public var description: String
        public var name: String
        public var notificationsRequired: Bool {
            didSet {
                if notificationsRequired {
                    defaultNotificationState = .subscribed
                }
            }
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
            self.init(
                eventID: category.event,
                categoryID: category.id,
                formValue: FormValue(
                    name: category.name,
                    description: category.description ?? "",
                    defaultNotificationState: category.defaultNotificationState == .known(.unsubscribed)
                        ? .unsubscribed : .subscribed,
                    notificationsRequired: category.notificationsRequired == true
                )
            )
        }

        public let categoryID: Social.Category.ID?
        public let eventID: Event.ID
        public var errorMessage: String?
        public var form: FormFeature.State
        public var isSaving = false

        var isEditing: Bool {
            categoryID != nil
        }

        var canSubmit: Bool {
            !isSaving && form.canSubmit
        }

    }

    public enum Action {
        case cancelButtonTapped
        case form(FormFeature.Action)
        case formSubmitted(FormValue)
        case saveButtonTapped
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
            case .cancelButtonTapped:
                store.addTask { try store.dismiss() }

            case .form:
                break

            case let .formSubmitted(value):
                guard !state.isSaving else { return }
                guard state.form.canSubmit else {
                    state.errorMessage = "Fix the highlighted fields."
                    return
                }

                let categoryID = state.categoryID
                let eventID = state.eventID
                let createdAt = now
                let fields = SocialCategoryRecordEditing.Fields(
                    name: value.trimmedName,
                    description: value.trimmedDescription.isEmpty ? nil : value.trimmedDescription,
                    defaultNotificationState: value.defaultNotificationState,
                    notificationsRequired: value.notificationsRequired
                )
                state.errorMessage = nil
                state.isSaving = true

                store.addTask {
                    do {
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
            }
        }
    }
}

public struct ChannelFormView: View {
    @Bindable var store: StoreOf<ChannelForm>

    public init(store: StoreOf<ChannelForm>) {
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
                        store.send(.form(.fieldSubmitted(ChannelFormFieldID.name)))
                    }

                FormFieldValidationStatus(
                    validation: store.form.validation[ChannelFormFieldID.name]
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
                    .onSubmit {
                        store.send(.form(.fieldSubmitted(ChannelFormFieldID.description)))
                    }

                FormFieldValidationStatus(
                    validation: store.form.validation[ChannelFormFieldID.description]
                )
            }

            Section("Notifications") {
                Toggle(
                    "Notify people by default",
                    isOn: $store.form.value.defaultNotificationState.isSubscribed
                )
                .disabled(store.form.value.notificationsRequired)

                Toggle("Notifications are required", isOn: $store.form.value.notificationsRequired)

                if store.form.value.notificationsRequired {
                    Text("People cannot turn off notifications for this channel.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("People can choose whether to receive notifications from this channel.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
    }
}

private enum ChannelFormFieldID {
    static var description: AnyHashable { AnyHashable(\ChannelForm.FormValue.description) }
    static var name: AnyHashable { AnyHashable(\ChannelForm.FormValue.name) }
}

private extension ChannelForm.FormFeature {
    init() {
        self.init {
            Self.Field(\.name) {
                Validation(error: "Enter a channel name.") { value in
                    !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            }
            Self.Field(\.description) {
                Validation(error: "Describe what this channel is for.") { value in
                    !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            }
        }
    }
}

private extension Social.Category.NotificationState {
    var isSubscribed: Bool {
        get { self == .subscribed }
        set { self = newValue ? .subscribed : .unsubscribed }
    }
}
