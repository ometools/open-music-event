import ATProtoTypes
import OpenMusicEventLexicon
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

public struct EventPoster: Equatable, Identifiable, Sendable {
    public struct ID: Equatable, Hashable, Sendable {
        public let eventID: Event.ID
        public let mediaIndex: Int

        public init(eventID: Event.ID, mediaIndex: Int) {
            self.eventID = eventID
            self.mediaIndex = mediaIndex
        }
    }

    public let id: ID
    public let image: OME.Image

    public var displayTitle: String? {
        let title = image.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return title?.isEmpty == false ? title : nil
    }

    public var displayImage: DisplayImageAsset? {
        image.displayImageAsset(recordID: id.eventID)
    }

    public static func all(in event: Event) -> [Self] {
        (event.media ?? []).enumerated().compactMap { index, medium in
            guard case let .known(.image(image)) = medium,
                  image.role == .known(.poster) else { return nil }
            return Self(id: ID(eventID: event.id, mediaIndex: index), image: image)
        }
    }
}

@Feature
public struct PostersViewer {
    public init() {}

    public struct State {
        public init(
            eventID: Event.ID? = nil,
            destination: Destination.State? = nil,
            importImages: Spawn<ImportImages>? = nil
        ) {
            @Dependency(EventViewerContext.self) var eventViewer
            let eventID = eventID ?? eventViewer.eventID
            self.eventID = eventID
            self.destination = destination
            self.importImages = importImages
            _event = FetchOne(Event.find(eventID))
        }

        let eventID: Event.ID
        var destination: Destination.State?
        var importImages: Spawn<ImportImages>?
        @FetchOne public var event: Event?

        public var posters: [EventPoster] {
            event.map(EventPoster.all(in:)) ?? []
        }

        var sortedPosters: [EventPoster] {
            posters.sorted { lhs, rhs in
                let lhsTitle = lhs.displayTitle
                let rhsTitle = rhs.displayTitle

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

                return lhs.id.mediaIndex < rhs.id.mediaIndex
            }
        }
    }

    public enum Action {
        case addButtonTapped
        case destination(Destination.Action)
        case posterButtonTapped(EventPoster.ID)
    }

    @Feature
    public enum Destination {
        case posterDetail(Spawn<PosterDetail>)
    }

    @Dependency(\.defaultDatabase) var database

    public var body: some Feature {
        @Dependency(\.localImageFileStore) var localImageFileStore
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
        .ifLet(\.destination) {
            Destination.body
        }
        .ifLet(\.importImages) {
            let database = database
            let eventID = store.eventID
            let localImageFileStore = localImageFileStore
            ImportImages { images in
                try await Self.savePosters(
                    images,
                    eventID: eventID,
                    database: database,
                    localImageFileStore: localImageFileStore
                )
            }
        }
    }

    private static func savePosters(
        _ images: [ImportImages.ImportedImage],
        eventID: Event.ID,
        database: any DatabaseWriter,
        localImageFileStore: LocalImageFileStoreClient
    ) async throws {
        let images = images.normalizingIncompleteAppearancePairs()
        try await database.write { db in
            guard var event = try Event.find(eventID).fetchOne(db) else {
                throw EditPosterSaveError()
            }
            var media = event.media ?? []

            for image in images {
                let blob = try stageLocalImageBlob(
                    image.data,
                    mimeType: ATProto.MIMEType(rawValue: image.mimeType),
                    using: localImageFileStore
                )
                var poster = image.image
                poster.source = .known(.blob(blob))
                poster.title = image.trimmedTitle.nilIfEmpty
                poster.role = .known(.poster)
                media.append(.known(.image(poster)))
            }

            event.media = media
            try event.validateReferences()
            try Event.upsert { event }.execute(db)
        }
    }
}

@Feature
public struct PosterDetail {
    public init() {}

    public struct State: Identifiable {
        public init(
            posterID: EventPoster.ID,
            destination: Destination.State? = nil
        ) {
            self.posterID = posterID
            self.destination = destination
            _event = FetchOne(Event.find(posterID.eventID))
        }

