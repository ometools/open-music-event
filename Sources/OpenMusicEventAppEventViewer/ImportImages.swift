import ComposableArchitecture2
import Foundation
import OpenMusicEventDatabase
import SwiftUI

#if !SKIP && canImport(AppKit)
import AppKit
#endif

#if !SKIP && canImport(PhotosUI)
import PhotosUI
#endif

#if !SKIP && canImport(UIKit)
import UIKit
#endif

#if !SKIP && canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

@Feature
public struct ImportImages {
    public init(
        onSave: @escaping ([ImportedImage]) async throws -> Void
    ) {
        self.onSave = onSave
    }

    public struct State {
        public init(
            configuration: Configuration,
            imageInfo: Spawn<ImageInfo>? = nil,
            images: [ImportedImage] = []
        ) {
            self.configuration = configuration
            self.imageInfo = imageInfo
            self.images = images
        }

        public init(
            configuration: Configuration,
            images: [ImportedImage]
        ) {
            self.init(
                configuration: configuration,
                imageInfo: nil,
                images: images
            )
        }

        public var configuration: Configuration
        public var errorMessage: String?
        public var imageInfo: Spawn<ImageInfo>?
        public var images: [ImportedImage]
        public var isImporting = false
        public var isSaving = false

        public var canSave: Bool {
            !images.isEmpty && !isImporting && !isSaving
        }

        mutating func append(_ importedImages: [ImportedImage]) {
            switch configuration.cardinality {
            case .single:
                images = importedImages.last.map { [$0] } ?? []
            case .multiple:
                images.append(contentsOf: importedImages)
            }
        }
    }

    public enum Action {
        case cancelButtonTapped
        case imageInfoButtonTapped(ImportedImage.ID)
        case imageImportFailed(String)
        case imageImportStarted
        case imagesImported([ImportedImage])
        case removeImageButtonTapped(ImportedImage.ID)
        case saveButtonTapped
    }

    let onSave: ([ImportedImage]) async throws -> Void

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .cancelButtonTapped:
                store.addTask {
                    try store.dismiss()
                }

            case let .imageInfoButtonTapped(id):
                guard let image = state.images.first(where: { $0.id == id }) else {
                    return
                }
                state.imageInfo = Spawn(
                    ImageInfo.State(
                        id: image.id,
                        asset: image.asset,
                        configuration: state.configuration.imageInfoConfiguration,
                        sourceLabel: image.sourceLabel
                    )
                )

            case let .imageImportFailed(message):
                state.errorMessage = message
                state.isImporting = false

            case .imageImportStarted:
                state.errorMessage = nil
                state.isImporting = true

            case let .imagesImported(images):
                state.append(images)
                state.errorMessage = nil
                state.isImporting = false

            case let .removeImageButtonTapped(id):
                state.images.removeAll { $0.id == id }

            case .saveButtonTapped:
                guard state.canSave else { return }

                let images = state.images.normalizingIncompleteAppearancePairs()
                state.errorMessage = nil
                state.isSaving = true

                store.addTask {
                    do {
                        try await onSave(images)
                        try store.dismiss()
                    } catch {
                        try store.modify {
                            $0.errorMessage = imageImportErrorMessage(error)
                            $0.isSaving = false
                        }
                    }
                }
            }
        }
        .ifLet(\.imageInfo) {
            ImageInfo { imageID, asset in
                try store.modify {
                    guard let index = $0.images.firstIndex(where: { $0.id == imageID }) else {
                        return
                    }
                    $0.images[index].asset = asset
                }
            }
        }
    }
}

public extension ImportImages {
    enum Cardinality: Equatable, Sendable {
        case single
        case multiple
    }

