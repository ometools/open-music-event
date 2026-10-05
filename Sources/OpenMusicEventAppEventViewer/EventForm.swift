import ATProto
import ATProtoOAuth
import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventComponents
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventTimeZones
import SQLiteData
import SwiftUITabFeatures
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

@Feature
public struct EventForm {
    public init() {}

    public enum Mode: Equatable, Sendable { case create, edit }

    typealias MediaEntry = RecordMediaEditing.MediaEntry
    public typealias MediaDraft = RecordMediaEditing.MediaDraft

    public struct State {
        public init(event: Event, mode: Mode = .edit) {
            @Dependency(\.date.now) var now
            self.original = event
            self.mode = mode
            self.draft = event
            let links = (event.links ?? []).map(EditableLink.init)
            self.links = links
            self.originalLinks = links
            let mediaEntries = (event.media ?? []).map { MediaEntry(value: $0) }
            self.mediaEntries = mediaEntries
            self.originalMediaEntries = mediaEntries
            self.defaultDate = now
        }

        let original: Event
        let mode: Mode
        @DebugSnapshotTracked var draft: Event
        var links: [EditableLink]
        let originalLinks: [EditableLink]
        var mediaEntries: [MediaEntry]
        let originalMediaEntries: [MediaEntry]
        var mediaDraft: MediaDraft?
        var destination: Destination.State?
        var editingLinkID: EditableLink.ID?
        let defaultDate: Date
        @DebugSnapshotTracked var isSaving = false
        @DebugSnapshotTracked var errorMessage: String?

        public var eventID: Event.ID { original.id }

        mutating func editMedia(_ id: UUID) {
            guard let entry = mediaEntries.first(where: { $0.id == id }) else { return }
            switch entry.value {
            case let .known(.external(external)):
                mediaDraft = MediaDraft(entryID: id, external: external)
            case let .known(.record(reference)):
                mediaDraft = MediaDraft(entryID: id, reference: reference)
            case .known(.image), .unknown:
                break
            }
        }

        mutating func saveMediaDraft() {
            guard let draft = mediaDraft, let value = draft.value() else { return }
            if let id = draft.entryID {
                guard let index = mediaEntries.firstIndex(where: { $0.id == id }) else { return }
                mediaEntries[index].value = value
            } else {
                mediaEntries.append(MediaEntry(value: value))
            }
            mediaDraft = nil
        }

