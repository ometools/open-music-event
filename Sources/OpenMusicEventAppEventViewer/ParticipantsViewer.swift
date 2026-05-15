import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventDatabase
import SQLiteData
import Tagged
import SwiftUI

@Feature
public struct PeopleViewer {
    public init() {}

    public struct State {
        public init(
            eventID: OMERecord.Event.ID,
            destination: Destination.State? = nil,
            database: (any DatabaseReader)? = nil
        ) {
            self.eventID = eventID
            self.destination = destination
            _participants = FetchAll(
                PeopleViewer.participantsQuery(eventID: eventID),
                database: database
            )
        }

        public let eventID: OMERecord.Event.ID
        public var destination: Destination.State?
        public var searchText = ""

        @FetchAll public var participants: [OMERecord.Participant]

        public var filteredParticipants: [OMERecord.Participant] {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return participants }

            return participants.filter { participant in
                participant.name.localizedStandardContains(query)
                    || participant.kind?.rawValue.localizedStandardContains(query) == true
            }
        }
    }

    public enum Action {
        case addButtonTapped
        case destination(Destination.Action)
        case participantButtonTapped(OMERecord.ID<OMERecord.Participant>)
    }

    @Feature
    public enum Destination {
        case createParticipant(Spawn<EditParticipant>)
        case participantDetail(Spawn<ParticipantDetail>)
    }

    static func participantsQuery(
        eventID: OMERecord.Event.ID
    ) -> some SelectStatementOf<OMERecord.Participant> {
        OMERecord.Participant
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .order { $0.name.collate(.nocase) }
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .addButtonTapped:
                store.withDependencies {
                    state.destination = .createParticipant(
                        Spawn(EditParticipant.State(eventID: state.eventID))
                    )
                }

            case .destination:
                break

            case let .participantButtonTapped(participantID):
                state.destination = .participantDetail(
                    Spawn(.init(participantID: participantID, eventID: state.eventID))
                )
            }
        }
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
    }
}

public struct PeopleViewerView: View {
    @Bindable var store: StoreOf<PeopleViewer>

    public init(store: StoreOf<PeopleViewer>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if store.participants.isEmpty {
                ViewerPlaceholderView(
                    title: "People",
                    systemImage: "person.3",
                    description: "No people have been added to this event yet."
                )
            } else if store.filteredParticipants.isEmpty {
                ViewerPlaceholderView(
                    title: "No Results",
                    systemImage: "person.3",
                    description: "No people match your search."
                )
            } else {
                List(store.filteredParticipants) { participant in
                    Button {
                        store.send(.participantButtonTapped(participant.id.participantID))
                    } label: {
                        PeopleRowView(participant: participant)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .searchable(text: $store.searchText, prompt: "Search People")
        .autocorrectionDisabled()
        #if os(iOS)
        .textInputAutocapitalization(.never)
        #endif
        .navigationTitle("People")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.send(.addButtonTapped)
                } label: {
                    Image(systemName: "plus")
                        .accessibilityLabel("Add Person")
                }
            }
        }
        .sheet(item: $store.scope(state: \.destination, action: \.destination).createParticipant) { createStore in
            NavigationStack {
                EditParticipantView(store: createStore)
            }
        }
        .navigationDestination(item: $store.scope(state: \.destination, action: \.destination).participantDetail) { detailStore in
            ParticipantDetailView(store: detailStore)
        }
    }
}

struct PeopleRowView: View {
    let participant: OMERecord.Participant

