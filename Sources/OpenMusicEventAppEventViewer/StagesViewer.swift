import BlueskyActorCache
import ComposableForms
import ComposableArchitecture2
import Dependencies
import Foundation
#if !SKIP && canImport(AppKit)
import AppKit
#elseif !SKIP && canImport(UIKit)
import UIKit
#endif
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
            destination: Destination.State? = nil
        ) {
            self.eventID = eventID
            self.destination = destination
            _stages = FetchAll(
                StagesViewer.stagesQuery(eventID: eventID)
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
                store.withDependencies {
                    state.destination = .stageDetail(
                        Spawn(.init(stageID: stageID, eventID: state.eventID))
                    )
                }
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
        .sheet(item: $store.scope(\.destination, action: \.destination).createStage) { createStore in
            NavigationStack {
                EditStageView(store: createStore)
            }
        }
        .navigationDestination(item: $store.scope(\.destination, action: \.destination).stageDetail) { detailStore in
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
        @FetchAll var contributors: [ContributorProfile]

        public init(
            stageID: OMERecord.ID<OMERecord.Stage>,
            eventID: OMERecord.Event.ID? = nil
        ) {
            @Dependency(\.defaultEventID) var defaultEventID

            self.stageID = stageID
            self.eventID = eventID ?? defaultEventID
            _stage = FetchOne(
                StageDetail.stageQuery(
                    stageID: stageID,
                    eventID: self.eventID
                )
            )
            _contributors = FetchAll(
                ContributorsViewer.contributorProfilesQuery(
                    eventID: self.eventID,
                    hydration: .bskyActorProfile
                )
            )
        }

        public var id: OMERecord.ID<OMERecord.Stage> { stageID }

        var lineupContributors: [ContributorProfile] {
            guard let lineup = stage?.lineup, !lineup.isEmpty else { return [] }
            let contributorsByID = Dictionary(
                uniqueKeysWithValues: contributors.map { ($0.contributorID, $0) }
            )
            return lineup.compactMap { contributorsByID[$0] }
        }

        var actorProfileLoadRequests: [ContributorProfile.ActorProfileLoadRequest] {
            lineupContributors.actorProfileLoadRequests
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

    @Dependency(\.blueskyActorProfileCache) var blueskyActorProfileCache

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
        .onChange(of: store.actorProfileLoadRequests, initial: true) { _, requests, _ in
            guard !requests.isEmpty else { return }

            store.addTask {
                for request in requests {
                    do {
                        _ = try await blueskyActorProfileCache.refreshProfileIfNeeded(
                            request.actor.description,
                            24 * 60 * 60,
                            15 * 60
                        )
                    } catch is CancellationError {
                        return
                    } catch {
                    }
                }
            }
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

                    if !store.lineupContributors.isEmpty {
                        Section("Lineup") {
                            ForEach(store.lineupContributors) { contributor in
                                ContributorsRowView(profile: contributor)
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
        .sheet(item: $store.scope(\.destination, action: \.destination).editStage) { editStore in
            NavigationStack {
                EditStageView(store: editStore)
            }
        }
    }
}

@Feature
public struct EditStage {
    public init() {}

    public struct FormValue: Equatable {
        var category = ""
        var color: OMEColor = 0x336699
        var iconShortCode = ""
        var name = ""
        var sortIndex = ""
        var systemIconName = ""

        init() {}

        init(draft: OMERecord.Stage.Draft) {
            category = draft.category?.rawValue ?? ""
            color = draft.color
            iconShortCode = draft.iconShortCode ?? ""
            name = draft.name
            sortIndex = draft.sortIndex.map(String.init) ?? ""
            systemIconName = draft.systemIconName ?? ""
        }
    }

    public typealias FormFeature = ComposableForms.Form<FormValue>

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
            let draft = Self.emptyDraft(stageID: nil, eventID: eventID)
            self.draft = draft
            self.form = FormFeature.State(value: FormValue(draft: draft))
            self.heroImagePicker = ImageAssetPicker.State(configuration: .stageHero, assets: draft.images)
            self.logoImagePicker = ImageAssetPicker.State(configuration: .stageLogo, assets: draft.images)
            self.posterImagePicker = ImageAssetPicker.State(configuration: .stagePoster, assets: draft.images)
            self.hasLoadedDraft = true
        }

        public init(
            stageID: OMERecord.ID<OMERecord.Stage>,
            eventID: OMERecord.Event.ID
        ) {
            self.eventID = eventID
            self.mode = .edit(stageID)
            let draft = Self.emptyDraft(stageID: stageID, eventID: eventID)
            self.draft = draft
            self.form = FormFeature.State(value: FormValue(draft: draft))
            let cacheContext = LocalImageCacheContext(
                stageID: OMERecord.Stage.ID(
                    organizerID: eventID.organizerID,
                    eventID: eventID.eventID,
                    stageID: stageID
                )
            )
            self.heroImagePicker = ImageAssetPicker.State(
                configuration: .stageHero,
                assets: draft.images,
                cacheContext: cacheContext
            )
            self.logoImagePicker = ImageAssetPicker.State(
                configuration: .stageLogo,
                assets: draft.images,
                cacheContext: cacheContext
            )
            self.posterImagePicker = ImageAssetPicker.State(
                configuration: .stagePoster,
                assets: draft.images,
                cacheContext: cacheContext
            )
        }

        public let eventID: OMERecord.Event.ID
        public let mode: Mode

        var draft: OMERecord.Stage.Draft {
            didSet {
                form.value = FormValue(draft: draft)
                resetImagePickers()
            }
        }
        var errorMessage: String?
        var form: FormFeature.State
        var hasLoadedDraft = false
        var heroImagePicker: ImageAssetPicker.State
        var isSaving = false
        var logoImagePicker: ImageAssetPicker.State
        var posterImagePicker: ImageAssetPicker.State

        var category: String {
            get { form.value.category }
            set { form.value.category = newValue }
        }

        var color: OMEColor {
            get { form.value.color }
            set { form.value.color = newValue }
        }

        var colorHex: String {
            get { Self.formatHexColor(color) }
            set {
                guard let color = Self.parseHexColor(
                    newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                ) else { return }
                self.color = color
            }
        }

        var heroImageURL: String {
            get { heroImagePicker.firstURLString }
            set { heroImagePicker.replaceURLString(newValue) }
        }

        var iconShortCode: String {
            get { form.value.iconShortCode }
            set { form.value.iconShortCode = newValue }
        }

        var logoURL: String {
            get { logoImagePicker.firstURLString }
            set { logoImagePicker.replaceURLString(newValue) }
        }

        var sortIndex: String {
            get { form.value.sortIndex }
            set { form.value.sortIndex = newValue }
        }

        var systemIconName: String {
            get { form.value.systemIconName }
            set { form.value.systemIconName = newValue }
        }

        public var stageID: OMERecord.ID<OMERecord.Stage>? {
            mode.stageID
        }

        var canSubmit: Bool {
            hasLoadedDraft && !isSaving && form.canSubmit
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
        ) throws -> (draft: OMERecord.Stage.Draft, blobs: [LocalImageBlob]) {
            var draft = draft
            let stageRecordID = stageRecordID(stageID: stageID)
            let preparedImages = try preparedImages(
                context: .init(stageID: stageRecordID)
            )
            draft.id = stageRecordID
            draft.name = trimmedName
            draft.category = trimmedCategory.nilIfEmpty.map { OMERecord.Stage.Category($0) }
            draft.color = color
            draft.iconShortCode = trimmedIconShortCode.nilIfEmpty
            draft.sortIndex = parsedSortIndex
            draft.systemIconName = trimmedSystemIconName.nilIfEmpty
            draft.images = preparedImages.images.isEmpty ? nil : preparedImages.images
            return (draft, preparedImages.blobs)
        }

        var validationMessage: String? {
            guard hasLoadedDraft else { return nil }

            if trimmedName.isEmpty {
                return "Enter a name."
            }

            if !trimmedSortIndex.isEmpty, parsedSortIndex == nil {
                return "Enter a valid sort index."
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

        mutating func resetImagePickers() {
            let cacheContext = imageCacheContext
            heroImagePicker = ImageAssetPicker.State(
                configuration: .stageHero,
                assets: draft.images,
                cacheContext: cacheContext
            )
            logoImagePicker = ImageAssetPicker.State(
                configuration: .stageLogo,
                assets: draft.images,
                cacheContext: cacheContext
            )
            posterImagePicker = ImageAssetPicker.State(
                configuration: .stagePoster,
                assets: draft.images,
                cacheContext: cacheContext
            )
        }

        private var imageCacheContext: LocalImageCacheContext? {
            if let id = draft.id {
                return LocalImageCacheContext(stageID: id)
            }
            if let stageID = mode.stageID {
                return LocalImageCacheContext(stageID: stageRecordID(stageID: stageID))
            }
            return nil
        }

        private var parsedSortIndex: Int? {
            trimmedSortIndex.isEmpty ? nil : Int(trimmedSortIndex)
        }

        private func preparedImages(
            context: LocalImageCacheContext
        ) throws -> (images: [OMERecord.ImageAsset], blobs: [LocalImageBlob]) {
            var images = (draft.images ?? []).filter {
                $0.role != .logo && $0.role != .hero && $0.role != .poster
            }
            var blobs: [LocalImageBlob] = []

            for picker in [logoImagePicker, heroImagePicker, posterImagePicker] {
                let preparedImages = try picker.materializedImages(context: context)
                images.append(contentsOf: preparedImages.images)
                blobs.append(contentsOf: preparedImages.blobs)
            }

            return (images, blobs)
        }

        private var trimmedCategory: String {
            category.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private var trimmedIconShortCode: String {
            iconShortCode.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private var trimmedName: String {
            form.value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private var trimmedSortIndex: String {
            sortIndex.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private var trimmedSystemIconName: String {
            systemIconName.trimmingCharacters(in: .whitespacesAndNewlines)
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

        fileprivate static func parseHexColor(_ string: String) -> OMEColor? {
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
        case form(FormFeature.Action)
        case formSubmitted(FormValue)
        case heroImagePicker(ImageAssetPicker.Action)
        case logoImagePicker(ImageAssetPicker.Action)
        case posterImagePicker(ImageAssetPicker.Action)
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
        Scope(\.heroImagePicker, action: \.heroImagePicker) {
            ImageAssetPicker()
        }
        Scope(\.logoImagePicker, action: \.logoImagePicker) {
            ImageAssetPicker()
        }
        Scope(\.posterImagePicker, action: \.posterImagePicker) {
            ImageAssetPicker()
        }
        Update { state, action in
            switch action {
            case .cancelButtonTapped:
                store.addTask {
                    try store.dismiss()
                }

            case .form:
                break

            case .formSubmitted:
                guard !state.isSaving else { return }
                guard state.hasLoadedDraft else {
                    state.errorMessage = "This event stage could not be loaded."
                    return
                }

                state.errorMessage = nil
                state.isSaving = true
                let draftState = state

                store.addTask {
                    do {
                        try database.write { db in
                            let stageID = try draftState.stageID(in: db)
                            let preparedDraft = try draftState.preparedDraft(stageID: stageID)
                            try OMERecord.Stage.upsert {
                                preparedDraft.draft
                            }
                            .execute(db)
                            if !preparedDraft.blobs.isEmpty {
                                try LocalImageBlob.insert { preparedDraft.blobs }.execute(db)
                            }
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

            case .heroImagePicker, .logoImagePicker, .posterImagePicker:
                break

            case .saveButtonTapped:
                guard !state.isSaving else { return }
                guard state.hasLoadedDraft else {
                    state.errorMessage = "This event stage could not be loaded."
                    return
                }

                store.addTask {
                    try store.send(.form(.submittedForm))
                }
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
                    state.form = FormFeature.State(value: FormValue(draft: state.draft))
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

private enum EditStageFormFieldID {
    static var name: AnyHashable { AnyHashable(\EditStage.FormValue.name) }
    static var sortIndex: AnyHashable { AnyHashable(\EditStage.FormValue.sortIndex) }
}

private extension EditStage.FormFeature {
    init() {
        self.init {
            Self.Field(\.name) {
                Validation(error: "Enter a name.") {
                    !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            }

            Self.Field(\.sortIndex) {
                Validation(error: "Enter a valid sort index.") { value in
                    let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    return value.isEmpty || Int(value) != nil
                }
            }

            Self.Field(\.color)
        }
    }
}

public struct EditStageView: View {
    @Bindable var store: StoreOf<EditStage>
    @FocusState var focusedField: AnyHashable?

    public init(store: StoreOf<EditStage>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if store.hasLoadedDraft {
                loadedForm
            } else {
                ViewerPlaceholderView(
                    title: store.navigationTitle,
                    systemImage: "square.grid.2x2",
                    description: "This event stage could not be loaded."
                )
            }
        }
        .disabled(store.isSaving)
        .onChange(of: focusedField) { _, focusedField in
            if store.form.focusedField != focusedField {
                $store.form.focusedField.wrappedValue = focusedField
            }
        }
        .onChange(of: store.form.focusedField) { _, focusedField in
            if self.focusedField != focusedField {
                self.focusedField = focusedField
            }
        }
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

    private var loadedForm: some View {
        SwiftUI.Form {
            eventStageSection
            iconSection
            imageSection
            errorSection
        }
    }

    private var eventStageSection: some View {
        Section("Event Stage") {
            nameField

            TextField("Category", text: $store.form.value.category)

            sortIndexField
            colorField
        }
    }

    private var iconSection: some View {
        Section("Icon") {
            TextField("SF Symbol", text: $store.form.value.systemIconName)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
            TextField("Short Code", text: $store.form.value.iconShortCode)
                #if os(iOS)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                #endif
        }
    }

    private var imageSection: some View {
        Group {
            ImageAssetPickerSection(
                store: store.scope(\.logoImagePicker, action: \.logoImagePicker)
            )
            ImageAssetPickerSection(
                store: store.scope(\.heroImagePicker, action: \.heroImagePicker)
            )
            ImageAssetPickerSection(
                store: store.scope(\.posterImagePicker, action: \.posterImagePicker)
            )
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let errorMessage = store.errorMessage {
            Section {
                Text(verbatim: errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading) {
            TextField("Name", text: $store.form.value.name)
                .focused($focusedField, equals: EditStageFormFieldID.name)
                .onSubmit {
                    store.send(.form(.fieldSubmitted(EditStageFormFieldID.name)))
                }
            validationStatus(for: EditStageFormFieldID.name)
        }
    }

    private var sortIndexField: some View {
        VStack(alignment: .leading) {
            TextField("Sort Index", text: $store.form.value.sortIndex)
                .focused($focusedField, equals: EditStageFormFieldID.sortIndex)
                .onSubmit {
                    store.send(.form(.fieldSubmitted(EditStageFormFieldID.sortIndex)))
                }
            #if os(iOS)
                .keyboardType(.numbersAndPunctuation)
            #endif
            validationStatus(for: EditStageFormFieldID.sortIndex)
        }
    }

    private var colorField: some View {
        ColorPicker(
            "Stage Color",
            selection: $store.form.value.color.editStageColor,
            supportsOpacity: false
        )
    }

    @ViewBuilder
    private func validationStatus(for field: AnyHashable) -> some View {
        FormFieldValidationStatus(validation: store.form.validation[field])
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

private extension OMEColor {
    var editStageColor: Color {
        get { swiftUIColor }
        set {
            guard let color = OMEColor(newValue) else { return }
            self = color
        }
    }

    init?(_ color: Color) {
        #if !SKIP && canImport(UIKit)
        let resolvedColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard resolvedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }
        self.init(red: red, green: green, blue: blue)
        #elseif !SKIP && canImport(AppKit)
        guard let resolvedColor = NSColor(color).usingColorSpace(.sRGB) else {
            return nil
        }
        self.init(
            red: resolvedColor.redComponent,
            green: resolvedColor.greenComponent,
            blue: resolvedColor.blueComponent
        )
        #else
        return nil
        #endif
    }

    init(red: CGFloat, green: CGFloat, blue: CGFloat) {
        self.init(
            (Int((red * 255).rounded()) << 16)
                | (Int((green * 255).rounded()) << 8)
                | Int((blue * 255).rounded())
        )
    }
}
