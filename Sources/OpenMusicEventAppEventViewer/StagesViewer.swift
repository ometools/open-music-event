import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventImages
import SQLiteData
import SwiftUI
import Tagged

@Feature
public struct StagesViewer {
    public init() {}

    public struct State {
        public init(
            eventID: OMERecord.Event.ID,
            destination: Destination.State? = nil,
            database: (any DatabaseReader)? = nil
        ) {
            self.eventID = eventID
            self.destination = destination
            _stages = FetchAll(
                StagesViewer.stagesQuery(eventID: eventID),
                database: database
            )
        }

        public let eventID: OMERecord.Event.ID
        public var destination: Destination.State?
        public var errorMessage: String?
        public var searchText = ""

        @FetchAll public var stages: [OMERecord.Stage]

        public var filteredStages: [OMERecord.Stage] {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return stages }

            return stages.filter { stage in
                stage.name.localizedStandardContains(query)
                    || stage.category?.rawValue.localizedStandardContains(query) == true
            }
        }
    }

    public enum Action {
        case addButtonTapped
        case deleteStages([OMERecord.ID<OMERecord.Stage>])
        case destination(Destination.Action)
        case stageButtonTapped(OMERecord.ID<OMERecord.Stage>)
    }

    @Feature
    public enum Destination {
        case createStage(Spawn<EditStage>)
        case stageDetail(Spawn<StageDetail>)
    }

    @Dependency(\.defaultDatabase) var database

    static func stagesQuery(
        eventID: OMERecord.Event.ID
    ) -> some SelectStatementOf<OMERecord.Stage> {
        OMERecord.Stage
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .order { ($0.sortIndex.asc(nulls: .last), $0.name.collate(.nocase)) }
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .addButtonTapped:
                store.withDependencies {
                    state.destination = .createStage(
                        Spawn(EditStage.State(eventID: state.eventID))
                    )
                }

            case let .deleteStages(stageIDs):
                let eventID = state.eventID
                store.addTask {
                    do {
                        try database.write { db in
                            for stageID in stageIDs {
                                try OMERecord.Stage
                                    .where { $0.id.organizerID.eq(eventID.organizerID) }
                                    .where { $0.id.eventID.eq(eventID.eventID) }
                                    .where { $0.id.stageID.eq(stageID) }
                                    .delete()
                                    .execute(db)
                            }
                        }
                        try store.modify {
                            $0.errorMessage = nil
                        }
                    } catch {
                        try store.modify {
                            $0.errorMessage = "Unable to delete event stage."
                        }
                    }
                }

            case .destination:
                break

            case let .stageButtonTapped(stageID):
                state.destination = .stageDetail(
                    Spawn(.init(stageID: stageID, eventID: state.eventID))
                )
            }
        }
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
    }
}

public struct StagesViewerView: View {
    @Bindable var store: StoreOf<StagesViewer>

    public init(store: StoreOf<StagesViewer>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if store.stages.isEmpty {
                ViewerPlaceholderView(
                    title: "Stages",
                    systemImage: "square.grid.2x2",
                    description: "No stages have been added to this event yet."
                )
            } else if store.filteredStages.isEmpty {
                ViewerPlaceholderView(
                    title: "No Results",
                    systemImage: "square.grid.2x2",
                    description: "No stages match your search."
                )
            } else {
                List {
                    if let errorMessage = store.errorMessage {
                        Section {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }

                    ForEach(store.filteredStages) { stage in
                        Button {
                            store.send(.stageButtonTapped(stage.id.stageID))
                        } label: {
                            StageRowView(stage: stage)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        deleteStages(at: offsets)
                    }
                }
                .listStyle(.plain)
            }
        }
        .searchable(text: $store.searchText, prompt: "Search Stages")
        .autocorrectionDisabled()
        #if os(iOS)
        .textInputAutocapitalization(.never)
        #endif
        .navigationTitle("Stages")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.send(.addButtonTapped)
                } label: {
                    Image(systemName: "plus")
                        .accessibilityLabel("Add Event Stage")
                }
            }
        }
        .sheet(item: $store.scope(state: \.destination, action: \.destination).createStage) { createStore in
            NavigationStack {
                EditStageView(store: createStore)
            }
        }
        .navigationDestination(item: $store.scope(state: \.destination, action: \.destination).stageDetail) { detailStore in
            StageDetailView(store: detailStore)
        }
    }

    func deleteStages(at offsets: IndexSet) {
        let stageIDs = offsets.compactMap { offset in
            store.filteredStages.indices.contains(offset)
                ? store.filteredStages[offset].id.stageID
                : nil
        }
        store.send(.deleteStages(stageIDs))
    }
}

