import ComposableArchitecture2
import Dependencies
import Foundation
import SQLiteData
import SwiftUI

@Feature
public struct ContactInfoViewer {
    public init() {}

    public struct State {
        public let eventID: OMERecord.Event.ID
        @FetchOne public var event: OMERecord.Event?
        public var destination: Destination.State?

        public init(
            eventID: OMERecord.Event.ID,
            destination: Destination.State? = nil
        ) {
            self.eventID = eventID
            self.destination = destination
            _event = FetchOne(
                OMERecord.Event.where { $0.id.eq(eventID) }
            )
        }
    }

    public enum Action {
        case destination(Destination.Action)
        case editButtonTapped
    }

    @Feature
    public enum Destination {
        case editContactInfo(Spawn<EditContactInfo>)
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .destination:
                break

            case .editButtonTapped:
                store.withDependencies {
                    state.destination = .editContactInfo(
                        Spawn(EditContactInfo.State(eventID: state.eventID))
                    )
                }
            }
        }
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
    }
}

public struct ContactInfoViewerView: View {
    @Bindable var store: StoreOf<ContactInfoViewer>

    public init(store: StoreOf<ContactInfoViewer>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if let contactNumbers = store.event?.contactNumbers?.displayContactNumbers, !contactNumbers.isEmpty {
                List {
                    ForEach(Array(contactNumbers.enumerated()), id: \.offset) { _, contactNumber in
                        if let url = contactNumber.phoneURL {
                            Link(destination: url) {
                                ContactNumberRow(contactNumber: contactNumber)
                            }
                            .buttonStyle(.plain)
                        } else {
                            ContactNumberRow(contactNumber: contactNumber)
                        }
                    }
                }
                .navigationTitle("Contact Info")
            } else {
                ViewerPlaceholderView(
                    title: "Contact Info",
                    systemImage: "phone",
                    description: store.event == nil
                        ? "This event could not be loaded."
                        : "No contact information has been added to this event yet."
                )
            }
        }
        .toolbar {
            if store.event != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") {
                        store.send(.editButtonTapped)
                    }
                }
            }
        }
        .sheet(item: $store.scope(\.destination, action: \.destination).editContactInfo) { editStore in
            NavigationStack {
                EditContactInfoView(store: editStore)
            }
        }
    }
}

@Feature
public struct EditContactInfo {
    public init() {}

    public struct State {
        public init(eventID: OMERecord.Event.ID) {
            self.eventID = eventID
        }

        let eventID: OMERecord.Event.ID
        var draft: OMERecord.Event.Draft = .placeholder
        var contactNumbers: [EditableContactNumber] = []
        var hasLoadedDraft = false
        var isSaving = false
        var errorMessage: String?

        var preparedContactNumbers: [OMERecord.Event.ContactNumber] {
            contactNumbers.compactMap(\.preparedContactNumber)
        }

        var validationMessage: String? {
            guard hasLoadedDraft else { return nil }
            return nil
        }

        var canSubmit: Bool {
            hasLoadedDraft && !isSaving && validationMessage == nil
        }

        var preparedDraft: OMERecord.Event.Draft {
            var draft = draft
            let contactNumbers = preparedContactNumbers
            draft.contactNumbers = contactNumbers.isEmpty ? nil : contactNumbers
            return draft
        }
    }

    public enum Action {
        case addContactNumberButtonTapped
        case cancelButtonTapped
        case removeContactNumberButtonTapped(UUID)
        case saveButtonTapped
    }

    @Dependency(\.defaultDatabase) var database

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .addContactNumberButtonTapped:
                state.contactNumbers.append(EditableContactNumber())

            case .cancelButtonTapped:
                store.addTask {
                    try store.dismiss()
                }

            case .removeContactNumberButtonTapped(let id):
                state.contactNumbers.removeAll { $0.id == id }

            case .saveButtonTapped:
                guard !state.isSaving else { return }
                guard state.hasLoadedDraft else {
                    state.errorMessage = "This event could not be loaded."
                    return
                }

                guard let validationMessage = state.validationMessage else {
                    state.errorMessage = nil
                    state.isSaving = true
                    let draft = state.preparedDraft

                    store.addTask {
                        do {
                            try database.write { db in
                                try OMERecord.Event.upsert {
                                    draft
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
                                $0.errorMessage = "Unable to save contact information."
                                $0.isSaving = false
                            }
                        }
                    }
                    return
                }

                state.errorMessage = validationMessage
            }
        }
        .onMount { state in
            guard !state.hasLoadedDraft else { return }

            do {
                if let event = try database.read({ db in
                    try OMERecord.Event.where { $0.id.eq(state.eventID) }.fetchOne(db)
                }) {
                    state.draft = .init(event)
                    state.contactNumbers = (event.contactNumbers ?? []).map(EditableContactNumber.init)
                    state.hasLoadedDraft = true
                    state.errorMessage = nil
                } else {
                    state.errorMessage = "This event could not be loaded."
                }
            } catch {
                state.errorMessage = "This event could not be loaded."
            }
        }
    }
}

