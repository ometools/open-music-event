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
            defaultNotificationState: OMERecord.Channel.NotificationState = .subscribed,
            notificationsRequired: Bool = false
        ) {
            self.name = name
            self.description = description
            self.defaultNotificationState = notificationsRequired ? .subscribed : defaultNotificationState
            self.notificationsRequired = notificationsRequired
        }

        public var defaultNotificationState: OMERecord.Channel.NotificationState
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
            eventID: OMERecord.Event.ID,
            channelID: OMERecord.ID<OMERecord.Channel>? = nil,
            formValue: FormValue = FormValue()
        ) {
            self.channelID = channelID
            self.eventID = eventID
            self.form = FormFeature.State(value: formValue)
        }

        public init(channel: OMERecord.Channel) {
            self.init(
                eventID: OMERecord.Event.ID(
                    organizerID: channel.id.organizerID,
                    eventID: channel.id.eventID
                ),
                channelID: channel.id.channelID,
                formValue: FormValue(
                    name: channel.name,
                    description: channel.description,
                    defaultNotificationState: channel.defaultNotificationState,
                    notificationsRequired: channel.notificationsRequired
                )
            )
        }

        public let channelID: OMERecord.ID<OMERecord.Channel>?
        public let eventID: OMERecord.Event.ID
        public var errorMessage: String?
        public var form: FormFeature.State
        public var isSaving = false

        var isEditing: Bool {
            channelID != nil
        }

        var canSubmit: Bool {
            !isSaving && form.canSubmit
        }

        func newChannel(
            value: FormValue,
            in db: Database
        ) throws -> OMERecord.Channel.Draft {
            let channels = try CommunicationsViewer.channelsQuery(eventID: eventID).fetchAll(db)
            let channelID = Self.nextChannelID(value: value, existingChannels: channels)
            let sortIndex = (channels.compactMap(\.sortIndex).max() ?? -1) + 1

            return OMERecord.Channel.Draft(
                id: OMERecord.Channel.ID(
                    organizerID: eventID.organizerID,
                    eventID: eventID.eventID,
                    channelID: channelID
                ),
                name: value.trimmedName,
                description: value.trimmedDescription,
                iconImageURL: nil,
                headerImageURL: nil,
                sortIndex: sortIndex,
                defaultNotificationState: value.notificationsRequired
                    ? .subscribed
                    : value.defaultNotificationState,
                notificationsRequired: value.notificationsRequired
            )
        }

        private static func nextChannelID(
            value: FormValue,
            existingChannels: [OMERecord.Channel]
        ) -> OMERecord.ID<OMERecord.Channel> {
            let base = Self.channelIDBase(for: value.trimmedName)
            let existingIDs = Set(existingChannels.map(\.id.channelID))
            var candidate = base
            var suffix = 2

            while existingIDs.contains(Self.localID(candidate)) {
                candidate = "\(base)-\(suffix)"
                suffix += 1
            }

            return Self.localID(candidate)
        }

        private static func channelIDBase(for name: String) -> String {
            let normalized = name
                .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
                .lowercased()
            let words = normalized
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }

            return words.isEmpty ? "channel" : words.joined(separator: "-")
        }

        private static func localID(_ string: String) -> OMERecord.ID<OMERecord.Channel> {
            OMERecord.ID<OMERecord.Channel>(.init(string))
        }
    }

    public enum Action {
        case cancelButtonTapped
        case form(FormFeature.Action)
        case formSubmitted(FormValue)
        case saveButtonTapped
    }

    @Dependency(\.defaultDatabase) var database

    public var body: some Feature {
        Scope(\.form, action: \.form) {
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

                let channelID = state.channelID
                let eventID = state.eventID
                state.errorMessage = nil
                state.isSaving = true

                store.addTask {
                    do {
                        try await database.write { db in
                            if let channelID {
                                let recordID = OMERecord.Channel.ID(
                                    organizerID: eventID.organizerID,
                                    eventID: eventID.eventID,
                                    channelID: channelID
                                )
                                try OMERecord.Channel.find(recordID).update {
                                    $0.name = value.trimmedName
                                    $0.description = value.trimmedDescription
                                    $0.defaultNotificationState = value.notificationsRequired
                                        ? .subscribed
                                        : value.defaultNotificationState
                                    $0.notificationsRequired = value.notificationsRequired
                                }
                                .execute(db)
                            } else {
                                let formState = State(eventID: eventID, formValue: value)
                                let channel = try formState.newChannel(value: value, in: db)
                                try OMERecord.Channel.insert {
                                    channel
                                }
                                .execute(db)
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

private extension OMERecord.Channel.NotificationState {
    var isSubscribed: Bool {
        get { self == .subscribed }
        set { self = newValue ? .subscribed : .unsubscribed }
    }
}