        var preparedRecord: Event {
            var record = draft
            if record.name != original.name {
                record.name = record.name.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if record.description != original.description {
                record.description = record.description?
                    .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            }
            if record.status != original.status, let custom = record.status?.customValue {
                record.status = .unknown(.string(custom.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            if record.mode != original.mode, let custom = record.mode?.customValue {
                record.mode = .unknown(.string(custom.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            if links != originalLinks {
                let preparedLinks = links.compactMap(\.preparedLink)
                record.links = preparedLinks.isEmpty ? nil : preparedLinks
            }
            return record
        }

        var validationMessage: String? {
            if let message = links.compactMap(\.validationMessage).first { return message }
            let record = preparedRecord
            if record.name.isEmpty { return "Enter an event name." }
            if record.status?.customValue == "" { return "Enter a custom event status." }
            if record.mode?.customValue == "" { return "Enter a custom event mode." }
            if let start = record.start?.date(in: record.timeZone),
               let end = record.end?.date(in: record.timeZone),
               (record.start.precision == .day || record.end.precision == .day
                ? LocalDate(end, in: record.timeZone) < LocalDate(start, in: record.timeZone)
                : end < start) {
                return "End must be on or after the start."
            }
            do {
                try record.validateReferences()
            } catch {
                return "Check the event values: \(error.localizedDescription)"
            }
            return nil
        }

        var canSubmit: Bool { !isSaving && mediaDraft == nil && validationMessage == nil }
    }

    public enum Action {
        case addExternalMediaButtonTapped
        case addImageButtonTapped
        case addLinkButtonTapped
        case addRecordMediaButtonTapped
        case cancelButtonTapped
        case destination(Destination.Action)
        case editLinkButtonTapped(UUID)
        case mediaDeleteButtonTapped(UUID)
        case mediaDraftCancelButtonTapped
        case mediaDraftChanged(MediaDraft)
        case mediaDraftRemoveThumbnailButtonTapped
        case mediaDraftSaveButtonTapped
        case mediaEditButtonTapped(UUID)
        case mediaImageInfoButtonTapped(UUID)
        case mediaMoveButtonTapped(UUID, Int)
        case moveLinkButtonTapped(UUID, Int)
        case removeLinkButtonTapped(UUID)
        case saveButtonTapped
    }

    @Feature
    public enum Destination {
        case imageInfo(Spawn<ImageInfo>)
        case importImages(Spawn<ImportImages>)
    }

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.getOptionalDefaultSession) var getOptionalDefaultSession

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .addExternalMediaButtonTapped:
                state.mediaDraft = MediaDraft(kind: .external)

            case .addImageButtonTapped:
                state.destination = .importImages(Spawn(ImportImages.State(configuration: .eventMedia)))

            case .addLinkButtonTapped:
                let link = EditableLink()
                state.links.append(link)
                state.editingLinkID = link.id

            case .addRecordMediaButtonTapped:
                state.mediaDraft = MediaDraft(kind: .record)

            case .cancelButtonTapped:
                guard !state.isSaving else { return }
                store.addTask { try store.dismiss() }

            case .destination:
                break

            case let .editLinkButtonTapped(id):
                guard state.links.contains(where: { $0.id == id }) else { return }
                state.editingLinkID = id

            case let .mediaDeleteButtonTapped(id):
                state.mediaEntries.removeAll { $0.id == id }
                if state.mediaDraft?.entryID == id { state.mediaDraft = nil }

            case .mediaDraftCancelButtonTapped:
                state.mediaDraft = nil

            case let .mediaDraftChanged(draft):
                guard state.mediaDraft != nil else { return }
                state.mediaDraft = draft

            case .mediaDraftRemoveThumbnailButtonTapped:
                state.mediaDraft?.removeThumbnail = true
                state.mediaDraft?.thumbnailURL = ""

            case .mediaDraftSaveButtonTapped:
                state.saveMediaDraft()

            case let .mediaEditButtonTapped(id):
                state.editMedia(id)

            case let .mediaImageInfoButtonTapped(id):
                if let draft = state.mediaDraft, draft.thumbnailID == id,
                   let imageInfo = draft.thumbnailImageInfoState(recordID: state.eventID) {
                    state.destination = .imageInfo(Spawn(imageInfo))
                    return
                }
                guard let entry = state.mediaEntries.first(where: { $0.id == id }),
                      let imageValue = entry.imageValue else { return }
                state.destination = .imageInfo(Spawn(ImageInfo.State(
                    id: id,
                    image: imageValue.image,
                    configuration: .allImages,
                    sourceLabel: imageValue.displaySource,
                    recordID: state.eventID,
                    previewData: entry.importedImage?.data
                )))

            case let .mediaMoveButtonTapped(id, offset):
                guard let index = state.mediaEntries.firstIndex(where: { $0.id == id }),
                      state.mediaEntries.indices.contains(index + offset) else { return }
                state.mediaEntries.swapAt(index, index + offset)

            case let .moveLinkButtonTapped(id, offset):
                guard let index = state.links.firstIndex(where: { $0.id == id }),
                      state.links.indices.contains(index + offset) else { return }
                state.links.swapAt(index, index + offset)

            case let .removeLinkButtonTapped(id):
                state.links.removeAll { $0.id == id }
                if state.editingLinkID == id { state.editingLinkID = nil }

            case .saveButtonTapped:
                guard !state.isSaving else { return }
                guard state.mediaDraft == nil else { return }
                if let message = state.validationMessage {
                    state.errorMessage = message
                    return
                }
                let preparedRecord = state.preparedRecord
                let mediaEntries = state.mediaEntries
                let mediaChanged = mediaEntries != state.originalMediaEntries
                let original = state.original
                let mode = state.mode
                let getOptionalDefaultSession = getOptionalDefaultSession
                let database = database
                state.errorMessage = nil
                state.isSaving = true
                store.addTask {
                    do {
                        var record = preparedRecord
                        if mediaChanged {
                            record.media = try RecordMediaEditing.preparedMedia(mediaEntries)
                        }
                        try database.write { db in
                            if mode == .create {
                                guard let account = getOptionalDefaultSession(),
                                      original.id.authority == .did(account.accountID.rawValue)
                                else { throw SaveError.accountChanged }
                                try record.validateReferences()
                                try Event.insert { record }.execute(db)
                                try InstalledEvent.insert { InstalledEvent(id: record.id) }.execute(db)
                                try LocallyCreatedEvent.insert { LocallyCreatedEvent(id: record.id) }.execute(db)
                            } else {
                                guard let current = try Event.find(original.id).fetchOne(db) else {
                                    throw SaveError.deleted
                                }
                                guard current == original else { throw SaveError.changed }
                                try record.validateReferences()
                                try Event.upsert { record }.execute(db)
                            }
                        }
                        try store.modify { $0.isSaving = false }
                        try store.dismiss()
                    } catch {
                        try store.modify {
                            $0.errorMessage = (error as? SaveError)?.message
                                ?? "Unable to save event changes."
                            $0.isSaving = false
                        }
                    }
                }
            }
        }
        .ifLet(\.destination) {
            EmptyFeature()
                .ifCaseLet(\.importImages) { ImportImages() }
                .ifCaseLet(\.imageInfo) {
                    ImageInfo { imageID, image in
                        try store.modify {
                            if $0.mediaDraft?.thumbnailID == imageID {
                                $0.mediaDraft?.updateThumbnailImageInfo(image)
                                return
                            }
                            guard let index = $0.mediaEntries.firstIndex(where: { $0.id == imageID }),
                                  case .known(.image) = $0.mediaEntries[index].value else { return }
                            $0.mediaEntries[index].value = .known(.image(image))
                            $0.mediaEntries[index].importedImage?.image = image
                        }
                    }
                }
        }
        .onEvent(ImportedImagesSubmitted.self) { images, state in
            guard case .importImages = state.destination else { return }
            state.mediaEntries.append(contentsOf: images.map { MediaEntry(importedImage: $0) })
        }
    }

    private enum SaveError: Error {
        case accountChanged, changed, deleted

        var message: String {
            switch self {
            case .accountChanged: "Sign in with the account you started this event with to save it. Your draft is unchanged."
            case .changed: "This event changed while you were editing. Reopen the form to edit the latest version."
            case .deleted: "This event is no longer available."
            }
        }
    }
}

public struct EventFormView: View {
    @Bindable var store: StoreOf<EventForm>

    public init(store: StoreOf<EventForm>) {
        self.store = store
    }

    public var body: some View {
        Form {
            Section("Event Name") {
                TextField("Event Name", text: $store.draft.name)
                    .accessibilityIdentifier("field.event-info.name")
            }
            Section("Description") {
                PortableTextField("Description", text: $store.draft.description[coalesce: ""], axis: .vertical)
                    .portableLineLimit(4...8)
            }
            Section("Times") {
                EventBoundaryPicker(
                    title: "Start", value: $store.draft.start,
                    timeZone: store.draft.timeZone, defaultDate: store.defaultDate
                )
                EventBoundaryPicker(
                    title: "End", value: $store.draft.end,
                    timeZone: store.draft.timeZone, defaultDate: store.defaultDate
                )
                NavigationLink {
                    TimeZonePicker(selection: $store.draft.timeZone)
                } label: {
                    LabeledContent("Time Zone", value: store.draft.timeZone.identifier)
                }
                .navigationLinkListRowStyle()
            }
            Section("Links") {
                ForEach(store.links) { link in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(link.title.isEmpty ? (link.url.isEmpty ? "New Link" : link.url) : link.title)
                                .lineLimit(1)
                            if !link.title.isEmpty && !link.url.isEmpty {
                                Text(link.url)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Menu {
                            Button("Edit") { store.send(.editLinkButtonTapped(link.id)) }
                            Button("Move Up") { store.send(.moveLinkButtonTapped(link.id, -1)) }
                                .disabled(store.links.first?.id == link.id)
                            Button("Move Down") { store.send(.moveLinkButtonTapped(link.id, 1)) }
                                .disabled(store.links.last?.id == link.id)
                            Button("Delete", role: .destructive) {
                                store.send(.removeLinkButtonTapped(link.id))
                            }
                        } label: {
                            Label("Link Actions", systemImage: "ellipsis.circle")
                                .labelStyle(.iconOnly)
                        }
                    }
                }
                Button("Add Link") { store.send(.addLinkButtonTapped) }
            }
            if let index = store.links.firstIndex(where: { $0.id == store.editingLinkID }) {
                Section("Edit Link") {
                    EditLinkFields(link: $store.links[index])
                }
            }
            EventMediaFormSection(store: store)
            Section("Details") {
                Picker("Status", selection: $store.draft.editStatus) {
                    ForEach(EventFormStatus.allCases, id: \.self) { status in
                        Text(status.title).tag(status)
                    }
                }
                if store.draft.editStatus == .custom {
                    TextField("Custom Status", text: $store.draft.customStatusText)
                }
                Picker("Mode", selection: $store.draft.editMode) {
                    ForEach(EventFormMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                if store.draft.editMode == .custom {
                    TextField("Custom Mode", text: $store.draft.customModeText)
                }
                Picker("RSVPs", selection: $store.draft.rsvpExpected) {
                    Text("Unspecified").tag(nil as Bool?)
                    Text("Expected").tag(true as Bool?)
                    Text("Not expected").tag(false as Bool?)
                }
            }
            if let message = store.errorMessage ?? store.validationMessage {
                Section {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }
            }
        }
        .disabled(store.isSaving)
        .navigationTitle(store.mode == .create ? "Create Event" : "Edit Event Info")
        .interactiveDismissDisabled(store.isSaving)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { store.send(.cancelButtonTapped) } label: {
                    Label("Cancel", systemImage: "xmark").labelStyle(.iconOnly)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                SubmitButton(isInProgress: store.isSaving, isDisabled: !store.canSubmit) {
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
}

struct EventBoundaryPicker: View {
    let title: String
    @Binding var value: Open<Event.Time>?
    let timeZone: TimeZone
    let defaultDate: Date

    var body: some View {
        Picker(title, selection: Binding(
            get: { value.precision },
            set: { precision in
                let date = value?.date(in: timeZone) ?? defaultDate
                switch precision {
                case .unspecified: value = nil
                case .day: value = .known(.day(.init(value: LocalDate(date, in: timeZone))))
                case .time: value = .known(.time(.init(value: .init(date.ISO8601Format()))))
                case .unknown: break
                }
            }
        )) {
            Text("Unspecified").tag(EventBoundaryPrecision.unspecified)
            Text("Day").tag(EventBoundaryPrecision.day)
            Text("Exact time").tag(EventBoundaryPrecision.time)
            if value.precision == .unknown {
                Text("Unsupported format").tag(EventBoundaryPrecision.unknown)
            }
        }
        if value.precision == .day || value.precision == .time {
            DatePicker(
                title,
                selection: Binding(
                    get: { value?.date(in: timeZone) ?? defaultDate },
                    set: { date in
                        if value.precision == .day {
                            value = .known(.day(.init(value: LocalDate(date, in: timeZone))))
                        } else {
                            value = .known(.time(.init(value: .init(date.ISO8601Format()))))
                        }
                    }
                ),
                displayedComponents: value.precision == .day ? [.date] : [.date, .hourAndMinute]
            )
            .environment(\.timeZone, timeZone)
        }
    }
}

private enum EventBoundaryPrecision: Hashable {
    case unspecified, day, time, unknown
}

private extension Optional where Wrapped == Open<Event.Time> {
    var precision: EventBoundaryPrecision {
        switch self {
        case nil: .unspecified
        case .known(.day): .day
        case .known(.time): .time
        case .unknown: .unknown
        }
    }
}

public enum EventFormStatus: String, CaseIterable, Hashable, Sendable {
    case unspecified
    case planned
    case scheduled
    case rescheduled
    case cancelled
    case postponed
    case custom

    init(_ status: Open<Event.Status>?) {
        guard let status else {
            self = .unspecified
            return
        }

        switch status {
        case .known(.planned):
            self = .planned
        case .known(.scheduled):
            self = .scheduled
        case .known(.rescheduled):
            self = .rescheduled
        case .known(.cancelled):
            self = .cancelled
        case .known(.postponed):
            self = .postponed
        case .unknown:
            self = .custom
        }
    }

    var title: String {
        switch self {
        case .unspecified:
            "Unspecified"
        case .planned:
            "Planned"
        case .scheduled:
            "Scheduled"
        case .rescheduled:
            "Rescheduled"
        case .cancelled:
            "Cancelled"
        case .postponed:
            "Postponed"
        case .custom:
            "Custom"
        }
    }

    func openValue(customValue: String) -> Open<Event.Status>? {
        switch self {
        case .unspecified:
            nil
        case .planned:
            .known(.planned)
        case .scheduled:
            .known(.scheduled)
        case .rescheduled:
            .known(.rescheduled)
        case .cancelled:
            .known(.cancelled)
        case .postponed:
            .known(.postponed)
        case .custom:
            .unknown(.string(customValue))
        }
    }
}

public enum EventFormMode: String, CaseIterable, Hashable, Sendable {
    case unspecified
    case inPerson
    case virtual
    case hybrid
    case custom

    init(_ mode: Open<Event.Mode>?) {
        guard let mode else {
            self = .unspecified
            return
        }

        switch mode {
        case .known(.inPerson):
            self = .inPerson
        case .known(.virtual):
            self = .virtual
        case .known(.hybrid):
            self = .hybrid
        case .unknown:
            self = .custom
        }
    }

    var title: String {
        switch self {
        case .unspecified:
            "Unspecified"
        case .inPerson:
            "In Person"
        case .virtual:
            "Virtual"
        case .hybrid:
            "Hybrid"
        case .custom:
            "Custom"
        }
    }

    func openValue(customValue: String) -> Open<Event.Mode>? {
        switch self {
        case .unspecified:
            nil
        case .inPerson:
            .known(.inPerson)
        case .virtual:
            .known(.virtual)
        case .hybrid:
            .known(.hybrid)
        case .custom:
            .unknown(.string(customValue))
        }
    }
}

private extension Open where Known == Event.Status {
    var customValue: String? {
        guard case let .unknown(value) = self else { return nil }
        return value.string
    }
}

private extension Open where Known == Event.Mode {
    var customValue: String? {
        guard case let .unknown(value) = self else { return nil }
        return value.string
    }
}

private extension Event {
    var editStatus: EventFormStatus {
        get { .init(status) }
        set { status = newValue.openValue(customValue: status?.customValue ?? "") }
    }

    var customStatusText: String {
        get { status?.customValue ?? "" }
        set { status = .some(.unknown(.string(newValue))) }
    }

    var editMode: EventFormMode {
        get { .init(mode) }
        set { mode = newValue.openValue(customValue: mode?.customValue ?? "") }
    }

    var customModeText: String {
        get { mode?.customValue ?? "" }
        set { mode = .some(.unknown(.string(newValue))) }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension Optional {
    subscript(coalesce coalesce: Wrapped) -> Wrapped {
        get { self ?? coalesce }
        set { self = newValue }
    }
}