        public let posterID: EventPoster.ID
        public var destination: Destination.State?
        @FetchOne public var event: Event?

        public var poster: EventPoster? {
            event.flatMap { event in
                EventPoster.all(in: event).first { $0.id == posterID }
            }
        }

        public var id: EventPoster.ID { posterID }

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
        .ifLet(\.destination) {
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
                            image: poster.displayImage,
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
        .sheet(item: $store.scope(\.destination).editPoster) { editStore in
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
            posterID: EventPoster.ID,
            destination: Destination.State? = nil,
            imageInfo: Spawn<ImageInfo>? = nil
        ) {
            self.destination = destination
            self.posterID = posterID
            self.imageInfo = imageInfo
        }

        public var destination: Destination.State?
        public let posterID: EventPoster.ID
        public var imageInfo: Spawn<ImageInfo>?
        var originalImage: OME.Image?
        var errorMessage: String?
        var hasLoadedDraft = false
        var isDeleting = false
        var isSaving = false

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

        func preparedImage() throws -> OME.Image {
            guard var image = imageInfo?.image else { throw EditPosterSaveError() }
            image.role = .known(.poster)
            return image
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
                guard let originalImage = state.originalImage else { return }
                state.errorMessage = nil
                state.isDeleting = true

                store.addTask {
                    do {
                        try await Self.deletePoster(
                            posterID: posterID,
                            originalImage: originalImage,
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
                    let image = try state.preparedImage()
                    guard let originalImage = state.originalImage else {
                        throw EditPosterSaveError()
                    }
                    let posterID = state.posterID
                    state.errorMessage = nil
                    state.isSaving = true

                    store.addTask {
                        do {
                            try database.write { db in
                                guard var event = try Event.find(posterID.eventID).fetchOne(db),
                                      var media = event.media,
                                      media.indices.contains(posterID.mediaIndex),
                                      case let .known(.image(current)) = media[posterID.mediaIndex],
                                      current == originalImage else {
                                    throw EditPosterSaveError()
                                }
                                media[posterID.mediaIndex] = .known(.image(image))
                                event.media = media
                                try event.validateReferences()
                                try Event.upsert { event }.execute(db)
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
        .ifLet(\.destination) {
            Destination.body
        }
        .ifLet(\.imageInfo) {
            ImageInfo()
        }
        .onMount { state in
            guard !state.hasLoadedDraft else { return }

            do {
                if let poster = try database.read({ db in
                    try Event.find(state.posterID.eventID).fetchOne(db)
                        .flatMap { EventPoster.all(in: $0).first { $0.id == state.posterID } }
                }) {
                    guard poster.displayImage != nil else {
                        throw EditPosterSaveError()
                    }
                    state.originalImage = poster.image
                    state.imageInfo = Spawn(
                        ImageInfo.State(
                            image: poster.image,
                            configuration: .posters,
                            sourceLabel: poster.displayTitle,
                            recordID: state.posterID.eventID
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
        posterID: EventPoster.ID,
        originalImage: OME.Image,
        database: any DatabaseWriter
    ) async throws {
        try await database.write { db in
            guard var event = try Event.find(posterID.eventID).fetchOne(db),
                  var media = event.media,
                  media.indices.contains(posterID.mediaIndex),
                  case .known(.image(let image)) = media[posterID.mediaIndex],
                  image == originalImage else {
                throw EditPosterDeleteError()
            }
            media.remove(at: posterID.mediaIndex)
            event.media = media
            try event.validateReferences()
            try Event.upsert { event }.execute(db)
        }
    }
}

private enum PosterDeleted: FeatureEventKey {
    typealias Value = EventPoster.ID
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
                isPresented: $store.scope(\.destination).deleteConfirmation.isPresented,
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
        .navigationDestination(item: $store.scope(\.destination).posterDetail) { detailStore in
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
    let poster: EventPoster
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                ImageAssetAsyncImage(
                    image: poster.displayImage,
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
