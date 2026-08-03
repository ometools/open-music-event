import ComposableArchitecture2
import Foundation
import OpenMusicEventComponents
import OpenMusicEventDatabase
import OpenMusicEventImages
import SQLiteData
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

@Feature
public struct PostersViewer {
    public init() {}

    public struct State {
        public init(
            eventID: OMERecord.Event.ID? = nil,
            destination: Destination.State? = nil,
            importImages: Spawn<ImportImages>? = nil
        ) {
            @Dependency(EventViewerContext.self) var eventViewer
            let eventID = eventID ?? eventViewer.eventID
            self.eventID = eventID
            self.destination = destination
            self.importImages = importImages
            _posters = FetchAll(
                PostersViewer.postersQuery(eventID: eventID)
            )
        }

        let eventID: OMERecord.Event.ID
        var destination: Destination.State?
        var importImages: Spawn<ImportImages>?
        @FetchAll public var posters: [OMERecord.Poster]

        var sortedPosters: [OMERecord.Poster] {
            posters.sorted { lhs, rhs in
                let lhsTitle = lhs.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                let rhsTitle = rhs.title?.trimmingCharacters(in: .whitespacesAndNewlines)

                switch (lhsTitle?.isEmpty == false ? lhsTitle : nil, rhsTitle?.isEmpty == false ? rhsTitle : nil) {
                case let (.some(lhsTitle), .some(rhsTitle)):
                    let comparison = lhsTitle.localizedStandardCompare(rhsTitle)
                    if comparison != .orderedSame {
                        return comparison == .orderedAscending
                    }

                case (.some, .none):
                    return true

                case (.none, .some):
                    return false

                case (.none, .none):
                    break
                }

                return lhs.id.posterID.rawValue.rawValue.localizedStandardCompare(
                    rhs.id.posterID.rawValue.rawValue
                ) == .orderedAscending
            }
        }
    }

    public enum Action {
        case addButtonTapped
        case destination(Destination.Action)
        case posterButtonTapped(OMERecord.Poster.ID)
    }

    @Feature
    public enum Destination {
        case posterDetail(Spawn<PosterDetail>)
    }

    @Dependency(\.defaultDatabase) var database

    static func postersQuery(
        eventID: OMERecord.Event.ID
    ) -> some SelectStatementOf<OMERecord.Poster> {
        OMERecord.Poster
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
    }

    static func posterQuery(
        posterID: OMERecord.Poster.ID
    ) -> some SelectStatementOf<OMERecord.Poster> {
        OMERecord.Poster
            .where { $0.id.organizerID.eq(posterID.organizerID) }
            .where { $0.id.eventID.eq(posterID.eventID) }
            .where { $0.id.posterID.eq(posterID.posterID) }
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .addButtonTapped:
                state.importImages = Spawn(
                    ImportImages.State(configuration: .posters)
                )

            case .destination:
                break

            case let .posterButtonTapped(posterID):
                guard state.posters.contains(where: { $0.id == posterID }) else { return }
                store.withDependencies {
                    state.destination = .posterDetail(
                        Spawn(
                            PosterDetail.State(posterID: posterID)
                        )
                    )
                }
            }
        }
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
        .ifLet(\.importImages) {
            let database = database
            let eventID = store.eventID
            ImportImages { images in
                try await Self.savePosters(
                    images,
                    eventID: eventID,
                    database: database
                )
            }
        }
    }

    private static func savePosters(
        _ images: [ImportImages.ImportedImage],
        eventID: OMERecord.Event.ID,
        database: any DatabaseWriter
    ) async throws {
        let images = images.normalizingIncompleteAppearancePairs()
        try await database.write { db in
            var usedPosterIDs = Set(
                try Self.postersQuery(eventID: eventID)
                    .fetchAll(db)
                    .map { $0.id.posterID.rawValue.rawValue }
            )
            var blobs: [LocalImageBlob] = []

            for image in images {
                let localPosterID = Self.uniquePosterID(
                    for: image,
                    usedPosterIDs: &usedPosterIDs
                )
                let posterID = OMERecord.Poster.ID(
                    organizerID: eventID.organizerID,
                    eventID: eventID.eventID,
                    posterID: localPosterID
                )
                let materializedImage = try materializeImportedLocalImage(
                    image.localImageImportRequest,
                    context: .init(posterID: posterID)
                )
                let poster = OMERecord.Poster.Draft(
                    id: posterID,
                    title: image.trimmedTitle.nilIfEmpty,
                    image: materializedImage.image
                )

                try OMERecord.Poster.upsert { poster }.execute(db)
                blobs.append(materializedImage.blob)
            }

            if !blobs.isEmpty {
                try LocalImageBlob.upsert { blobs }.execute(db)
            }
        }
    }

    private static func uniquePosterID(
        for image: ImportImages.ImportedImage,
        usedPosterIDs: inout Set<String>
    ) -> OMERecord.ID<OMERecord.Poster> {
        let base = posterIDBase(for: image.suggestedIDSource)
        var candidate = base
        var suffix = 2

        while usedPosterIDs.contains(candidate) {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }

        usedPosterIDs.insert(candidate)
        return OMERecord.ID<OMERecord.Poster>(.init(candidate))
    }

    private static func posterIDBase(for string: String) -> String {
        let normalized = string
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
        let words = normalized
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        return words.isEmpty ? "poster" : words.joined(separator: "-")
    }
}