public struct EditContactInfoView: View {
    @Bindable var store: StoreOf<EditContactInfo>

    public init(store: StoreOf<EditContactInfo>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if store.hasLoadedDraft {
                Form {
                    ForEach($store.contactNumbers) { $contactNumber in
                        Section {
                            TextField("Title", text: $contactNumber.title)
                            TextField("Phone Number", text: $contactNumber.phoneNumber)
                                #if os(iOS)
                                .keyboardType(.phonePad)
                                #endif
                            TextField("Description", text: $contactNumber.description, axis: .vertical)
                                .lineLimit(2...4)

                            Button("Remove Contact Number", role: .destructive) {
                                store.send(.removeContactNumberButtonTapped(contactNumber.id))
                            }
                        }
                    }

                    Section {
                        Button("Add Contact Number") {
                            store.send(.addContactNumberButtonTapped)
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
            } else {
                ViewerPlaceholderView(
                    title: "Edit Contact Info",
                    systemImage: "phone",
                    description: "This event could not be loaded."
                )
            }
        }
        .disabled(store.isSaving)
        .navigationTitle("Edit Contact Info")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    store.send(.cancelButtonTapped)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if store.isSaving {
                    ProgressView()
                } else {
                    Button("Save") {
                        store.send(.saveButtonTapped)
                    }
                    .disabled(!store.canSubmit)
                }
            }
        }
    }
}

struct ContactNumberRow: View {
    let contactNumber: OMERecord.Event.ContactNumber

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(contactNumber.displayTitle)
                    .font(.headline)

                Text(contactNumber.phoneNumber.formattedPhoneNumber)
                    .foregroundStyle(.secondary)
                    #if !os(Android)
                    .textSelection(.enabled)
                    #endif

                if let description = contactNumber.displayDescription {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            Image(systemName: "phone.fill")
                .foregroundStyle(.tint)
        }
        .padding(.vertical, 4)
    }
}

public struct EditableContactNumber: Identifiable, Equatable {
    public var id = UUID()
    var title = ""
    var phoneNumber = ""
    var description = ""

    init() {}

    init(_ contactNumber: OMERecord.Event.ContactNumber) {
        self.title = contactNumber.title
        self.phoneNumber = contactNumber.phoneNumber
        self.description = contactNumber.description ?? ""
    }

    var preparedContactNumber: OMERecord.Event.ContactNumber? {
        let phoneNumber = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phoneNumber.isEmpty else { return nil }

        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return OMERecord.Event.ContactNumber(
            phoneNumber: phoneNumber,
            title: title.isEmpty ? "Contact" : title,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
    }
}

private extension Array where Element == OMERecord.Event.ContactNumber {
    var displayContactNumbers: Self {
        filter { !$0.phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

private extension OMERecord.Event.ContactNumber {
    var displayTitle: String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Contact" : title
    }

    var displayDescription: String? {
        let description = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        return description?.isEmpty == false ? description : nil
    }

    var phoneURL: URL? {
        let phoneNumber = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasInternationalPrefix = phoneNumber.first == "+"
        let digits = phoneNumber.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel:\(hasInternationalPrefix ? "+" : "")\(digits)")
    }
}

private extension OMERecord.Event.Draft {
    static var placeholder: Self {
        .init(
            id: .init(
                organizerID: OMERecord.Organizer.ID("did:web:example.com")!,
                eventID: .init("-1")
            ),
            name: "",
            description: nil,
            startDate: nil,
            endDate: nil,
            status: nil,
            mode: nil,
            locations: nil,
            uris: nil,
            timeZone: TimeZone.current,
            imageURL: nil,
            iconImageURL: nil,
            siteMapImageURL: nil,
            contactNumbers: nil,
            categoryConfigs: nil
        )
    }
}

private extension String {
    var formattedPhoneNumber: String {
        let digits = filter(\.isNumber)
        guard digits.count == 10 else { return self }

        let areaCode = digits.prefix(3)
        let prefix = digits.dropFirst(3).prefix(3)
        let lineNumber = digits.suffix(4)
        return "(\(areaCode)) \(prefix)-\(lineNumber)"
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