    var body: some View {
        HStack(spacing: 12) {
            ParticipantArtworkView(
                asset: participant.preferredArtworkAsset,
                cacheContext: .init(participantID: participant.id),
                size: 60
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(participant.name)
                    .lineLimit(1)

                if let kind = participant.kind?.displayName {
                    Text(kind)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .foregroundStyle(.primary)
    }
}

@Feature
public struct ParticipantDetail {
    public init() {}

    public struct State: Identifiable {
        public let participantID: OMERecord.ID<OMERecord.Participant>
        public let eventID: OMERecord.Event.ID
        public var destination: Destination.State?

        @FetchOne public var participant: OMERecord.Participant?

        public init(
            participantID: OMERecord.ID<OMERecord.Participant>,
            eventID: OMERecord.Event.ID? = nil,
            database: (any DatabaseReader)? = nil
        ) {
            @Dependency(\.defaultEventID) var defaultEventID

            self.participantID = participantID
            self.eventID = eventID ?? defaultEventID
            _participant = FetchOne(
                ParticipantDetail.participantQuery(
                    participantID: participantID,
                    eventID: self.eventID
                ),
                database: database
            )
        }

        public var id: OMERecord.ID<OMERecord.Participant> { participantID }
    }

    public enum Action {
        case destination(Destination.Action)
        case editButtonTapped
    }

    @Feature
    public enum Destination {
        case editParticipant(Spawn<EditParticipant>)
    }

    static func participantQuery(
        participantID: OMERecord.ID<OMERecord.Participant>,
        eventID: OMERecord.Event.ID
    ) -> some SelectStatementOf<OMERecord.Participant> {
        OMERecord.Participant
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .where { $0.id.participantID.eq(participantID) }
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .destination:
                break

            case .editButtonTapped:
                store.withDependencies {
                    state.destination = .editParticipant(
                        Spawn(
                            EditParticipant.State(
                                participantID: state.participantID,
                                eventID: state.eventID
                            )
                        )
                    )
                }
            }
        }
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
    }
}

public struct ParticipantDetailView: View {
    @Bindable var store: StoreOf<ParticipantDetail>

    public init(store: StoreOf<ParticipantDetail>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if let participant = store.participant {
                List {
                    ParticipantHeaderView(participant: participant)

                    if let bio = participant.displayBio {
                        Section("About") {
                            Text(bio)
                        }
                    }

                    if let links = participant.links, !links.isEmpty {
                        Section("Links") {
                            ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                                ParticipantLinkRow(link: link)
                            }
                        }
                    }
                }
                .navigationTitle(participant.name)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Edit") {
                            store.send(.editButtonTapped)
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "Person",
                    systemImage: "person.crop.circle",
                    description: Text(verbatim: store.participantID.rawValue.rawValue)
                )
                .navigationTitle("Person")
            }
        }
        .sheet(item: $store.scope(state: \.destination, action: \.destination).editParticipant) { editStore in
            NavigationStack {
                EditParticipantView(store: editStore)
            }
        }
    }
}

@Feature
public struct EditParticipant {
    public init() {}

    public struct State {
        public enum Mode: Equatable, Sendable {
            case create
            case edit(OMERecord.ID<OMERecord.Participant>)

            var participantID: OMERecord.ID<OMERecord.Participant>? {
                switch self {
                case .create:
                    return nil
                case let .edit(participantID):
                    return participantID
                }
            }
        }

        public init(eventID: OMERecord.Event.ID) {
            self.eventID = eventID
            self.hasLoadedDraft = true
            self.mode = .create
        }

        public init(
            participantID: OMERecord.ID<OMERecord.Participant>,
            eventID: OMERecord.Event.ID
        ) {
            self.eventID = eventID
            self.mode = .edit(participantID)
        }

        public let eventID: OMERecord.Event.ID
        let mode: Mode

        @DebugSnapshotTracked var bio: String = ""
        @DebugSnapshotTracked var errorMessage: String?
        @DebugSnapshotTracked var hasLoadedDraft: Bool = false
        @DebugSnapshotTracked var imageURL: String = ""
        @DebugSnapshotTracked var isSaving: Bool = false
        @DebugSnapshotTracked var kind: String = ""
        var links: [EditableParticipantLink] = []
        @DebugSnapshotTracked var logoURL: String = ""
        @DebugSnapshotTracked var name: String = ""

        var canSubmit: Bool {
            hasLoadedDraft && !isSaving && validationMessage == nil
        }