@Feature
public struct PosterDetail {
    public init() {}

    public struct State: Identifiable {
        public init(
            posterID: OMERecord.Poster.ID,
            destination: Destination.State? = nil
        ) {
            self.posterID = posterID
            self.destination = destination
            _poster = FetchOne(
                PostersViewer.posterQuery(posterID: posterID)
            )
        }

        public let posterID: OMERecord.Poster.ID
        public var destination: Destination.State?
        @FetchOne public var poster: OMERecord.Poster?

        public var id: OMERecord.Poster.ID { posterID }

        var navigationTitle: String {
            poster?.displayTitle ?? "Poster"
        }
    }

    public enum Action {
        case destination(Destination.Action)
        case editButtonTapped
    }

    @Feature
    public enum Destination {
        case editPoster(Spawn<EditPoster>)
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .destination:
                break

            case .editButtonTapped:
                state.destination = .editPoster(
                    Spawn(
                        EditPoster.State(posterID: state.posterID)
                    )
                )
            }
        }
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
        .onEvent(PosterDeleted.self) { posterID, state in
            guard posterID == state.posterID else { return }
            store.addTask {
                try store.dismiss()
            }
        }
    }
}

public struct PosterDetailView: View {
    @Bindable var store: StoreOf<PosterDetail>
    let showsAuthoringControls: Bool

    public init(
        store: StoreOf<PosterDetail>,
        showsAuthoringControls: Bool = true
    ) {
        self.store = store
        self.showsAuthoringControls = showsAuthoringControls
    }

    public var body: some View {
        Group {
            if let poster = store.poster {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ImageAssetAsyncImage(
                            asset: poster.image,
                            cacheContext: .init(posterID: poster.id),
                            contentMode: .fit
                        ) {
                            PosterPlaceholderView()
                        }
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        if let title = poster.displayTitle {
                            Text(title)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding()
                }
            } else {
                ViewerPlaceholderView(
                    title: "Poster",
                    systemImage: "photo",
                    description: "This poster could not be loaded."
                )
            }
        }
        .navigationTitle(store.navigationTitle)
        .toolbar {
            if showsAuthoringControls {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        store.send(.editButtonTapped)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(store.poster == nil)
                }
            }
        }
        .sheet(item: $store.scope(\.destination, action: \.destination).editPoster) { editStore in
            NavigationStack {
                EditPosterView(store: editStore)
            }
        }
    }
}

@Feature
public struct EditPoster {
    public init() {}

    public struct State {
        public init(
            posterID: OMERecord.Poster.ID,
            destination: Destination.State? = nil,
            imageInfo: Spawn<ImageInfo>? = nil
        ) {
            self.destination = destination
            self.posterID = posterID
            self.imageInfo = imageInfo
        }

        public var destination: Destination.State?
        public let posterID: OMERecord.Poster.ID
        public var imageInfo: Spawn<ImageInfo>?
        var errorMessage: String?
        var hasLoadedDraft = false
        var isDeleting = false
        var isSaving = false
        var title = ""

        var canDelete: Bool {
            hasLoadedDraft && !isWorking
        }

        var canSubmit: Bool {
            hasLoadedDraft && !isWorking && imageInfo != nil
        }

        var isWorking: Bool {
            isDeleting || isSaving
        }

        var navigationTitle: String {
            "Edit Poster"
        }

        var trimmedTitle: String {
            title.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func preparedDraft() throws -> OMERecord.Poster.Draft {
            guard let image = imageInfo?.asset else { throw EditPosterSaveError() }
            return OMERecord.Poster.Draft(
                id: posterID,
                title: trimmedTitle.nilIfEmpty,
                image: [image].normalizingIncompleteAppearancePairs()[0]
            )
        }
    }

