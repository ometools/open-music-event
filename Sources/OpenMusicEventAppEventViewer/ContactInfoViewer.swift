import OpenMusicEventLexicon
import ATProtoTypes
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
        public let eventID: Event.ID
        @FetchOne public var event: Event?

        public init(eventID: Event.ID) {
            self.eventID = eventID
            _event = FetchOne(Event.where { $0.id.eq(eventID) })
        }

        var hasContent: Bool {
            guard let event else { return false }
            return !event.contactLinks.isEmpty || !event.reportingLinks.isEmpty
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
        let reportingLinkCount = store.event?.reportingLinks.count ?? 0

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
                                    Text("Opens \(reportingLink.displayTitle) in a browser.")
                                )
                            }
                        }
                    }

                    if let contactLinks = store.event?.contactLinks, !contactLinks.isEmpty {
                        Section(contactLinks.allSatisfy { $0.url.scheme?.lowercased() == "tel" }
                            ? "Contact Numbers" : "Contact") {
                            ForEach(
                                reportingLinkCount..<(reportingLinkCount + contactLinks.count),
                                id: \.self
                            ) { rowID in
                                let contactLink = contactLinks[rowID - reportingLinkCount]
                                Link(destination: contactLink.url) {
                                    ContactLinkRow(contactLink: contactLink)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .navigationTitle("Contact Info")
            } else {
                ContentUnavailableView {
                    Label("Contact Info", mappedSystemImage: "phone")
                } description: {
                    if store.event == nil {
                        Text("This event could not be loaded.")
                    } else if showsAuthoringControls {
                        Text("Add contact details and reporting links so attendees know how to reach you.")
                    } else {
                        Text("No contact information has been added to this event yet.")
                    }
                } actions: {
                    if showsAuthoringControls, store.event != nil {
                        Button("Add Contact Info") { store.send(.editButtonTapped) }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .navigationTitle("Contact Info")
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
        public init(eventID: Event.ID) {
            self.eventID = eventID
        }

        let eventID: Event.ID
        var event: Event?
        var contactLinks: [EditableCommunicationLink] = []
        var reportingLinks: [EditableCommunicationLink] = []
        var hasLoadedDraft = false
        var isSaving = false
        var errorMessage: String?

        var validationMessage: String? {
            guard hasLoadedDraft else { return nil }
            return contactLinks.compactMap(\.validationMessage).first
                ?? reportingLinks.compactMap(\.validationMessage).first
        }

        var canSubmit: Bool {
            hasLoadedDraft && !isSaving && validationMessage == nil
        }

        var preparedEvent: Event? {
            guard var event else { return nil }
            let original = event.links ?? []
            var editedByIndex: [Int: OME.Link] = [:]
            for row in contactLinks + reportingLinks {
                if let index = row.originalIndex, let link = row.preparedLink {
                    editedByIndex[index] = link
                }
            }
            var links: [OME.Link] = []
            for (index, link) in original.enumerated() {
                if let edited = editedByIndex[index] {
                    links.append(edited)
                } else if !link.isContactOrReporting {
                    links.append(link)
                }
            }
            links += contactLinks.filter { $0.originalIndex == nil }.compactMap(\.preparedLink)
            links += reportingLinks.filter { $0.originalIndex == nil }.compactMap(\.preparedLink)
            event.links = links.isEmpty ? nil : links
            return event
        }
    }

    public enum Action {
        case addContactLinkButtonTapped
        case addReportingLinkButtonTapped
        case cancelButtonTapped
        case removeContactLinkButtonTapped(UUID)
        case removeReportingLinkButtonTapped(UUID)
        case saveButtonTapped
    }

    @Dependency(\.defaultDatabase) var database

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .addContactLinkButtonTapped:
                state.contactLinks.append(EditableCommunicationLink(kind: .contact))

            case .addReportingLinkButtonTapped:
                state.reportingLinks.append(EditableCommunicationLink(kind: .reporting))

            case .cancelButtonTapped:
                store.addTask {
                    try store.dismiss()
                }

            case .removeContactLinkButtonTapped(let id):
                state.contactLinks.removeAll { $0.id == id }

            case .removeReportingLinkButtonTapped(let id):
                state.reportingLinks.removeAll { $0.id == id }

            case .saveButtonTapped:
                guard !state.isSaving else { return }
                guard state.hasLoadedDraft else {
                    state.errorMessage = "This event could not be loaded."
                    return
                }

                guard let validationMessage = state.validationMessage else {
                    guard let original = state.event,
                          let edited = state.preparedEvent else {
                        state.errorMessage = "This event could not be loaded."
                        return
                    }
                    state.errorMessage = nil
                    state.isSaving = true

                    store.addTask {
                        do {
                            try database.write { db in
                                guard var current = try Event.find(original.id).fetchOne(db),
                                      current.links == original.links else {
                                    throw ContactInfoChangedError()
                                }
                                current.links = edited.links
                                try current.validateReferences()
                                try Event.upsert { current }.execute(db)
                            }
                            try store.modify {
                                $0.errorMessage = nil
                                $0.isSaving = false
                            }
                            try store.dismiss()
                        } catch is ContactInfoChangedError {
                            try store.modify {
                                $0.errorMessage = "Contact information changed. Reopen the editor to see the latest values."
                                $0.isSaving = false
                            }
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
                    try Event.where { $0.id.eq(state.eventID) }.fetchOne(db)
                }) {
                    state.event = event
                    state.contactLinks = (event.links ?? []).enumerated().compactMap { index, link in
                        link.isContact ? EditableCommunicationLink(link, originalIndex: index, kind: .contact) : nil
                    }
                    state.reportingLinks = (event.links ?? []).enumerated().compactMap { index, link in
                        link.isReporting ? EditableCommunicationLink(link, originalIndex: index, kind: .reporting) : nil
                    }
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

private struct ContactInfoChangedError: Error {}

public struct EditContactInfoView: View {
    @Bindable var store: StoreOf<EditContactInfo>

    public init(store: StoreOf<EditContactInfo>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if store.hasLoadedDraft {
                Form {
                    ForEach($store.contactLinks) { $contactLink in
                        Section {
                            TextField("Title", text: $contactLink.title)
                            TextField("Phone, email, or URL", text: $contactLink.destinationString)
                                #if os(iOS)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                #endif
                            PortableTextField("Description", text: $contactLink.description, axis: .vertical)
                                .portableLineLimit(2...4)
                            ContactUsePicker(selection: $contactLink.useChoice)

                        } header: {
                            HStack {
                                Text("Contact")
                                Spacer()
                                Menu("Actions") {
                                    Button("Delete Contact", role: .destructive) {
                                        store.send(.removeContactLinkButtonTapped(contactLink.id))
                                    }
                                }
                            }
                        }
                    }

                    Section {
                        Button("Add Contact") {
                            store.send(.addContactLinkButtonTapped)
                        }
                    }

                    ForEach($store.reportingLinks) { $reportingLink in
                        Section {
                            TextField("Name", text: $reportingLink.title)
                            TextField("Phone, email, or URL", text: $reportingLink.destinationString)
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
                            ContactUsePicker(selection: $reportingLink.useChoice)

                        } header: {
                            HStack {
                                Text("Reporting Link")
                                Spacer()
                                Menu("Actions") {
                                    Button("Delete Reporting Link", role: .destructive) {
                                        store.send(.removeReportingLinkButtonTapped(reportingLink.id))
                                    }
                                }
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

struct ContactLinkRow: View {
    let contactLink: OME.Link

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(contactLink.displayTitle)
                    .font(.headline)

                Text(contactLink.displayDestination)
                    .foregroundStyle(.secondary)
                    #if !os(Android)
                    .selectableText()
                    #endif

                if let description = contactLink.displayDescription {
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
    let reportingLink: OME.Link

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(reportingLink.displayTitle)
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

extension OME.Link {
    var displayTitle: String {
        title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? (isReporting ? "Report an Issue" : "Contact")
    }

    var displayDescription: String? {
        description?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var displayDestination: String {
        if url.scheme?.lowercased() == "tel" {
            return String(url.absoluteString.dropFirst(4)).formattedPhoneNumber
        }
        return url.absoluteString
    }
}

public struct EditableCommunicationLink: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case contact
        case reporting
    }

    public var id = UUID()
    let originalIndex: Int?
    let kind: Kind
    let original: OME.Link?
    var title = ""
    var destinationString = ""
    var description = ""
    var useChoice = ""

    init(kind: Kind) {
        self.kind = kind
        self.originalIndex = nil
        self.original = nil
    }

    init(_ link: OME.Link, originalIndex: Int, kind: Kind) {
        self.kind = kind
        self.originalIndex = originalIndex
        self.original = link
        self.title = link.title ?? ""
        self.destinationString = link.url.absoluteString
        self.description = link.description ?? ""
        switch link.role {
        case .known(.contact(let contact)):
            self.useChoice = contact.use?.displayValue ?? ""
        case .known(.reporting(let reporting)):
            self.useChoice = reporting.use?.displayValue ?? ""
        default:
            break
        }
    }

    var preparedLink: OME.Link? {
        guard !isEmpty, validationMessage == nil, let url = preparedURL else { return nil }
        var link = original ?? OME.Link(url: url)
        link.url = url
        link.title = trimmedTitle.nilIfEmpty
        link.description = trimmedDescription.nilIfEmpty
        let use: Open<OME.Link.ContactUse>? = switch useChoice {
        case "": nil
        case "emergency": .known(.emergency)
        case "nonEmergency": .known(.nonEmergency)
        default: .unknown(.string(useChoice))
        }
        switch kind {
        case .contact: link.role = .known(.contact(.init(use: use)))
        case .reporting: link.role = .known(.reporting(.init(use: use)))
        }
        return link
    }

    var validationMessage: String? {
        guard !isEmpty else { return nil }
        if kind == .reporting && trimmedTitle.isEmpty {
            return "Enter a reporting link name."
        }
        guard preparedURL != nil else { return "Enter a valid phone number, email, or URL." }
        return nil
    }

    var isEmpty: Bool {
        trimmedTitle.isEmpty && trimmedDestination.isEmpty && trimmedDescription.isEmpty
            && useChoice.isEmpty
    }

    var preparedURL: URL? {
        let value = trimmedDestination
        guard !value.isEmpty else { return nil }
        if !value.contains(":"), value.contains("@") {
            return URL(string: "mailto:\(value)")
        }
        if !value.contains(":") {
            let digits = value.filter(\.isNumber)
            guard !digits.isEmpty else { return nil }
            return URL(string: "tel:\(value.first == "+" ? "+" : "")\(digits)")
        }
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              ["tel", "sms", "mailto", "http", "https"].contains(scheme),
              let url = components.url
        else { return nil }
        if scheme == "http" || scheme == "https" {
            return components.host?.isEmpty == false ? url : nil
        }
        return components.path.isEmpty ? nil : url
    }

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedDescription: String { description.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedDestination: String { destinationString.trimmingCharacters(in: .whitespacesAndNewlines) }
}

struct ContactUsePicker: View {
    @Binding var selection: String

    var body: some View {
        Picker("Use", selection: $selection) {
            Text("Unspecified").tag("")
            Text("Emergency").tag("emergency")
            Text("Non-emergency").tag("nonEmergency")
            if !["", "emergency", "nonEmergency"].contains(selection) {
                Text("Other: \(selection)").tag(selection)
            }
        }
    }
}

extension OME.Link {
    var isContact: Bool {
        if case .known(.contact) = role { return true }
        return false
    }

    var isReporting: Bool {
        if case .known(.reporting) = role { return true }
        return false
    }

    var isContactOrReporting: Bool { isContact || isReporting }
}

extension Open where Known == OME.Link.ContactUse {
    var displayValue: String {
        switch self {
        case .known(let use): use.rawValue
        case .unknown(let value): value.string ?? ""
        }
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