        var navigationTitle: String {
            switch mode {
            case .create:
                return "New Person"
            case .edit:
                return "Edit Person"
            }
        }

        var submitButtonTitle: String {
            switch mode {
            case .create:
                return "Create"
            case .edit:
                return "Save"
            }
        }

        fileprivate struct SaveRequest: Sendable {
            let bio: String?
            let eventID: OMERecord.Event.ID
            let images: [OMERecord.ImageAsset]?
            let kind: OMERecord.Participant.Kind?
            let links: [ExternalPlatform.Link]?
            let mode: Mode
            let name: String

            init(state: State) {
                self.bio = state.bio.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                self.eventID = state.eventID
                self.images = state.preparedImages.isEmpty ? nil : state.preparedImages
                self.kind = state.kind.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    .map { OMERecord.Participant.Kind($0) }
                self.links = state.preparedLinks.nilIfEmpty
                self.mode = state.mode
                self.name = state.trimmedName
            }

            func participantID(in db: Database) throws -> OMERecord.ID<OMERecord.Participant> {
                if let participantID = mode.participantID {
                    return participantID
                }

                let base = State.participantIDBase(for: name)
                var candidate = base
                var suffix = 2

                while try ParticipantDetail.participantQuery(
                    participantID: State.localID(candidate),
                    eventID: eventID
                )
                .fetchOne(db) != nil {
                    candidate = "\(base)-\(suffix)"
                    suffix += 1
                }

                return State.localID(candidate)
            }

            func participantRecordID(
                participantID: OMERecord.ID<OMERecord.Participant>
            ) -> OMERecord.Participant.ID {
                OMERecord.Participant.ID(
                    organizerID: eventID.organizerID,
                    eventID: eventID.eventID,
                    participantID: participantID
                )
            }

            func preparedDraft(
                participantID: OMERecord.ID<OMERecord.Participant>
            ) -> OMERecord.Participant.Draft {
                OMERecord.Participant.Draft(
                    id: participantRecordID(participantID: participantID),
                    name: name,
                    bio: bio,
                    images: images,
                    kind: kind,
                    links: links
                )
            }
        }

        var preparedLinks: [ExternalPlatform.Link] {
            links.compactMap(\.preparedLink)
        }

        var preparedImages: [OMERecord.ImageAsset] {
            [
                trimmedImageURL.nilIfEmpty
                    .flatMap(URL.init(string:))
                    .map {
                        OMERecord.ImageAsset(
                            source: .url($0),
                            role: .photo,
                            renderKind: .fullImage,
                            materializationPolicy: .lazy
                        )
                    },
                trimmedLogoURL.nilIfEmpty
                    .flatMap(URL.init(string:))
                    .map {
                        OMERecord.ImageAsset(
                            source: .url($0),
                            role: .logo,
                            renderKind: .transparent,
                            materializationPolicy: .lazy
                        )
                    },
            ]
            .compactMap { $0 }
        }

        var validationMessage: String? {
            guard hasLoadedDraft else { return nil }

            if trimmedName.isEmpty {
                return "Enter a name."
            }

            if !trimmedImageURL.isEmpty, URL(string: trimmedImageURL) == nil {
                return "Enter a valid image URL."
            }

            if !trimmedLogoURL.isEmpty, URL(string: trimmedLogoURL) == nil {
                return "Enter a valid logo URL."
            }

            return links.compactMap(\.validationMessage).first
        }