    struct Configuration: Equatable, Sendable {
        public init(
            cardinality: Cardinality,
            title: String,
            role: OMERecord.ImageAsset.Role,
            renderKind: OMERecord.ImageAsset.RenderKind,
            appearance: OMERecord.ImageAsset.Appearance? = nil,
            materializationPolicy: OMERecord.ImageAsset.MaterializationPolicy,
            imageInfoConfiguration: ImageInfo.Configuration? = nil
        ) {
            self.cardinality = cardinality
            self.title = title
            self.role = role
            self.renderKind = renderKind
            self.appearance = appearance
            self.materializationPolicy = materializationPolicy
            self.imageInfoConfiguration = imageInfoConfiguration ?? ImageInfo.Configuration(
                allowedRoles: [role],
                allowedRenderKinds: [renderKind],
                allowsAppearance: true,
                allowsMaterializationPolicy: true,
                allowedMaterializationPolicies: [materializationPolicy]
            )
        }

        public var cardinality: Cardinality
        public var imageInfoConfiguration: ImageInfo.Configuration
        public var title: String
        public var role: OMERecord.ImageAsset.Role
        public var renderKind: OMERecord.ImageAsset.RenderKind
        public var appearance: OMERecord.ImageAsset.Appearance?
        public var materializationPolicy: OMERecord.ImageAsset.MaterializationPolicy

        public static var calendarHero: Self {
            Self(
                cardinality: .single,
                title: "Choose Calendar Hero",
                role: .hero,
                renderKind: .fullImage,
                materializationPolicy: .lazy,
                imageInfoConfiguration: .calendarHero
            )
        }

        public static var calendarLogo: Self {
            Self(
                cardinality: .single,
                title: "Choose Calendar Logo",
                role: .logo,
                renderKind: .transparent,
                materializationPolicy: .lazy,
                imageInfoConfiguration: .calendarLogo
            )
        }

        public static var posters: Self {
            Self(
                cardinality: .multiple,
                title: "Add Posters",
                role: .poster,
                renderKind: .fullImage,
                materializationPolicy: .lazy,
                imageInfoConfiguration: .posters
            )
        }

        public static var contributorLogo: Self {
            Self(
                cardinality: .single,
                title: "Choose Contributor Logo",
                role: .logo,
                renderKind: .transparent,
                materializationPolicy: .lazy,
                imageInfoConfiguration: .contributorLogo
            )
        }

        public static var contributorPhoto: Self {
            Self(
                cardinality: .single,
                title: "Choose Contributor Photo",
                role: .photo,
                renderKind: .fullImage,
                materializationPolicy: .lazy,
                imageInfoConfiguration: .contributorPhoto
            )
        }

        public static var stageHero: Self {
            Self(
                cardinality: .single,
                title: "Choose Stage Hero",
                role: .hero,
                renderKind: .fullImage,
                materializationPolicy: .prefetchOnOpen,
                imageInfoConfiguration: .stageHero
            )
        }

        public static var stageLogo: Self {
            Self(
                cardinality: .single,
                title: "Choose Stage Logo",
                role: .logo,
                renderKind: .transparent,
                materializationPolicy: .prefetchOnOpen,
                imageInfoConfiguration: .stageLogo
            )
        }

        public static var stagePoster: Self {
            Self(
                cardinality: .multiple,
                title: "Choose Stage Posters",
                role: .poster,
                renderKind: .fullImage,
                materializationPolicy: .lazy,
                imageInfoConfiguration: .stagePoster
            )
        }

        var allowsMultipleSelection: Bool {
            cardinality == .multiple
        }

        func importedImage(
            id: UUID = UUID(),
            title: String? = nil,
            sourceName: String? = nil,
            sourceURL: URL? = nil,
            mimeType: String,
            data: Data
        ) -> ImportedImage {
            let asset = OMERecord.ImageAsset(
                source: .url(sourceURL ?? Self.transientImportSourceURL(id: id)),
                role: role,
                renderKind: renderKind,
                appearance: appearance,
                materializationPolicy: materializationPolicy
            )
            return ImportedImage(
                id: id,
                title: title,
                sourceName: sourceName,
                sourceURL: sourceURL,
                mimeType: mimeType,
                data: data,
                asset: asset
            )
        }

        private static func transientImportSourceURL(id: UUID) -> URL {
            URL(string: "open-music-event-import://\(id.uuidString)")!
        }
    }