@Feature
public struct StageDetail {
    public init() {}

    public struct State: Identifiable {
        public let stageID: OMERecord.ID<OMERecord.Stage>
        public let eventID: OMERecord.Event.ID
        public var destination: Destination.State?

        @FetchOne public var stage: OMERecord.Stage?
        @FetchAll public var participants: [OMERecord.Participant]

        public init(
            stageID: OMERecord.ID<OMERecord.Stage>,
            eventID: OMERecord.Event.ID? = nil,
            database: (any DatabaseReader)? = nil
        ) {
            @Dependency(\.defaultEventID) var defaultEventID

            self.stageID = stageID
            self.eventID = eventID ?? defaultEventID
            _stage = FetchOne(
                StageDetail.stageQuery(
                    stageID: stageID,
                    eventID: self.eventID
                ),
                database: database
            )
            _participants = FetchAll(
                PeopleViewer.participantsQuery(eventID: self.eventID),
                database: database
            )
        }

        public var id: OMERecord.ID<OMERecord.Stage> { stageID }

        public var lineupParticipants: [OMERecord.Participant] {
            guard let lineup = stage?.lineup, !lineup.isEmpty else { return [] }
            let participantsByID = Dictionary(
                uniqueKeysWithValues: participants.map { ($0.id.participantID, $0) }
            )
            return lineup.compactMap { participantsByID[$0] }
        }
    }

    public enum Action {
        case destination(Destination.Action)
        case editButtonTapped
    }

    @Feature
    public enum Destination {
        case editStage(Spawn<EditStage>)
    }