        private var trimmedImageURL: String {
            imageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private var trimmedLogoURL: String {
            logoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private var trimmedName: String {
            name.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private static func localID(_ string: String) -> OMERecord.ID<OMERecord.Participant> {
            OMERecord.ID<OMERecord.Participant>(.init(string))
        }

        private static func participantIDBase(for name: String) -> String {
            let normalized = name
                .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
                .lowercased()
            let words = normalized
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }

            return words.isEmpty
                ? "person-\(UUID().uuidString.lowercased())"
                : words.joined(separator: "-")
        }
    }

    public enum Action {
        case addLinkButtonTapped
        case cancelButtonTapped
        case removeLinkButtonTapped(UUID)
        case saveButtonTapped
        case saveFailed(String)
        case saveSucceeded
    }

    @Dependency(\.defaultDatabase) var database

    public var body: some Feature {
        let _ = Self._logChanges()
        Update { state, action in
            switch action {
            case .addLinkButtonTapped:
                state.links.append(EditableParticipantLink())

            case .cancelButtonTapped:
                store.addTask {
                    try store.dismiss()
                }

            case let .removeLinkButtonTapped(id):
                state.links.removeAll { $0.id == id }

            case .saveButtonTapped:
                guard !state.isSaving else { return }
                guard state.hasLoadedDraft else {
                    state.errorMessage = "This person could not be loaded."
                    return
                }

                guard let validationMessage = state.validationMessage else {
                    state.errorMessage = nil
                    state.isSaving = true
                    let saveRequest = State.SaveRequest(state: state)

                    store.addTask {
                        do {
                            try await database.write { db in
                                let participantID = try saveRequest.participantID(in: db)
                                let draft = saveRequest.preparedDraft(participantID: participantID)
                                try OMERecord.Participant.upsert {
                                    draft
                                }
                                .execute(db)
                            }
                            try store.send(.saveSucceeded)
                        } catch {
                            try store.send(
                                .saveFailed("Unable to save person: \(error.editParticipantSaveDescription)")
                            )
                        }
                    }
                    return
                }

                state.errorMessage = validationMessage

            case let .saveFailed(message):
                state.errorMessage = message
                state.isSaving = false

            case .saveSucceeded:
                state.errorMessage = nil
                state.isSaving = false
                store.addTask {
                    _ = try? store.dismiss()
                }
            }
        }
        .onMount { state in
            guard !state.hasLoadedDraft else { return }

            guard let participantID = state.mode.participantID else {
                state.hasLoadedDraft = true
                state.errorMessage = nil
                return
            }

            do {
                if let participant = try database.read({ db in
                    try ParticipantDetail.participantQuery(
                        participantID: participantID,
                        eventID: state.eventID
                    )
                    .fetchOne(db)
                }) {
                    state.name = participant.name
                    state.bio = participant.bio ?? ""
                    state.imageURL = participant.images?.imageAsset(role: .photo)?.url?.absoluteString ?? ""
                    state.logoURL = participant.images?.imageAsset(role: .logo)?.url?.absoluteString ?? ""
                    state.kind = participant.kind?.rawValue ?? ""
                    state.links = (participant.links ?? []).map(EditableParticipantLink.init)
                    state.hasLoadedDraft = true
                    state.errorMessage = nil
                } else {
                    state.errorMessage = "This person could not be loaded."
                }
            } catch {
                state.errorMessage = "This person could not be loaded."
            }
        }
    }
}

public struct EditParticipantView: View {
    @Bindable var store: StoreOf<EditParticipant>

    public init(store: StoreOf<EditParticipant>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if store.hasLoadedDraft {
                Form {
                    Section("Person") {
                        TextField("Name", text: $store.name)
                        TextField("Kind", text: $store.kind)
                    }

                    Section("Bio") {
                        TextField("Bio", text: $store.bio, axis: .vertical)
                            .lineLimit(4...8)
                    }

                    Section("Images") {
                        TextField("Image URL", text: $store.imageURL)
                            #if os(iOS)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            #endif
                        TextField("Logo URL", text: $store.logoURL)
                            #if os(iOS)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            #endif
                    }

                    ForEach($store.links) { $link in
                        Section("Link") {
                            TextField("URL", text: $link.url)
                                #if os(iOS)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                #endif

                            Picker("Platform", selection: $link.platformRawValue) {
                                Text("Auto").tag("")
                                ForEach(ExternalPlatform.allCases, id: \.rawValue) { platform in
                                    Text(platform.name).tag(platform.rawValue)
                                }
                            }

                            Button("Remove Link", role: .destructive) {
                                store.send(.removeLinkButtonTapped(link.id))
                            }
                        }
                    }

                    Section {
                        Button("Add Link") {
                            store.send(.addLinkButtonTapped)
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
                    title: store.navigationTitle,
                    systemImage: "person.crop.circle",
                    description: "This person could not be loaded."
                )
            }
        }
        .disabled(store.isSaving)
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
                    Button(store.submitButtonTitle) {
                        store.send(.saveButtonTapped)
                    }
                    .disabled(!store.canSubmit)
                }
            }
        }
        .navigationTitle(store.navigationTitle)
    }
}