    struct ImportedImage: Identifiable, Equatable, Sendable {
        public init(
            id: UUID = UUID(),
            title: String? = nil,
            sourceName: String? = nil,
            sourceURL: URL? = nil,
            mimeType: String,
            data: Data,
            asset: OMERecord.ImageAsset
        ) {
            self.id = id
            self.title = title ?? sourceName?.deletingPathExtension ?? ""
            self.sourceName = sourceName
            self.sourceURL = sourceURL
            self.mimeType = mimeType
            self.data = data
            self.asset = asset
        }

        public var asset: OMERecord.ImageAsset
        public var id: UUID
        public var title: String
        public var sourceName: String?
        public var sourceURL: URL?
        public var mimeType: String
        public var data: Data

        public var trimmedTitle: String {
            title.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        public var suggestedIDSource: String {
            trimmedTitle.nilIfEmpty
                ?? sourceName?.deletingPathExtension.nilIfEmpty
                ?? "poster"
        }

        public var sourceLabel: String {
            sourceName
                ?? sourceURL?.lastPathComponent
                ?? "Photos"
        }

        public var localImageImportRequest: LocalImageImportRequest {
            LocalImageImportRequest(
                data: data,
                mimeType: mimeType,
                sourceURL: sourceURL,
                role: asset.role,
                renderKind: asset.renderKind,
                appearance: asset.appearance,
                materializationPolicy: asset.materializationPolicy,
                thumbhash: asset.thumbhash,
                focalPoint: asset.focalPoint
            )
        }
    }
}

extension Collection where Element == ImportImages.ImportedImage {
    func normalizingIncompleteAppearancePairs() -> [ImportImages.ImportedImage] {
        zip(self, map(\.asset).normalizingIncompleteAppearancePairs())
            .map { importedImage, asset in
                var importedImage = importedImage
                importedImage.asset = asset
                return importedImage
            }
    }
}

private func imageImportErrorMessage(_ error: any Error) -> String {
    let description = error.localizedDescription
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !description.isEmpty else {
        return "Unable to import images."
    }
    return "Unable to import images: \(description)"
}

public struct ImportImagesView: View {
    @Bindable var store: StoreOf<ImportImages>
    @State var isFileImporterPresented = false

    #if !SKIP && canImport(PhotosUI)
    @State var selectedPhotoItems: [PhotosPickerItem] = []
    #endif

    public init(store: StoreOf<ImportImages>) {
        self.store = store
    }

    public var body: some View {
        Form {
            Section {
                importControls
            }

            if !store.images.isEmpty {
                Section("Images") {
                    ForEach($store.images) { $image in
                        ImportImageRowView(image: $image) {
                            store.send(.imageInfoButtonTapped(image.id))
                        } onRemove: {
                            store.send(.removeImageButtonTapped(image.id))
                        }
                    }
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
        .disabled(store.isSaving)
        .navigationTitle(store.configuration.title)
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
                    Button("Add") {
                        store.send(.saveButtonTapped)
                    }
                    .disabled(!store.canSave)
                }
            }
        }
        .importImagesFileImporter(
            isPresented: $isFileImporterPresented,
            allowsMultipleSelection: store.configuration.allowsMultipleSelection,
            onCompletion: fileImportCompleted
        )
        .sheet(isPresented: $store.imageInfo.isPresented) {
            if let imageInfoStore = store.spawn(\.imageInfo) {
                NavigationStack {
                    ImageInfoView(store: imageInfoStore)
                }
            }
        }
        #if !SKIP && canImport(PhotosUI)
        .onChange(of: selectedPhotoItems) { _, items in
            photoItemsChanged(items)
        }
        #endif
    }

    @ViewBuilder
    var importControls: some View {
        #if !SKIP && canImport(PhotosUI)
        PhotosPicker(
            selection: $selectedPhotoItems,
            maxSelectionCount: store.configuration.allowsMultipleSelection ? nil : 1,
            matching: .images
        ) {
            Label("Choose Photos", systemImage: "photo.on.rectangle")
        }
        #endif

        #if !SKIP && canImport(UniformTypeIdentifiers)
        Button {
            isFileImporterPresented = true
        } label: {
            Label("Choose Files", systemImage: "folder")
        }
        #endif

        #if SKIP || (!canImport(PhotosUI) && !canImport(UniformTypeIdentifiers))
        ContentUnavailableView(
            "Image Import",
            systemImage: "photo",
            description: Text("Image import is not available on this platform yet.")
        )
        #endif
    }