    public enum Action {
        case cancelButtonTapped
        case deleteButtonTapped
        case destination(Destination.Action)
        case saveButtonTapped
    }

    @Feature
    public enum Destination {
        case deleteConfirmation(DeleteConfirmation)
    }

    @Feature
    public struct DeleteConfirmation: Prompt {
        public enum Action {
            case deleteButtonTapped
        }
    }

    @Dependency(\.defaultDatabase) var database

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .cancelButtonTapped:
                store.addTask {
                    try store.dismiss()
                }

            case .deleteButtonTapped:
                guard state.canDelete else { return }
                state.destination = .deleteConfirmation(DeleteConfirmation.State())

            case .destination(.deleteConfirmation(.deleteButtonTapped)):
                guard !state.isWorking else { return }
                let posterID = state.posterID
                state.errorMessage = nil
                state.isDeleting = true

                store.addTask {
                    do {
                        try await Self.deletePoster(
                            posterID: posterID,
                            database: database
                        )
                        try store.post(key: PosterDeleted.self, value: posterID)
                        try store.modify {
                            $0.errorMessage = nil
                            $0.isDeleting = false
                        }
                        _ = try? store.dismiss()
                    } catch {
                        try store.modify {
                            $0.errorMessage = editPosterDeleteErrorMessage(error)
                            $0.isDeleting = false
                        }
                    }
                }

            case .saveButtonTapped:
                guard !state.isWorking else { return }
                guard state.hasLoadedDraft else {
                    state.errorMessage = "This poster could not be loaded."
                    return
                }

                do {
                    let draft = try state.preparedDraft()
                    let posterID = state.posterID
                    state.errorMessage = nil
                    state.isSaving = true

                    store.addTask {
                        do {
                            try database.write { db in
                                guard try PostersViewer.posterQuery(posterID: posterID)
                                    .fetchOne(db) != nil else {
                                    throw EditPosterSaveError()
                                }
                                try OMERecord.Poster.upsert { draft }.execute(db)
                            }
                            try store.modify {
                                $0.errorMessage = nil
                                $0.isSaving = false
                            }
                            try store.dismiss()
                        } catch {
                            try store.modify {
                                $0.errorMessage = editPosterErrorMessage(error)
                                $0.isSaving = false
                            }
                        }
                    }
                } catch {
                    state.errorMessage = editPosterErrorMessage(error)
                }
            }
        }
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
        .ifLet(\.imageInfo) {
            ImageInfo()
        }
        .onMount { state in
            guard !state.hasLoadedDraft else { return }

            do {
                if let poster = try database.read({ db in
                    try PostersViewer.posterQuery(posterID: state.posterID)
                        .fetchOne(db)
                }) {
                    state.title = poster.title ?? ""
                    state.imageInfo = Spawn(
                        ImageInfo.State(
                            asset: poster.image,
                            configuration: .posters,
                            sourceLabel: poster.displayTitle ?? poster.image.url?.lastPathComponent,
                            cacheContext: LocalImageCacheContext(posterID: poster.id)
                        )
                    )
                    state.hasLoadedDraft = true
                    state.errorMessage = nil
                } else {
                    state.errorMessage = "This poster could not be loaded."
                }
            } catch {
                state.errorMessage = "This poster could not be loaded."
            }
        }
    }

    private static func deletePoster(
        posterID: OMERecord.Poster.ID,
        database: any DatabaseWriter
    ) async throws {
        try await database.write { db in
            guard try PostersViewer.posterQuery(posterID: posterID)
                .fetchOne(db) != nil else {
                throw EditPosterDeleteError()
            }

            try OMERecord.Poster
                .where { $0.id.organizerID.eq(posterID.organizerID) }
                .where { $0.id.eventID.eq(posterID.eventID) }
                .where { $0.id.posterID.eq(posterID.posterID) }
                .delete()
                .execute(db)

            try LocalImageBlob
                .where { $0.organizerID.eq(posterID.organizerID) }
                .where { $0.eventID.eq(posterID.eventID) }
                .where { $0.parentKind.eq(LocalImageBlob.ParentKind.poster) }
                .where { $0.parentLocalID.eq(posterID.posterID.rawValue.rawValue) }
                .delete()
                .execute(db)
        }
    }
}

private enum PosterDeleted: FeatureEventKey {
    typealias Value = OMERecord.Poster.ID
}