public struct EditableParticipantLink: Identifiable, Equatable {
    public var id = UUID()
    var platformRawValue = ""
    var url = ""

    init() {}

    init(_ link: ExternalPlatform.Link) {
        self.platformRawValue = link.platform?.rawValue ?? ""
        self.url = link.url.absoluteString
    }

    var preparedLink: ExternalPlatform.Link? {
        guard let url = URL(string: trimmedURL), !trimmedURL.isEmpty else { return nil }
        return ExternalPlatform.Link(
            url: url,
            platform: trimmedPlatformRawValue.nilIfEmpty.flatMap(ExternalPlatform.init(rawValue:))
        )
    }

    var validationMessage: String? {
        guard !trimmedURL.isEmpty else { return nil }

        if URL(string: trimmedURL) == nil {
            return "Enter a valid link URL."
        }

        if !trimmedPlatformRawValue.isEmpty, ExternalPlatform(rawValue: trimmedPlatformRawValue) == nil {
            return "Choose a valid link platform."
        }

        return nil
    }

    private var trimmedPlatformRawValue: String {
        platformRawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedURL: String {
        url.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ParticipantHeaderView: View {
    let participant: OMERecord.Participant

    var body: some View {
        HStack(spacing: 14) {
            ParticipantArtworkView(
                asset: participant.preferredArtworkAsset,
                cacheContext: .init(participantID: participant.id),
                size: 72
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(participant.name)
                    .font(.headline)
                    .lineLimit(2)

                if let kind = participant.kind?.displayName {
                    Text(kind)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 6)
    }
}

struct ParticipantArtworkView: View {
    let asset: OMERecord.ImageAsset?
    let cacheContext: LocalImageCacheContext
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(.secondary.opacity(0.12))

            ImageAssetAsyncImage(asset: asset, cacheContext: cacheContext) {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var placeholder: some View {
        Image(systemName: "person.crop.square")
            .font(.system(size: size * 0.42))
            .foregroundStyle(.secondary)
    }
}

struct ParticipantLinkRow: View {
    let link: ExternalPlatform.Link

    var body: some View {
        Link(destination: link.destinationURL) {
            HStack(spacing: 12) {
                Text(link.displayName)
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
    }
}

private extension OMERecord.Participant {
    var preferredArtworkAsset: OMERecord.ImageAsset? {
        images?.imageAsset(role: .photo)
        ?? images?.imageAsset(role: .logo)
    }

    var displayBio: String? {
        let bio = bio?.trimmingCharacters(in: .whitespacesAndNewlines)
        return bio?.isEmpty == false ? bio : nil
    }
}

private extension Array where Element == ExternalPlatform.Link {
    var nilIfEmpty: Self? {
        isEmpty ? nil : self
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension Error {
    var editParticipantSaveDescription: String {
        let description = String(describing: self)
        return description.isEmpty ? localizedDescription : description
    }
}

private extension OMERecord.Participant.Kind {
    var displayName: String? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private extension ExternalPlatform.Link {
    var destinationURL: URL {
        guard url.scheme == nil else { return url }
        return URL(string: "https://\(url.absoluteString)") ?? url
    }

    var displayName: String {
        platform?.name ?? url.host ?? url.absoluteString
    }
}
