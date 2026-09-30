import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventComponents
import OpenMusicEventEditors
import SQLiteData
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

@Feature
public struct ContactInfoViewer {
    public init() {}

    public struct State {
        public let eventID: OMERecord.Event.ID
        @FetchOne public var event: OMERecord.Event?

        public init(eventID: OMERecord.Event.ID) {
            self.eventID = eventID
            _event = FetchOne(
                OMERecord.Event.where { $0.id.eq(eventID) }
            )
        }

        var hasContent: Bool {
            guard let event else { return false }
            return !(event.contactNumbers ?? []).displayContactNumbers.isEmpty
                || !(event.reportingLinks ?? []).isEmpty
        }
    }

    public enum Action {
        case editButtonTapped
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .editButtonTapped:
                let eventID = state.eventID
                store.addTask {
                    let task = try store.post(
                        key: EventEditingRequested.self,
                        value: .editContactInfo(eventID)
                    )
                    await task?.value
                }
            }
        }
    }
}

public struct ContactInfoViewerView: View {
    @Bindable var store: StoreOf<ContactInfoViewer>
    let showsAuthoringControls: Bool

    public init(
        store: StoreOf<ContactInfoViewer>,
        showsAuthoringControls: Bool = true
    ) {
        self.store = store
        self.showsAuthoringControls = showsAuthoringControls
    }

    public var body: some View {
        let reportingLinkCount = store.event?.reportingLinks?.count ?? 0

        Group {
            if store.hasContent {
                List {
                    if let reportingLinks = store.event?.reportingLinks, !reportingLinks.isEmpty {
                        Section("Reporting") {
                            ForEach(reportingLinks.indices, id: \.self) { index in
                                let reportingLink = reportingLinks[index]
                                IncidentReportingLinkRow(reportingLink: reportingLink)
                                .buttonStyle(.plain)
                                .portableAccessibilityHint(
                                    Text("Opens \(reportingLink.name) in a browser.")
                                )
                            }
                        }
                    }

                    if let contactNumbers = store.event?.contactNumbers?.displayContactNumbers,
                       !contactNumbers.isEmpty {
                        Section("Contact Numbers") {
                            ForEach(
                                reportingLinkCount..<(reportingLinkCount + contactNumbers.count),
                                id: \.self
                            ) { rowID in
                                let contactNumber = contactNumbers[rowID - reportingLinkCount]
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
            if showsAuthoringControls, store.event != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        store.send(.editButtonTapped)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                            .labelStyle(.iconOnly)
                    }
                }
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
        var reportingLinks: [EditableReportingLink] = []
        var hasLoadedDraft = false
        var isSaving = false
        var errorMessage: String?

        var preparedContactNumbers: [OMERecord.Event.ContactNumber] {
            contactNumbers.compactMap(\.preparedContactNumber)
        }

        var preparedReportingLinks: [OMERecord.Event.ReportingLink] {
            reportingLinks.compactMap(\.preparedReportingLink)
        }

        var validationMessage: String? {
            guard hasLoadedDraft else { return nil }
            return reportingLinks.compactMap(\.validationMessage).first
        }

        var canSubmit: Bool {
            hasLoadedDraft && !isSaving && validationMessage == nil
        }

        var preparedDraft: OMERecord.Event.Draft {
            var draft = draft
            let contactNumbers = preparedContactNumbers
            draft.contactNumbers = contactNumbers.isEmpty ? nil : contactNumbers
            let reportingLinks = preparedReportingLinks
            draft.reportingLinks = reportingLinks.isEmpty ? nil : reportingLinks
            return draft
        }
    }

    public enum Action {
        case addContactNumberButtonTapped
        case addReportingLinkButtonTapped
        case cancelButtonTapped
        case removeContactNumberButtonTapped(UUID)
        case removeReportingLinkButtonTapped(UUID)
        case saveButtonTapped
    }

    @Dependency(\.defaultDatabase) var database

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .addContactNumberButtonTapped:
                state.contactNumbers.append(EditableContactNumber())

            case .addReportingLinkButtonTapped:
                state.reportingLinks.append(EditableReportingLink())

            case .cancelButtonTapped:
                store.addTask {
                    try store.dismiss()
                }

            case .removeContactNumberButtonTapped(let id):
                state.contactNumbers.removeAll { $0.id == id }

            case .removeReportingLinkButtonTapped(let id):
                state.reportingLinks.removeAll { $0.id == id }

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
                    state.reportingLinks = (event.reportingLinks ?? []).map(EditableReportingLink.init)
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
                            PortableTextField("Description", text: $contactNumber.description, axis: .vertical)
                                .portableLineLimit(2...4)

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

                    ForEach($store.reportingLinks) { $reportingLink in
                        Section("Reporting Link") {
                            TextField("Name", text: $reportingLink.name)
                            TextField("URL", text: $reportingLink.urlString)
                                #if os(iOS)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                #endif
                            PortableTextField(
                                "Description",
                                text: $reportingLink.description,
                                axis: .vertical
                            )
                            .portableLineLimit(2...5)

                            Button("Remove Reporting Link", role: .destructive) {
                                store.send(.removeReportingLinkButtonTapped(reportingLink.id))
                            }
                        }
                    }

                    Section {
                        Button("Add Reporting Link") {
                            store.send(.addReportingLinkButtonTapped)
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
                Button {
                    store.send(.cancelButtonTapped)
                } label: {
                    Label("Cancel", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                }
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
                    .selectableText()
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

struct ReportingLinkRow: View {
    let reportingLink: OMERecord.Event.ReportingLink

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(reportingLink.name)
                    .font(.headline)

                if let description = reportingLink.displayDescription {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            Image(systemName: "link")
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

public struct EditableReportingLink: Identifiable, Equatable {
    public var id = UUID()
    var name = ""
    var urlString = ""
    var description = ""

    init() {}

    init(_ reportingLink: OMERecord.Event.ReportingLink) {
        self.name = reportingLink.name
        self.urlString = reportingLink.url.absoluteString
        self.description = reportingLink.description ?? ""
    }

    var preparedReportingLink: OMERecord.Event.ReportingLink? {
        guard !isEmpty, validationMessage == nil, let url = preparedURL else { return nil }
        return OMERecord.Event.ReportingLink(
            name: trimmedName,
            url: url,
            description: trimmedDescription.nilIfEmpty
        )
    }

    var validationMessage: String? {
        guard !isEmpty else { return nil }
        guard !trimmedName.isEmpty else { return "Enter a reporting link name." }
        guard preparedURL != nil else { return "Enter a valid http or https URL." }
        return nil
    }

    var isEmpty: Bool {
        trimmedName.isEmpty && trimmedURLString.isEmpty && trimmedDescription.isEmpty
    }

    var preparedURL: URL? {
        guard let components = URLComponents(string: trimmedURLString),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host?.isEmpty == false,
              let url = components.url
        else { return nil }

        return url
    }

    var trimmedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedURLString: String {
        urlString.trimmingCharacters(in: .whitespacesAndNewlines)
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

private extension OMERecord.Event.ReportingLink {
    var displayDescription: String? {
        let description = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        return description?.isEmpty == false ? description : nil
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
            contactNumbers: nil
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