private struct EditPosterDeleteError: LocalizedError {
    var errorDescription: String? {
        "This poster could not be loaded."
    }
}

private struct EditPosterSaveError: Error {}

private func editPosterDeleteErrorMessage(_ error: any Error) -> String {
    let description = error.localizedDescription
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !description.isEmpty else {
        return "Unable to delete poster."
    }
    return "Unable to delete poster: \(description)"
}

private func editPosterErrorMessage(_ error: any Error) -> String {
    let description = error.localizedDescription
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !description.isEmpty else {
        return "Unable to save poster."
    }
    return "Unable to save poster: \(description)"
}

public struct EditPosterView: View {
    @Bindable var store: StoreOf<EditPoster>

    public init(store: StoreOf<EditPoster>) {
        self.store = store
    }

    public var body: some View {
        content
            .disabled(store.isWorking)
            .navigationTitle(store.navigationTitle)
            .toolbar {
                toolbarContent
            }
            .confirmationDialog(
                "Delete Poster?",
                isPresented: $store.scope(\.destination, action: \.destination).deleteConfirmation.isPresented,
                titleVisibility: .visible
            ) {
                Button("Delete Poster", role: .destructive) {
                    store.send(.destination(.deleteConfirmation(.deleteButtonTapped)))
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the poster from this event.")
            }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if store.hasLoadedDraft {
                editForm
            } else {
                ViewerPlaceholderView(
                    title: store.navigationTitle,
                    systemImage: "photo",
                    description: "This poster could not be loaded."
                )
            }
        }
    }

    private var editForm: some View {
        Form {
            Section("Poster") {
                TextField("Title", text: $store.title)
            }

            if let imageInfoStore = store.spawn(\.imageInfo) {
                ImageInfoEditorSection(store: imageInfoStore)
            }

            if let errorMessage = store.errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button("Delete Poster", role: .destructive) {
                    store.send(.deleteButtonTapped)
                }
                .disabled(!store.canDelete)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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
                isInProgress: store.isSaving || store.isDeleting,
                isDisabled: !store.canSubmit
            ) {
                store.send(.saveButtonTapped)
            }
        }
    }
}

public struct PostersViewerView: View {
    @Bindable var store: StoreOf<PostersViewer>
    let showsAuthoringControls: Bool

    public init(
        store: StoreOf<PostersViewer>,
        showsAuthoringControls: Bool = true
    ) {
        self.store = store
        self.showsAuthoringControls = showsAuthoringControls
    }

    public var body: some View {
        Group {
            if store.posters.isEmpty {
                ContentUnavailableView {
                    Label(
                        "Posters",
                        mappedSystemImage: "photo.on.rectangle"
                    )
                } description: {
                    Text("No posters have been added to this event yet.")
                } actions: {
                    if showsAuthoringControls {
                        Button {
                            store.send(.addButtonTapped)
                        } label: {
                            Label("Add Posters", systemImage: "plus")
                        }
                    }
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(store.sortedPosters) { poster in
                            PosterCardView(poster: poster) {
                                store.send(.posterButtonTapped(poster.id))
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Posters")
        .toolbar {
            if showsAuthoringControls {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        store.send(.addButtonTapped)
                    } label: {
                        Image(systemName: "plus")
                            .accessibilityLabel("Add Posters")
                    }
                }
            }
        }
        .navigationDestination(item: $store.scope(\.destination, action: \.destination).posterDetail) { detailStore in
            PosterDetailView(
                store: detailStore,
                showsAuthoringControls: showsAuthoringControls
            )
        }
        .sheet(isPresented: $store.importImages.isPresented) {
            if let importStore = store.spawn(\.importImages) {
                NavigationStack {
                    ImportImagesView(store: importStore)
                }
            }
        }
    }
}

struct PosterCardView: View {
    let poster: OMERecord.Poster
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                ImageAssetAsyncImage(
                    asset: poster.image,
                    cacheContext: .init(posterID: poster.id),
                    contentMode: .fit
                ) {
                    PosterPlaceholderView()
                }
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if let title = displayTitle {
                    Text(title)
                        .font(.headline)
                        .padding(.horizontal, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .portableContentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var displayTitle: String? { poster.displayTitle }
}

struct PosterPlaceholderView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.secondary.opacity(0.12))
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
    }
}

extension Optional {
    var isPresented: Bool {
        get { self != nil }
        set {
            guard !newValue else { return }
            self = nil
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension OMERecord.Poster {
    var displayTitle: String? {
        let title = self.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return title?.isEmpty == false ? title : nil
    }
}
