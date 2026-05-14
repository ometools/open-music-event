import ComposableArchitecture2
import Foundation
import OpenMusicEventDatabase
import SQLiteData
import SwiftUI

@Feature
public struct PostersViewer {
    public init() {}

    public struct State {
        public init(
            eventID: OMERecord.Event.ID? = nil,
            importImages: Spawn<ImportImages>? = nil,
            database: (any DatabaseReader)? = nil
        ) {
            @Dependency(\.defaultEventID) var defaultEventID
            let eventID = eventID ?? defaultEventID
            self.eventID = eventID
            self.importImages = importImages
            _posters = FetchAll(
                PostersViewer.postersQuery(eventID: eventID),
                database: database
            )
        }

        let eventID: OMERecord.Event.ID
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
    }

    @Dependency(\.defaultDatabase) var database

    static func postersQuery(
        eventID: OMERecord.Event.ID
    ) -> some SelectStatementOf<OMERecord.Poster> {
        OMERecord.Poster
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .addButtonTapped:
                state.importImages = Spawn(
                    ImportImages.State(configuration: .posters)
                )
            }
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
                try LocalImageBlob.insert { blobs }.execute(db)
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

public struct PostersViewerView: View {
    @Bindable var store: StoreOf<PostersViewer>

    public init(store: StoreOf<PostersViewer>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if store.posters.isEmpty {
                ContentUnavailableView {
                    Label("Posters", systemImage: "photo.on.rectangle")
                } description: {
                    Text("No posters have been added to this event yet.")
                } actions: {
                    Button {
                        store.send(.addButtonTapped)
                    } label: {
                        Label("Add Posters", systemImage: "plus")
                    }
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(store.sortedPosters) { poster in
                            PosterCardView(poster: poster)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Posters")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.send(.addButtonTapped)
                } label: {
                    Image(systemName: "plus")
                        .accessibilityLabel("Add Posters")
                }
            }
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

    var body: some View {
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
    }

    private var displayTitle: String? {
        let title = poster.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return title?.isEmpty == false ? title : nil
    }
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