    #if !SKIP && canImport(UniformTypeIdentifiers)
    func fileImportCompleted(_ result: Result<[URL], any Error>) {
        switch result {
        case let .success(urls):
            do {
                let images = try urls.map(importedImage(from:))
                if !images.isEmpty {
                    store.send(.imagesImported(images))
                }
            } catch {
                store.send(.imageImportFailed("Unable to import selected files."))
            }

        case .failure:
            store.send(.imageImportFailed("Unable to import selected files."))
        }
    }

    func importedImage(from url: URL) throws -> ImportImages.ImportedImage {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return store.configuration.importedImage(
            sourceName: url.lastPathComponent,
            sourceURL: url,
            mimeType: imageMimeType(for: url),
            data: try Data(contentsOf: url)
        )
    }

    func imageMimeType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension),
           let mimeType = type.preferredMIMEType {
            return mimeType
        }
        return fallbackImageMimeType(forPathExtension: url.pathExtension)
    }
    #endif

    #if !SKIP && canImport(PhotosUI)
    func photoItemsChanged(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        store.send(.imageImportStarted)

        Task {
            var importedImages: [ImportImages.ImportedImage] = []
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    continue
                }
                importedImages.append(
                    store.configuration.importedImage(
                        sourceName: nil,
                        sourceURL: nil,
                        mimeType: item.supportedContentTypes.first?.preferredMIMEType ?? "application/octet-stream",
                        data: data
                    )
                )
            }

            await MainActor.run {
                selectedPhotoItems = []
                if importedImages.isEmpty {
                    store.send(.imageImportFailed("Unable to import selected photos."))
                } else {
                    store.send(.imagesImported(importedImages))
                }
            }
        }
    }
    #endif
}

struct ImportImageRowView: View {
    @Binding var image: ImportImages.ImportedImage
    let onEditInfo: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ImportedImageThumbnail(data: image.data)
                .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 6) {
                TextField("Title", text: $image.title)

                Text(image.sourceLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                onEditInfo()
            } label: {
                Image(systemName: "info.circle")
                    .accessibilityLabel("Image Info")
            }
            .buttonStyle(.borderless)

            Button(role: .destructive) {
                onRemove()
            } label: {
                Image(systemName: "trash")
                    .accessibilityLabel("Remove Image")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

struct ImportedImageThumbnail: View {
    let data: Data

    var body: some View {
        Group {
            #if !SKIP && canImport(UIKit)
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
            #elseif !SKIP && canImport(AppKit)
            if let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
            #else
            placeholder
            #endif
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    var placeholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(.secondary.opacity(0.12))
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
    }
}

extension View {
    @ViewBuilder
    func importImagesFileImporter(
        isPresented: Binding<Bool>,
        allowsMultipleSelection: Bool,
        onCompletion: @escaping (Result<[URL], any Error>) -> Void
    ) -> some View {
        #if !SKIP && canImport(UniformTypeIdentifiers)
        self.fileImporter(
            isPresented: isPresented,
            allowedContentTypes: [.image],
            allowsMultipleSelection: allowsMultipleSelection,
            onCompletion: onCompletion
        )
        #else
        self
        #endif
    }
}

func fallbackImageMimeType(forPathExtension pathExtension: String) -> String {
    switch pathExtension.lowercased() {
    case "png":
        return "image/png"
    case "jpg", "jpeg":
        return "image/jpeg"
    case "webp":
        return "image/webp"
    case "gif":
        return "image/gif"
    case "svg":
        return "image/svg+xml"
    default:
        return "application/octet-stream"
    }
}

private extension String {
    var deletingPathExtension: String {
        (self as NSString).deletingPathExtension
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