    static func stageQuery(
        stageID: OMERecord.ID<OMERecord.Stage>,
        eventID: OMERecord.Event.ID
    ) -> some SelectStatementOf<OMERecord.Stage> {
        OMERecord.Stage
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .where { $0.id.stageID.eq(stageID) }
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .destination:
                break

            case .editButtonTapped:
                store.withDependencies {
                    state.destination = .editStage(
                        Spawn(
                            EditStage.State(
                                stageID: state.stageID,
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

public struct StageDetailView: View {
    @Bindable var store: StoreOf<StageDetail>

    public init(store: StoreOf<StageDetail>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if let stage = store.stage {
                let logoAsset = stage.images?.imageAsset(role: .logo)
                HeroImageList(
                    title: Text(stage.name),
                    showsNavigationTitleBeforeScroll: logoAsset != nil
                ) {
                    HeroImage(
                        title: Text(stage.name),
                        asset: stage.images?.imageAsset(role: .hero),
                        cacheContext: .init(stageID: stage.id),
                        logoAsset: logoAsset,
                        tint: stage.color.swiftUIColor
                    ) {
                        StageIconFallback(stage: stage, size: 150)
                    }
                } content: {
                    if stage.hasDisplayDetails {
                        Section("Details") {
                            if let category = stage.category?.displayName {
                                LabeledContent("Category", value: category)
                            }

                            if let sortIndex = stage.sortIndex {
                                LabeledContent("Sort Index", value: sortIndex.formatted())
                            }
                        }
                    }

                    if !store.lineupParticipants.isEmpty {
                        Section("Lineup") {
                            ForEach(store.lineupParticipants) { participant in
                                PeopleRowView(participant: participant)
                            }
                        }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Edit") {
                            store.send(.editButtonTapped)
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "Stage",
                    systemImage: "square.grid.2x2",
                    description: Text(verbatim: store.stageID.rawValue.rawValue)
                )
                .navigationTitle("Stage")
            }
        }
        .sheet(item: $store.scope(state: \.destination, action: \.destination).editStage) { editStore in
            NavigationStack {
                EditStageView(store: editStore)
            }
        }
    }
}

@Feature
public struct EditStage {
    public init() {}

    public struct State {
        public enum Mode: Equatable {
            case create
            case edit(OMERecord.ID<OMERecord.Stage>)

            var stageID: OMERecord.ID<OMERecord.Stage>? {
                switch self {
                case .create:
                    return nil
                case let .edit(stageID):
                    return stageID
                }
            }
        }

        public init(eventID: OMERecord.Event.ID) {
            self.eventID = eventID
            self.mode = .create
            self.draft = Self.emptyDraft(stageID: nil, eventID: eventID)
            self.colorHex = Self.formatHexColor(draft.color)
            self.hasLoadedDraft = true
        }

        public init(
            stageID: OMERecord.ID<OMERecord.Stage>,
            eventID: OMERecord.Event.ID
        ) {
            self.eventID = eventID
            self.mode = .edit(stageID)
            self.draft = Self.emptyDraft(stageID: stageID, eventID: eventID)
        }

        public let eventID: OMERecord.Event.ID
        public let mode: Mode

        var colorHex = ""
        var draft: OMERecord.Stage.Draft
        var errorMessage: String?
        var hasLoadedDraft = false
        var heroImageURL = ""
        var isSaving = false
        var logoURL = ""
        var sortIndex = ""

        var category: String {
            get { draft.category?.rawValue ?? "" }
            set {
                let value = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                draft.category = value.nilIfEmpty.map { OMERecord.Stage.Category($0) }
            }
        }

        var iconShortCode: String {
            get { draft.iconShortCode ?? "" }
            set {
                draft.iconShortCode = newValue
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty
            }
        }

        var systemIconName: String {
            get { draft.systemIconName ?? "" }
            set {
                draft.systemIconName = newValue
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty
            }
        }

        public var stageID: OMERecord.ID<OMERecord.Stage>? {
            mode.stageID
        }

        var canSubmit: Bool {
            hasLoadedDraft && !isSaving && validationMessage == nil
        }

        var navigationTitle: String {
            switch mode {
            case .create:
                return "New Event Stage"
            case .edit:
                return "Edit Event Stage"
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

        func preparedDraft(
            stageID: OMERecord.ID<OMERecord.Stage>
        ) -> OMERecord.Stage.Draft? {
            guard let color = parsedColor else { return nil }

            var draft = draft
            draft.id = stageRecordID(stageID: stageID)
            draft.name = trimmedName
            draft.color = color
            draft.sortIndex = parsedSortIndex
            draft.images = preparedImages.isEmpty ? nil : preparedImages
            return draft
        }

        var validationMessage: String? {
            guard hasLoadedDraft else { return nil }

            if trimmedName.isEmpty {
                return "Enter a name."
            }

            if parsedColor == nil {
                return "Enter a valid hex color."
            }

            if !trimmedSortIndex.isEmpty, parsedSortIndex == nil {
                return "Enter a valid sort index."
            }

            if !trimmedLogoURL.isEmpty, URL(string: trimmedLogoURL) == nil {
                return "Enter a valid logo URL."
            }

            if !trimmedHeroImageURL.isEmpty, URL(string: trimmedHeroImageURL) == nil {
                return "Enter a valid hero image URL."
            }

            return nil
        }

        func stageID(in db: Database) throws -> OMERecord.ID<OMERecord.Stage> {
            if let stageID = mode.stageID {
                return stageID
            }

            let base = Self.stageIDBase(for: trimmedName)
            var candidate = base
            var suffix = 2

            while try StageDetail.stageQuery(
                stageID: Self.localID(candidate),
                eventID: eventID
            )
            .fetchOne(db) != nil {
                candidate = "\(base)-\(suffix)"
                suffix += 1
            }

            return Self.localID(candidate)
        }

        func stageRecordID(
            stageID: OMERecord.ID<OMERecord.Stage>
        ) -> OMERecord.Stage.ID {
            OMERecord.Stage.ID(
                organizerID: eventID.organizerID,
                eventID: eventID.eventID,
                stageID: stageID
            )
        }

        private var parsedColor: OMEColor? {
            Self.parseHexColor(trimmedColorHex)
        }

        private var parsedSortIndex: Int? {
            trimmedSortIndex.isEmpty ? nil : Int(trimmedSortIndex)
        }

        private var preparedImages: [OMERecord.ImageAsset] {
            var images = (draft.images ?? []).filter {
                $0.role != .logo && $0.role != .hero
            }

            images.append(contentsOf: preservedNonURLImages(role: .logo, replacementURL: trimmedLogoURL))
            images.append(contentsOf: preservedNonURLImages(role: .hero, replacementURL: trimmedHeroImageURL))

            if let logoURL = trimmedLogoURL.nilIfEmpty.flatMap(URL.init(string:)) {
                images.append(
                    OMERecord.ImageAsset(
                        source: .url(logoURL),
                        role: .logo,
                        renderKind: .transparent,
                        materializationPolicy: .prefetchOnOpen
                    )
                )
            }

            if let heroImageURL = trimmedHeroImageURL.nilIfEmpty.flatMap(URL.init(string:)) {
                images.append(
                    OMERecord.ImageAsset(
                        source: .url(heroImageURL),
                        role: .hero,
                        renderKind: .fullImage,
                        materializationPolicy: .prefetchOnOpen
                    )
                )
            }

            return images
        }

        private var trimmedColorHex: String {
            colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private var trimmedHeroImageURL: String {
            heroImageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private var trimmedLogoURL: String {
            logoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private var trimmedName: String {
            draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private var trimmedSortIndex: String {
            sortIndex.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private func preservedNonURLImages(
            role: OMERecord.ImageAsset.Role,
            replacementURL: String
        ) -> [OMERecord.ImageAsset] {
            guard replacementURL.isEmpty else { return [] }
            return (draft.images ?? []).filter { $0.role == role && $0.url == nil }
        }

        private static func emptyDraft(
            stageID: OMERecord.ID<OMERecord.Stage>?,
            eventID: OMERecord.Event.ID
        ) -> OMERecord.Stage.Draft {
            OMERecord.Stage.Draft(
                id: stageID.map {
                    OMERecord.Stage.ID(
                        organizerID: eventID.organizerID,
                        eventID: eventID.eventID,
                        stageID: $0
                    )
                },
                name: "",
                color: 0x336699,
                category: nil,
                sortIndex: nil,
                images: nil,
                systemIconName: nil,
                iconShortCode: nil,
                lineup: nil
            )
        }

        private static func localID(_ string: String) -> OMERecord.ID<OMERecord.Stage> {
            OMERecord.ID<OMERecord.Stage>(.init(string))
        }

        private static func parseHexColor(_ string: String) -> OMEColor? {
            var value = string

            if value.hasPrefix("#") {
                value.removeFirst()
            } else if value.hasPrefix("0x") || value.hasPrefix("0X") {
                value.removeFirst(2)
            }

            guard value.count == 6,
                  let rawValue = Int(value, radix: 16),
                  (0...0xFFFFFF).contains(rawValue) else {
                return nil
            }

            return OMEColor(rawValue)
        }

        private static func stageIDBase(for name: String) -> String {
            let normalized = name
                .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
                .lowercased()
            let words = normalized
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }

            return words.isEmpty
                ? "stage-\(UUID().uuidString.lowercased())"
                : words.joined(separator: "-")
        }
    }

    public enum Action {
        case cancelButtonTapped
        case saveButtonTapped
    }

    @Dependency(\.defaultDatabase) var database

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .cancelButtonTapped:
                store.addTask {
                    try store.dismiss()
                }

            case .saveButtonTapped:
                guard !state.isSaving else { return }
                guard state.hasLoadedDraft else {
                    state.errorMessage = "This event stage could not be loaded."
                    return
                }

                guard let validationMessage = state.validationMessage else {
                    state.errorMessage = nil
                    state.isSaving = true
                    let draftState = state

                    store.addTask {
                        do {
                            try database.write { db in
                                let stageID = try draftState.stageID(in: db)
                                guard let draft = draftState.preparedDraft(stageID: stageID) else {
                                    throw EditStageSaveError()
                                }
                                try OMERecord.Stage.upsert {
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
                                $0.errorMessage = "Unable to save event stage."
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
            guard let stageID = state.mode.stageID else {
                state.hasLoadedDraft = true
                state.errorMessage = nil
                return
            }

            do {
                if let stage = try database.read({ db in
                    try StageDetail.stageQuery(
                        stageID: stageID,
                        eventID: state.eventID
                    )
                    .fetchOne(db)
                }) {
                    state.draft = stage.editDraft
                    state.sortIndex = state.draft.sortIndex.map(String.init) ?? ""
                    state.colorHex = Self.State.formatHexColor(state.draft.color)
                    state.logoURL = state.draft.iconImageURL?.absoluteString ?? ""
                    state.heroImageURL = state.draft.imageURL?.absoluteString ?? ""
                    state.hasLoadedDraft = true
                    state.errorMessage = nil
                } else {
                    state.errorMessage = "This event stage could not be loaded."
                }
            } catch {
                state.errorMessage = "This event stage could not be loaded."
            }
        }
    }
}

private struct EditStageSaveError: Error {}

public struct EditStageView: View {
    @Bindable var store: StoreOf<EditStage>

    public init(store: StoreOf<EditStage>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if store.hasLoadedDraft {
                Form {
                    Section("Event Stage") {
                        TextField("Name", text: $store.draft.name)
                        TextField("Category", text: $store.category)
                        TextField("Sort Index", text: $store.sortIndex)
                            #if os(iOS)
                            .keyboardType(.numbersAndPunctuation)
                            #endif
                        TextField("Color Hex", text: $store.colorHex)
                            #if os(iOS)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            #endif
                    }

                    Section("Icon") {
                        TextField("SF Symbol", text: $store.systemIconName)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            #endif
                        TextField("Short Code", text: $store.iconShortCode)
                            #if os(iOS)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            #endif
                    }

                    Section("Images") {
                        TextField("Logo URL", text: $store.logoURL)
                            #if os(iOS)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            #endif
                        TextField("Hero Image URL", text: $store.heroImageURL)
                            #if os(iOS)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            #endif
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
                    systemImage: "square.grid.2x2",
                    description: "This event stage could not be loaded."
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

struct StageRowView: View {
    let stage: OMERecord.Stage

    var body: some View {
        HStack(spacing: 12) {
            StageArtworkView(stage: stage, size: 60)

            VStack(alignment: .leading, spacing: 3) {
                Text(stage.name)
                    .lineLimit(1)

                if let category = stage.category?.displayName {
                    Text(category)
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

struct StageArtworkView: View {
    let stage: OMERecord.Stage
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(stage.color.swiftUIColor.opacity(0.18))

            ImageAssetAsyncImage(
                asset: stage.images?.imageAsset(role: .logo),
                cacheContext: .init(stageID: stage.id),
                contentMode: .fit
            ) {
                StageIconFallback(stage: stage, size: size)
            }
            .foregroundStyle(stage.color.swiftUIColor)
            .padding(10)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct StageIconFallback: View {
    let stage: OMERecord.Stage
    let size: CGFloat

    var body: some View {
        if let systemIconName = stage.systemIconName {
            Image(systemName: systemIconName)
                .font(.system(size: size * 0.42, weight: .semibold))
        } else if let iconShortCode = stage.iconShortCode {
            Text(iconShortCode)
                .font(.system(size: size * 0.36, weight: .heavy))
                .lineLimit(1)
                #if os(iOS)
                .minimumScaleFactor(0.2)
                #endif
        } else {
            Text(stage.initials)
                .font(.system(size: size * 0.36, weight: .heavy))
                .lineLimit(1)
                #if os(iOS)
                .minimumScaleFactor(0.2)
                #endif
        }
    }
}

private extension OMERecord.Stage {
    var editDraft: OMERecord.Stage.Draft {
        OMERecord.Stage.Draft(
            id: id,
            name: name,
            color: color,
            category: category,
            sortIndex: sortIndex,
            images: images,
            systemIconName: systemIconName,
            iconShortCode: iconShortCode,
            lineup: lineup
        )
    }

    var hasDisplayDetails: Bool {
        category?.displayName != nil || sortIndex != nil
    }

    var initials: String {
        let initials = name
            .split(separator: " ")
            .filter { !$0.localizedCaseInsensitiveContains("the") }
            .compactMap(\.first)
            .prefix(2)
            .map(String.init)
            .joined()
        return initials.isEmpty ? "?" : initials
    }
}

private extension OMERecord.Stage.Category {
    var displayName: String? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value.scheduleDivisionTitle
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var scheduleDivisionTitle: String {
        split { $0 == "-" || $0 == "_" || $0 == " " }
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

private extension EditStage.State {
    static func formatHexColor(_ color: OMEColor) -> String {
        String(format: "#%06X", color.rawValue & 0xFFFFFF)
    }
}
